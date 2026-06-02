//
//  AriaNetworking.swift
//  AriaM3U8Downloader
//
//  网络层（基于 Alamofire 5.12 的 async/await API）。替代旧 `AriaBackgroundManager` + RxAlamofire。
//  `Session` 为 `@unchecked Sendable`，故本类型可作为 `Sendable` 值安全跨 actor 使用。
//

import Foundation
import Alamofire

struct AriaNetworking: Sendable {
    private let session: Session

    init(timeout: TimeInterval) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpAdditionalHeaders = HTTPHeaders.default.dictionary
        session = Session(configuration: configuration)
    }

    /// 拉取文本（m3u8 清单）。
    func text(from url: URL) async throws -> String {
        try await session.request(url).serializingString().value
    }

    /// 下载文件到指定目标路径。
    @discardableResult
    func download(from url: URL, to destination: URL) async throws -> URL {
        let dest: DownloadRequest.Destination = { _, _ in
            (destination, [.removePreviousFile, .createIntermediateDirectories])
        }
        return try await session.download(url, to: dest).serializingDownloadedFileURL().value
    }

    /// 试探某 URL 是否可访问（用于推断正确的切片前缀）。
    func exists(_ url: URL) async -> Bool {
        do {
            _ = try await session.request(url).serializingData().value
            return true
        } catch {
            return false
        }
    }
}
