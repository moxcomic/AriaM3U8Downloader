//
//  M3U8Parser.swift
//  AriaM3U8Downloader
//
//  M3U8 文本解析与切片前缀推断。逻辑迁移自旧 `AriaM3U8Downloader` 的
//  analysisClips / getTruePrefix / getURLClips，改为纯函数 + async（去 Rx）。
//

import Foundation

enum M3U8Parser {
    /// 是否为 master playlist（含多码率变体）。
    static func isMasterPlaylist(_ text: String) -> Bool {
        text.contains("#EXT-X-STREAM-INF")
    }

    /// 取 master playlist 中第一个变体（以 .m3u8 结尾的行）。
    static func firstVariant(in text: String) -> String? {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasSuffix(".m3u8") }
    }

    /// 解析媒体播放列表文本。
    static func parseMedia(text: String) throws -> M3U8Playlist {
        var playlist = M3U8Playlist()
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if line.hasPrefix("#EXT-X-VERSION:") {
                if let v = Int(line.replacingOccurrences(of: "#EXT-X-VERSION:", with: "")) { playlist.version = v }
            } else if line.hasPrefix("#EXT-X-TARGETDURATION:") {
                if let v = Int(line.replacingOccurrences(of: "#EXT-X-TARGETDURATION:", with: "")) { playlist.targetDuration = v }
            } else if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                if let v = Int(line.replacingOccurrences(of: "#EXT-X-MEDIA-SEQUENCE:", with: "")) { playlist.mediaSequence = v }
            } else if line.hasPrefix("#EXT-X-PLAYLIST-TYPE:") {
                playlist.playlistType = line.replacingOccurrences(of: "#EXT-X-PLAYLIST-TYPE:", with: "")
            } else if line.hasPrefix("#EXT-X-KEY:") {
                playlist.key = parseKey(line)
            } else if line.hasPrefix("#EXTINF:") {
                let value = line
                    .replacingOccurrences(of: "#EXTINF:", with: "")
                    .replacingOccurrences(of: ",", with: "")
                if let d = Double(value) { playlist.durations.append(d) }
            } else if line.hasSuffix(".ts") {
                playlist.segments.append(String(line.components(separatedBy: "/").last ?? line))
            }
        }

        guard !playlist.segments.isEmpty else {
            throw AriaError("获取 M3U8 内容失败：未找到 TS 切片")
        }
        return playlist
    }

    /// 解析 #EXT-X-KEY 行（METHOD / URI / IV）。
    /// 基于属性提取，正确处理引号闭合与 IV 缺省（修正旧逻辑在无 IV 时残留尾引号的缺陷）。
    private static func parseKey(_ line: String) -> M3U8Key? {
        let value = line.replacingOccurrences(of: "#EXT-X-KEY:", with: "")

        // METHOD（取到下一个逗号）
        guard let methodRange = value.range(of: "METHOD=") else { return nil }
        let method = String(value[methodRange.upperBound...].prefix { $0 != "," })

        // URI（取双引号内内容）
        var uri = ""
        if let uriRange = value.range(of: "URI=\"") {
            let afterOpenQuote = value[uriRange.upperBound...]
            if let closeQuote = afterOpenQuote.firstIndex(of: "\"") {
                let rawURI = String(afterOpenQuote[..<closeQuote])
                uri = rawURI.hasPrefix("http") ? rawURI : (rawURI.components(separatedBy: "/").last ?? rawURI)
            }
        }

        guard !method.isEmpty, !uri.isEmpty else { return nil }

        // IV（可选，取到下一个逗号）
        var iv: String?
        if let ivRange = value.range(of: "IV=") {
            let raw = String(value[ivRange.upperBound...].prefix { $0 != "," })
            if !raw.isEmpty { iv = raw }
        }

        return M3U8Key(method: method, uri: uri, iv: iv)
    }

    /// 由基准 URL 生成候选前缀（host 根逐级到各层目录，排除 .m3u8 段）。
    static func candidatePrefixes(for base: URL) -> [String] {
        guard let scheme = base.scheme, let host = base.host else { return [] }
        let portSuffix = base.port.map { ":\($0)" } ?? ""
        let root = "\(scheme)://\(host)\(portSuffix)"
        let comps = base.path
            .components(separatedBy: "/")
            .filter { !$0.isEmpty && !$0.hasSuffix(".m3u8") }

        var clips = [root]
        for i in comps.indices {
            clips.append(root + "/" + comps[0...i].joined(separator: "/"))
        }
        return clips
    }

    /// 通过试探找出能正确拼出首个切片的前缀目录。
    static func resolvePrefix(base: URL, sampleSegment: String, networking: AriaNetworking) async -> URL? {
        for clip in candidatePrefixes(for: base) {
            let segmentPath = sampleSegment.hasPrefix("/") ? sampleSegment : "/\(sampleSegment)"
            guard let candidate = URL(string: clip + segmentPath) else { continue }
            if await networking.exists(candidate) {
                return URL(string: clip)
            }
        }
        return nil
    }
}
