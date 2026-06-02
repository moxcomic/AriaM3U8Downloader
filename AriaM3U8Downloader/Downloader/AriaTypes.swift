//
//  AriaTypes.swift
//  AriaM3U8Downloader
//
//  公开类型：下载状态、事件流元素、错误、配置。
//  迁移自旧 AriaGlobal.swift —— 去掉 Rx 与 NotificationCenter，改为纯 Swift Concurrency 友好的 Sendable 类型。
//

import Foundation

/// 下载状态。相比旧 `AriaDownloadStatus` 删除了无意义的 `isStart` 死态。
public enum DownloadStatus: Sendable, Equatable {
    /// 尚未准备好
    case notReady
    /// 已就绪，可开始
    case ready
    /// 下载中
    case downloading
    /// 已暂停
    case paused
    /// 已取消
    case cancelled
    /// 已完成
    case completed
    /// 失败
    case failed
}

/// 下载过程事件。统一替代旧版 11 个 block 回调 + tagged `NotificationCenter` 通知。
public enum DownloadEvent: Sendable {
    /// 任务开始（已解析完播放列表，开始下载切片）
    case started
    /// 整体进度，范围 0...1
    case progress(Double)
    /// 单个切片下载完成
    /// - Parameters:
    ///   - name: 切片文件名
    ///   - completed: 已完成数量
    ///   - total: 切片总数
    case segmentCompleted(name: String, completed: Int, total: Int)
    /// 单个切片下载失败（默认容错继续）
    case segmentFailed(name: String)
    /// 已暂停
    case paused
    /// 已恢复
    case resumed
    /// 已取消
    case cancelled
    /// 全部完成
    case completed
    /// 失败终止（含错误描述）
    case failed(String)
}

/// 库错误类型。
public struct AriaError: Error, Sendable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
    public var localizedDescription: String { message }
}

/// 下载配置。
public struct DownloadConfiguration: Sendable {
    /// 最大并发下载数（替代旧 `OperationQueue.maxConcurrentOperationCount`），默认 3
    public var maxConcurrentDownloads: Int
    /// 单请求 / 资源超时（秒），默认 10
    public var requestTimeout: TimeInterval
    /// 单切片失败重试次数，默认 1
    public var retryCount: Int
    /// 是否“一片失败即整体取消”，默认 false（容错继续）
    public var failFast: Bool
    /// App 进入后台是否自动暂停、回前台自动恢复，默认 true（与旧版行为一致）
    public var autoPauseOnBackground: Bool

    public init(
        maxConcurrentDownloads: Int = 3,
        requestTimeout: TimeInterval = 10,
        retryCount: Int = 1,
        failFast: Bool = false,
        autoPauseOnBackground: Bool = true
    ) {
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.requestTimeout = requestTimeout
        self.retryCount = retryCount
        self.failFast = failFast
        self.autoPauseOnBackground = autoPauseOnBackground
    }
}
