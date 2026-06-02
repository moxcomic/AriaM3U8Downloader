//
//  AriaM3U8LocalServer.swift
//  AriaM3U8Downloader
//
//  Created by 神崎H亚里亚 on 2019/11/29.
//  Copyright © 2019 moxcomic. All rights reserved.
//
//  本地播放 HTTP 服务。替代旧 GCDWebServer（已归档、无 SPM）——改用 Network.framework
//  自建极简 HTTP/1.1 静态文件服务，支持 Range（视频 seek 必需），零第三方依赖。
//

import Foundation
import Network
import AriaM3U8Downloader

public final class AriaM3U8LocalServer: @unchecked Sendable {
    public static let shared = AriaM3U8LocalServer()

    private let queue = DispatchQueue(label: "com.moxcomic.AriaM3U8LocalServer", attributes: .concurrent)
    private let lock = NSLock()
    private var listener: NWListener?
    private var rootPath: String?
    private var servingPort: UInt16 = 8080

    public init() {}

    /// 开启本地服务。
    /// - Parameters:
    ///   - path: 需要开放的目录
    ///   - port: 端口，默认 8080
    public func start(path: String, port: UInt16 = 8080) throws {
        lock.lock()
        defer { lock.unlock() }
        if listener != nil {
            #if DEBUG
            print("本地服务已开启,请勿重复开启")
            #endif
            return
        }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw AriaError("端口非法: \(port)")
        }
        let listener = try NWListener(using: .tcp, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { state in
            #if DEBUG
            if case .failed(let error) = state { print("本地服务失败: \(error)") }
            #endif
        }
        listener.start(queue: queue)
        self.listener = listener
        self.rootPath = path
        self.servingPort = port
    }

    /// 停止本地服务。
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        listener?.cancel()
        listener = nil
        rootPath = nil
    }

    /// 获取本地服务 URL（拼接需以 / 开头）。
    public func localServerURLString() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard listener != nil else { return nil }
        return "http://localhost:\(servingPort)"
    }

    private func currentRoot() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return rootPath
    }

    // MARK: - 连接处理

    private func handle(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled: connection.cancel()
            default: break
            }
        }
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var accumulated = buffer
            if let data { accumulated.append(data) }

            if let headerRange = accumulated.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = accumulated.subdata(in: accumulated.startIndex..<headerRange.lowerBound)
                self.respond(connection, headerData: headerData)
            } else if isComplete || error != nil || accumulated.count > 1_048_576 {
                connection.cancel()
            } else {
                self.receive(connection, buffer: accumulated)
            }
        }
    }

    private func respond(_ connection: NWConnection, headerData: Data) {
        guard let header = String(data: headerData, encoding: .utf8) else {
            send(connection, status: "400 Bad Request"); return
        }
        let lines = header.components(separatedBy: "\r\n")
        let requestLine = lines.first?.components(separatedBy: " ") ?? []
        guard requestLine.count >= 2 else {
            send(connection, status: "400 Bad Request"); return
        }
        let method = requestLine[0]
        guard method == "GET" || method == "HEAD" else {
            send(connection, status: "405 Method Not Allowed"); return
        }

        var path = requestLine[1]
        if let queryIndex = path.firstIndex(of: "?") { path = String(path[..<queryIndex]) }
        let decoded = path.removingPercentEncoding ?? path

        var rangeHeader: String?
        for line in lines.dropFirst() where line.lowercased().hasPrefix("range:") {
            rangeHeader = String(line.dropFirst("range:".count)).trimmingCharacters(in: .whitespaces)
        }

        guard let root = currentRoot() else {
            send(connection, status: "404 Not Found"); return
        }
        let safePath = sanitize(decoded)
        let fileURL = URL(fileURLWithPath: root).appendingPathComponent(safePath)
        serveFile(connection, fileURL: fileURL, rangeHeader: rangeHeader, includeBody: method == "GET")
    }

    private func serveFile(_ connection: NWConnection, fileURL: URL, rangeHeader: String?, includeBody: Bool) {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            send(connection, status: "404 Not Found"); return
        }
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
            let fileSize = (attributes[.size] as? NSNumber)?.intValue,
            let handle = try? FileHandle(forReadingFrom: fileURL)
        else {
            send(connection, status: "500 Internal Server Error"); return
        }
        defer { try? handle.close() }

        var start = 0
        var end = fileSize - 1
        var status = "200 OK"
        var isPartial = false
        if let rangeHeader, let parsed = parseRange(rangeHeader, fileSize: fileSize) {
            start = parsed.lowerBound
            end = parsed.upperBound
            status = "206 Partial Content"
            isPartial = true
        }
        let length = max(0, end - start + 1)

        var body = Data()
        if includeBody && length > 0 {
            do {
                try handle.seek(toOffset: UInt64(start))
                body = try handle.read(upToCount: length) ?? Data()
            } catch {
                send(connection, status: "500 Internal Server Error"); return
            }
        }

        var headers = "HTTP/1.1 \(status)\r\n"
        headers += "Content-Type: \(mimeType(for: fileURL.pathExtension))\r\n"
        headers += "Content-Length: \(length)\r\n"
        headers += "Accept-Ranges: bytes\r\n"
        if isPartial { headers += "Content-Range: bytes \(start)-\(end)/\(fileSize)\r\n" }
        headers += "Connection: close\r\n\r\n"

        var response = Data(headers.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func send(_ connection: NWConnection, status: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: - 工具

    /// 防目录穿越：剔除空段、`.`、`..`。
    private func sanitize(_ path: String) -> String {
        path.components(separatedBy: "/")
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
            .joined(separator: "/")
    }

    /// 解析 Range 头：bytes=START-END / bytes=START- / bytes=-SUFFIX。
    private func parseRange(_ header: String, fileSize: Int) -> ClosedRange<Int>? {
        guard header.hasPrefix("bytes="), fileSize > 0 else { return nil }
        let spec = header.dropFirst("bytes=".count)
        let parts = spec.components(separatedBy: "-")
        guard parts.count == 2 else { return nil }

        let startText = parts[0]
        let endText = parts[1]

        if startText.isEmpty {
            guard let suffix = Int(endText), suffix > 0 else { return nil }
            let start = max(0, fileSize - suffix)
            return start...(fileSize - 1)
        }
        guard let start = Int(startText), start < fileSize else { return nil }
        let end = endText.isEmpty ? (fileSize - 1) : min(Int(endText) ?? (fileSize - 1), fileSize - 1)
        guard start <= end else { return nil }
        return start...end
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "m3u8": return "application/vnd.apple.mpegurl"
        case "ts": return "video/mp2t"
        case "mp4", "m4s": return "video/mp4"
        case "key": return "application/octet-stream"
        case "aac": return "audio/aac"
        case "mp3": return "audio/mpeg"
        default: return "application/octet-stream"
        }
    }
}
