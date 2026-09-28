import Foundation
import XCTest
@testable import TorrentSourceFileSupport

final class TorrentSourceFileSupportTests: XCTestCase {
    func testRemovesUnchangedTorrentSource() throws {
        let file = try makeTemporaryTorrent(data: Data("torrent bytes".utf8))
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }

        try TorrentSourceFileSupport.removeIfUnchanged(at: file.url, matching: file.data)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
    }

    func testKeepsSourceWhenContentsChanged() throws {
        let file = try makeTemporaryTorrent(data: Data("original torrent".utf8))
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        try Data("replacement data".utf8).write(to: file.url)

        XCTAssertThrowsError(try TorrentSourceFileSupport.removeIfUnchanged(at: file.url, matching: file.data))
        XCTAssertEqual(try Data(contentsOf: file.url), Data("replacement data".utf8))
    }

    func testIgnoresNonTorrentFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("notes.txt")
        let data = Data("keep".utf8)
        try data.write(to: file)

        try TorrentSourceFileSupport.removeIfUnchanged(at: file, matching: data)

        XCTAssertEqual(try Data(contentsOf: file), data)
    }

    private func makeTemporaryTorrent(data: Data) throws -> (url: URL, data: Data) {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("sample.TORRENT")
        try data.write(to: file)
        return (file, data)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
