//
//  AriaM3U8Downloader.swift
//  AriaM3U8Downloader
//
//  Created by 神崎H亚里亚 on 2019/11/28.
//  Copyright © 2019 moxcomic. All rights reserved.
//
//  公开门面（@MainActor）。对外以 `AsyncStream<DownloadEvent>` 统一替代旧版 11 个 block 回调
//  + tagged NotificationCenter 通知；内部驱动 `actor DownloadEngine`。已彻底去除 RxSwift / @objc。
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class AriaM3U8Downloader {
    private let engine: DownloadEngine
    private let configuration: DownloadConfiguration

    private let eventStream: AsyncStream<DownloadEvent>
    private let eventContinuation: AsyncStream<DownloadEvent>.Continuation
    private var driveTask: Task<Void, Never>?
    private let observerBox = LifecycleObserverBox()

    /// 当前下载状态。
    public private(set) var status: DownloadStatus = .ready

    /// 下载事件流。请在 `start()` 前后 `for await` 消费（单消费者）。
    public var events: AsyncStream<DownloadEvent> { eventStream }

    /// 创建下载器。
    /// - Parameters:
    ///   - url: m3u8 地址
    ///   - outputDirectory: 输出目录
    ///   - configuration: 下载配置
    public init(url: URL, outputDirectory: URL, configuration: DownloadConfiguration = .init()) {
        self.configuration = configuration
        self.engine = DownloadEngine(sourceURL: url, outputDirectory: outputDirectory, config: configuration)
        (self.eventStream, self.eventContinuation) = AsyncStream<DownloadEvent>.makeStream(bufferingPolicy: .unbounded)
        if configuration.autoPauseOnBackground { observeLifecycle() }
    }

    /// 便捷构造（字符串 URL + 字符串路径）。
    public convenience init?(urlString: String, outputPath: String, configuration: DownloadConfiguration = .init()) {
        guard let url = URL(string: urlString) else { return nil }
        self.init(url: url, outputDirectory: URL(fileURLWithPath: outputPath), configuration: configuration)
    }

    // MARK: - 控制

    /// 开始下载。
    public func start() {
        guard status == .ready else { return }
        status = .downloading
        driveTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.engine.run()
            for await event in stream {
                self.apply(event)
                self.eventContinuation.yield(event)
            }
            self.eventContinuation.finish()
            self.removeLifecycleObservers()
        }
    }

    /// 暂停（停止派发新切片，已在途的继续完成）。
    public func pause() {
        Task { await engine.pause() }
    }

    /// 恢复。
    public func resume() {
        Task { await engine.resume() }
    }

    /// 取消。
    public func cancel() {
        Task { await engine.cancel() }
    }

    // MARK: - 本地播放文件

    /// 生成包含全部切片的本地 index.m3u8（替代旧 `createLocalM3U8File()`）。
    public func makeLocalPlaylist() async throws {
        try await engine.writeLocalPlaylist(segmentCount: nil)
    }

    /// 生成仅含“已下载切片”的本地 index.m3u8，用于边下边播（替代旧 `createTempLocalM3U8File()`）。
    public func makeLocalPlaylistForDownloaded() async throws {
        let count = await engine.downloadedCount()
        try await engine.writeLocalPlaylist(segmentCount: count)
    }

    // MARK: - 内部

    private func apply(_ event: DownloadEvent) {
        switch event {
        case .started: status = .downloading
        case .paused: status = .paused
        case .resumed: status = .downloading
        case .cancelled: status = .cancelled
        case .completed: status = .completed
        case .failed: status = .failed
        case .progress, .segmentCompleted, .segmentFailed: break
        }
    }

    private func observeLifecycle() {
        #if canImport(UIKit)
        let engine = self.engine
        let center = NotificationCenter.default
        let background = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { _ in
            Task { await engine.pause() }
        }
        let foreground = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { await engine.resume() }
        }
        observerBox.tokens = [background, foreground]
        #endif
    }

    private func removeLifecycleObservers() {
        observerBox.removeAll()
    }
}

/// 生命周期观察者令牌容器：以独立类承载 `NSObjectProtocol` 令牌，
/// 由其自身（非隔离）deinit 负责注销，避免在 @MainActor 类的 deinit 中触碰隔离状态。
private final class LifecycleObserverBox: @unchecked Sendable {
    var tokens: [NSObjectProtocol] = []

    func removeAll() {
        let center = NotificationCenter.default
        for token in tokens { center.removeObserver(token) }
        tokens.removeAll()
    }

    deinit { removeAll() }
}
