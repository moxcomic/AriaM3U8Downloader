import XCTest
@testable import AriaM3U8Downloader

/// 解析与本地播放文件写出的单元测试（纯函数，无需联网）。
/// 用于验证迁移后解析行为与旧版 analysisClips/parseKey/getURLClips 保持一致。
final class M3U8ParserTests: XCTestCase {

    func testParseMediaPlaylist() throws {
        let text = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:10
        #EXT-X-MEDIA-SEQUENCE:0
        #EXTINF:9.009,
        /seg/0.ts
        #EXTINF:8.5,
        /seg/1.ts
        #EXT-X-ENDLIST
        """
        let playlist = try M3U8Parser.parseMedia(text: text)
        XCTAssertEqual(playlist.version, 3)
        XCTAssertEqual(playlist.targetDuration, 10)
        XCTAssertEqual(playlist.mediaSequence, 0)
        XCTAssertEqual(playlist.segments, ["0.ts", "1.ts"])
        XCTAssertEqual(playlist.durations.count, 2)
        XCTAssertEqual(playlist.durations.first ?? 0, 9.009, accuracy: 0.0001)
    }

    func testParseKeyAbsoluteURI() throws {
        let text = """
        #EXTM3U
        #EXT-X-KEY:METHOD=AES-128,URI="https://example.com/enc.key",IV=0x123
        #EXTINF:5.0,
        0.ts
        """
        let key = try XCTUnwrap(try M3U8Parser.parseMedia(text: text).key)
        XCTAssertEqual(key.method, "AES-128")
        XCTAssertEqual(key.uri, "https://example.com/enc.key")
        XCTAssertEqual(key.iv, "0x123")
    }

    func testParseKeyRelativeURITakesLastComponent() throws {
        let text = """
        #EXTM3U
        #EXT-X-KEY:METHOD=AES-128,URI="/path/enc.key"
        #EXTINF:5.0,
        0.ts
        """
        let key = try XCTUnwrap(try M3U8Parser.parseMedia(text: text).key)
        XCTAssertEqual(key.uri, "enc.key")
        XCTAssertNil(key.iv)
    }

    func testParseThrowsWhenNoSegments() {
        let text = "#EXTM3U\n#EXT-X-VERSION:3\n"
        XCTAssertThrowsError(try M3U8Parser.parseMedia(text: text))
    }

    func testMasterPlaylistDetectionAndVariant() {
        let master = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=800000\nlow.m3u8\n"
        XCTAssertTrue(M3U8Parser.isMasterPlaylist(master))
        XCTAssertEqual(M3U8Parser.firstVariant(in: master), "low.m3u8")
        XCTAssertFalse(M3U8Parser.isMasterPlaylist("#EXTM3U\n#EXTINF:1,\n0.ts"))
    }

    func testCandidatePrefixesProgression() {
        let url = URL(string: "https://cdn.example.com/a/b/index.m3u8")!
        let prefixes = M3U8Parser.candidatePrefixes(for: url)
        XCTAssertEqual(prefixes.first, "https://cdn.example.com")
        XCTAssertTrue(prefixes.contains("https://cdn.example.com/a"))
        XCTAssertTrue(prefixes.contains("https://cdn.example.com/a/b"))
    }

    func testWriterProducesPlayablePlaylist() throws {
        var playlist = M3U8Playlist()
        playlist.durations = [9.0, 8.0]
        playlist.segments = ["0.ts", "1.ts"]
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try M3U8PlaylistWriter.write(playlist: playlist, to: dir, segmentCount: nil)

        let content = try String(contentsOf: dir.appendingPathComponent("index.m3u8"), encoding: .utf8)
        XCTAssertTrue(content.contains("#EXTM3U"))
        XCTAssertTrue(content.contains("0.ts"))
        XCTAssertTrue(content.contains("1.ts"))
        XCTAssertTrue(content.contains("#EXT-X-ENDLIST"))
    }

    func testWriterRespectsPartialCount() throws {
        var playlist = M3U8Playlist()
        playlist.durations = [9.0, 8.0, 7.0]
        playlist.segments = ["0.ts", "1.ts", "2.ts"]
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try M3U8PlaylistWriter.write(playlist: playlist, to: dir, segmentCount: 1)

        let content = try String(contentsOf: dir.appendingPathComponent("index.m3u8"), encoding: .utf8)
        XCTAssertTrue(content.contains("0.ts"))
        XCTAssertFalse(content.contains("1.ts"))
    }
}
