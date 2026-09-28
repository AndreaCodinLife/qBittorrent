import Foundation

public struct TorrentLinkParseResult: Equatable, Sendable {
    public let urls: [URL]
    public let invalidLines: [String]

    public init(urls: [URL], invalidLines: [String]) {
        self.urls = urls
        self.invalidLines = invalidLines
    }
}

public enum TorrentLinkInput {
    public static func parse(_ text: String) -> TorrentLinkParseResult {
        var seen = Set<String>()
        var urls: [URL] = []
        var invalidLines: [String] = []

        for line in text.components(separatedBy: .newlines) {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(value).inserted else { continue }
            guard let url = url(for: value) else {
                invalidLines.append(value)
                continue
            }
            urls.append(url)
        }

        return TorrentLinkParseResult(urls: urls, invalidLines: invalidLines)
    }

    public static func recognizedLines(_ text: String) -> String {
        var seen = Set<String>()
        return text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted && url(for: $0) != nil }
            .joined(separator: "\n")
    }

    private static func url(for value: String) -> URL? {
        if isHex(value, count: 40) {
            return URL(string: "magnet:?xt=urn:btih:\(value)")
        }
        if isHex(value, count: 64) {
            return URL(string: "magnet:?xt=urn:btmh:1220\(value)")
        }
        if isBase32InfoHash(value) {
            return URL(string: "magnet:?xt=urn:btih:\(value.uppercased())")
        }

        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased() else { return nil }

        switch scheme {
        case "magnet":
            guard value.lowercased().hasPrefix("magnet:") else { return nil }
        case "http", "https", "ftp":
            guard components.host?.isEmpty == false else { return nil }
        case "file":
            guard URL(string: value)?.pathExtension.lowercased() == "torrent" else { return nil }
        default:
            return nil
        }
        return URL(string: value)
    }

    private static func isHex(_ value: String, count: Int) -> Bool {
        value.utf8.count == count && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }

    private static func isBase32InfoHash(_ value: String) -> Bool {
        value.utf8.count == 32 && value.uppercased().utf8.allSatisfy {
            (65...90).contains($0) || (50...55).contains($0)
        }
    }
}
