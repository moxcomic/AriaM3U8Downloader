//
//  DownloadEngine.swift
//  AriaM3U8Downloader
//
//  下载引擎：以 actor 收敛全部可变状态（替代旧 OperationQueue + DispatchSemaphore +
//  跨线程共享变量），用 TaskGroup 滑动窗口限流并发下载，事件经 AsyncStream 输出。
//

import Foundation

actor DownloadEngine {
    private let sourceURL: URL
    private let outputDirectory: URL
    private let config: DownloadConfiguration
    private let networking: AriaNetworking

    private var playlist = M3U8Playlist()
    private var resolvedPrefix: URL?
    private var completedCount = 0
    private var failedSegments: [String] = []

    private var running = false
    private var paused = false
    private var cancelled = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var emitter: AsyncStream<DownloadEvent>.Continuation?

    init(sourceURL: URL, outputDirectory: URL, config: DownloadConfiguration) {
        self.sourceURL = sourceURL
        self.outputDirectory = outputDirectory
        self.config = config
        self.networking = AriaNetworking(timeout: config.requestTimeout)
    }

    // MARK: - 事件流

    /// 启动下载，返回事件流。调用方逐个 `for await` 消费。
    func run() -> AsyncStream<DownloadEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task { await self.execute(emitting: continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - 控制

    func pause() {
        guard running, !paused, !cancelled else { return }
        paused = true
        emitter?.yield(.paused)
    }

    func resume() {
        guard running, paused, !cancelled else { return }
        paused = false
        resumeWaiters()
        emitter?.yield(.resumed)
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        paused = false
        resumeWaiters()
    }

    private func resumeWaiters() {
        let waiters = pauseWaiters
        pauseWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func waitWhilePaused() async {
        guard paused, !cancelled else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if !paused || cancelled {
                continuation.resume()
            } else {
                pauseWaiters.append(continuation)
            }
        }
    }

    // MARK: - 只读快照

    /// 当前已完成的切片数（用于“边下边播”生成临时播放文件）。
    func downloadedCount() -> Int { completedCount }

    /// 写出本地可播放的 index.m3u8。
    /// - Parameter segmentCount: nil 表示全部切片；否则仅写入前 N 个。
    func writeLocalPlaylist(segmentCount: Int?) throws {
        try M3U8PlaylistWriter.write(playlist: playlist, to: outputDirectory, segmentCount: segmentCount)
    }

    // MARK: - 执行

    private func execute(emitting continuation: AsyncStream<DownloadEvent>.Continuation) async {
        emitter = continuation
        running = true
        defer {
            running = false
            emitter = nil
            continuation.finish()
        }

        do {
            try await prepare()
            continuation.yield(.started)
            if let key = playlist.key { await downloadKey(key) }
            await downloadSegments(emitting: continuation)

            if cancelled {
                continuation.yield(.cancelled)
                return
            }
            try? writeLocalPlaylist(segmentCount: nil)
            continuation.yield(.progress(1.0))
            continuation.yield(.completed)
        } catch {
            if cancelled {
                continuation.yield(.cancelled)
            } else {
                continuation.yield(.failed(String(describing: error)))
            }
        }
    }

    private func prepare() async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let text = try await networking.text(from: sourceURL)

        if M3U8Parser.isMasterPlaylist(text) {
            guard let variant = M3U8Parser.firstVariant(in: text) else {
                throw AriaError("获取 M3U8 切片失败：master playlist 未找到变体")
            }
            let variantURL = try await resolveVariantURL(variant)
            let variantText = try await networking.text(from: variantURL)
            playlist = try M3U8Parser.parseMedia(text: variantText)
            resolvedPrefix = await M3U8Parser.resolvePrefix(
                base: variantURL, sampleSegment: playlist.segments[0], networking: networking
            ) ?? variantURL.deletingLastPathComponent()
        } else {
            playlist = try M3U8Parser.parseMedia(text: text)
            resolvedPrefix = await M3U8Parser.resolvePrefix(
                base: sourceURL, sampleSegment: playlist.segments[0], networking: networking
            ) ?? sourceURL.deletingLastPathComponent()
        }
    }

    private func resolveVariantURL(_ variant: String) async throws -> URL {
        if variant.hasPrefix("http"), let url = URL(string: variant) {
            return url
        }
        if let prefix = await M3U8Parser.resolvePrefix(base: sourceURL, sampleSegment: variant, networking: networking) {
            return prefix.appendingPathComponent(variant)
        }
        return sourceURL.deletingLastPathComponent().appendingPathComponent(variant)
    }

    private func downloadKey(_ key: M3U8Key) async {
        let keyURL: URL?
        if key.uri.hasPrefix("http") {
            keyURL = URL(string: key.uri)
        } else {
            keyURL = resolvedPrefix?.appendingPathComponent(key.uri)
        }
        guard let url = keyURL else { return }
        let destination = outputDirectory.appendingPathComponent(url.lastPathComponent)
        _ = try? await networking.download(from: url, to: destination)
    }

    // MARK: - 切片并发下载

    private enum SegmentOutcome: Sendable {
        case completed(String)
        case failed(String)
        var isFailure: Bool { if case .failed = self { return true } else { return false } }
    }

    private func downloadSegments(emitting continuation: AsyncStream<DownloadEvent>.Continuation) async {
        let total = playlist.segments.count
        guard total > 0 else { return }
        let window = max(1, config.maxConcurrentDownloads)
        var index = 0

        await withTaskGroup(of: SegmentOutcome.self) { group in
            func enqueueNext() async -> Bool {
                while index < total {
                    await waitWhilePaused()
                    if cancelled { return false }
                    let name = playlist.segments[index]
                    index += 1
                    group.addTask { await self.downloadOne(name: name) }
                    return true
                }
                return false
            }

            var inFlight = 0
            for _ in 0..<window {
                if await enqueueNext() { inFlight += 1 }
            }

            while inFlight > 0 {
                guard let outcome = await group.next() else { break }
                inFlight -= 1
                handle(outcome, total: total, emitting: continuation)
                if cancelled || (config.failFast && outcome.isFailure) {
                    group.cancelAll()
                    break
                }
                if await enqueueNext() { inFlight += 1 }
            }

            // 取消/快速失败后清空剩余任务
            for await outcome in group {
                handle(outcome, total: total, emitting: continuation)
            }
        }
    }

    private func handle(_ outcome: SegmentOutcome, total: Int, emitting continuation: AsyncStream<DownloadEvent>.Continuation) {
        guard !cancelled else { return }
        switch outcome {
        case .completed(let name):
            completedCount += 1
            continuation.yield(.segmentCompleted(name: name, completed: completedCount, total: total))
            continuation.yield(.progress(total == 0 ? 1 : Double(completedCount) / Double(total)))
        case .failed(let name):
            failedSegments.append(name)
            continuation.yield(.segmentFailed(name: name))
        }
    }

    private func downloadOne(name: String) async -> SegmentOutcome {
        let destination = outputDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) {
            return .completed(name)
        }
        guard let prefix = resolvedPrefix else { return .failed(name) }
        let url = prefix.appendingPathComponent(name)

        var attempt = 0
        while !cancelled {
            do {
                _ = try await networking.download(from: url, to: destination)
                return .completed(name)
            } catch {
                attempt += 1
                if attempt > max(0, config.retryCount) { return .failed(name) }
            }
        }
        return .failed(name)
    }
}
