import Foundation
import Testing
@testable import TorrentLinkInput

struct TorrentLinkInputTests {
    @Test func parsesLinksAndDeduplicatesInInputOrder() {
        let result = TorrentLinkInput.parse("""
        https://example.com/one.torrent
        magnet:?xt=urn:btih:0123456789012345678901234567890123456789
        https://example.com/one.torrent
        """)

        #expect(result.invalidLines.isEmpty)
        #expect(result.urls.count == 2)
        #expect(result.urls[0].absoluteString == "https://example.com/one.torrent")
        #expect(result.urls[1].scheme == "magnet")
    }

    @Test func convertsV1AndV2InfoHashesToMagnetLinks() {
        let v1 = String(repeating: "a", count: 40)
        let v2 = String(repeating: "b", count: 64)
        let result = TorrentLinkInput.parse("\(v1)\n\(v2)")

        #expect(result.invalidLines.isEmpty)
        #expect(result.urls.map(\.absoluteString) == [
            "magnet:?xt=urn:btih:\(v1)",
            "magnet:?xt=urn:btmh:1220\(v2)"
        ])
    }

    @Test func recognizesOnlySupportedClipboardLines() {
        let result = TorrentLinkInput.recognizedLines("""
        Read this first
        0123456789012345678901234567890123456789
        file:///tmp/example.torrent
        file:///tmp/example.txt
        """)

        #expect(result == "0123456789012345678901234567890123456789\nfile:///tmp/example.torrent")
    }

    @Test func reportsUnsupportedEntriesAndDoesNotReturnThem() {
        let result = TorrentLinkInput.parse("https://example.com/torrent\nnot a link")

        #expect(result.urls.count == 1)
        #expect(result.invalidLines == ["not a link"])
    }
}
