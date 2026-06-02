//
//  M3U8Playlist.swift
//  AriaM3U8Downloader
//
//  M3U8 播放列表值类型模型，替代旧 `M3U8Entity`（class: NSObject + 隐式解包可选）。
//  纯 `Sendable` 值类型，可安全跨 actor 传递。
//

import Foundation

/// 加密 KEY 信息（对应 #EXT-X-KEY）。
public struct M3U8Key: Sendable {
    /// 加密方法（如 AES-128）
    public var method: String
    /// KEY URI（完整 http 地址，或相对的文件名）
    public var uri: String
    /// 初始化向量（可选）
    public var iv: String?

    public init(method: String, uri: String, iv: String? = nil) {
        self.method = method
        self.uri = uri
        self.iv = iv
    }
}

/// 解析后的媒体播放列表。仅承载“解析所得的不可变数据”；
/// 下载过程中的运行态（已完成数、失败列表）由 `DownloadEngine` 持有。
public struct M3U8Playlist: Sendable {
    public var version: Int = 0
    public var targetDuration: Int = 0
    public var mediaSequence: Int = 0
    public var playlistType: String?
    public var key: M3U8Key?
    /// 各切片时长（对应 #EXTINF）
    public var durations: [Double] = []
    /// 切片文件名列表（取自每行最后一个路径分量）
    public var segments: [String] = []

    public init() {}
}

/// 本地 index.m3u8 播放文件写出器（替代旧 `createLocalM3U8File`）。
enum M3U8PlaylistWriter {
    /// 写出可本地播放的 index.m3u8。
    /// - Parameters:
    ///   - playlist: 播放列表
    ///   - directory: 输出目录
    ///   - segmentCount: 写入的切片数量；nil 表示全部
    static func write(playlist: M3U8Playlist, to directory: URL, segmentCount: Int?) throws {
        let requested = segmentCount ?? playlist.segments.count
        // 防御：不越界（durations 与 segments 取较小者）
        let count = max(0, min(requested, min(playlist.segments.count, playlist.durations.count)))

        var text = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:60

        """
        if let key = playlist.key {
            var line = "#EXT-X-KEY:METHOD=\(key.method),URI=\"\(key.uri)\""
            if let iv = key.iv { line += ",IV=\(iv)" }
            text += line + "\n"
        }
        for i in 0..<count {
            text += "#EXTINF:\(playlist.durations[i]),\n\(playlist.segments[i])\n"
        }
        text += "#EXT-X-ENDLIST"

        guard let data = text.data(using: .utf8) else {
            throw AriaError("生成本地 m3u8 失败：编码错误")
        }
        let file = directory.appendingPathComponent("index.m3u8")
        try data.write(to: file)
    }
}
