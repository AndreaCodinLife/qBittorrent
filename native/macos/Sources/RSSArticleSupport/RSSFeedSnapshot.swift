import Foundation

public struct RSSFeedSnapshot: Sendable {
    public let feeds: [RSSFeed]
    public let folders: [RSSFolder]
}

public struct RSSFeed: Identifiable, Sendable {
    public let path: String
    public let title: String
    public let url: String
    public let refreshInterval: Int
    public let isLoading: Bool
    public let hasError: Bool
    public let articles: [RSSArticle]

    public var id: String { path }
}

public struct RSSFolder: Identifiable, Sendable {
    public let path: String
    public let title: String

    public var id: String { path }
}

public struct RSSArticle: Identifiable, Sendable {
    public let id: String
    public let feedPath: String
    public let feedTitle: String
    public let title: String
    public let author: String
    public let description: String
    public let link: String
    public let torrentURL: String
    public let date: String
    public let dateValue: Date?
    public let isRead: Bool

    public var selectionID: String { "\(feedPath)\u{1F}\(id)" }
}

public enum RSSFeedSnapshotParserError: LocalizedError {
    case invalidResponse

    public var errorDescription: String? {
        "The qBittorrent server returned an invalid RSS response."
    }
}

public enum RSSFeedSnapshotParser {
    public static func parse(_ data: Data) throws -> RSSFeedSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RSSFeedSnapshotParserError.invalidResponse
        }

        var feeds: [RSSFeed] = []
        var folders: [RSSFolder] = []
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

        func collect(_ node: [String: Any], path: String) {
            for (name, value) in node {
                guard let entry = value as? [String: Any] else { continue }
                let itemPath = path.isEmpty ? name : "\(path)\\\(name)"
                if let url = entry["url"] as? String {
                    let rawFeedTitle = (entry["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let feedTitle = rawFeedTitle.isEmpty ? name : rawFeedTitle
                    let refreshInterval = entry["refreshInterval"] as? Int ?? 0
                    let articles = (entry["articles"] as? [[String: Any]] ?? []).map { article in
                        let date = article["date"] as? String ?? ""
                        return RSSArticle(
                            id: article["id"] as? String ?? UUID().uuidString,
                            feedPath: itemPath,
                            feedTitle: feedTitle,
                            title: article["title"] as? String ?? "Untitled",
                            author: article["author"] as? String ?? "",
                            description: article["description"] as? String ?? "",
                            link: article["link"] as? String ?? "",
                            torrentURL: article["torrentURL"] as? String ?? "",
                            date: date,
                            dateValue: dateFormatter.date(from: date),
                            isRead: article["isRead"] as? Bool ?? false
                        )
                    }
                    feeds.append(RSSFeed(
                        path: itemPath,
                        title: feedTitle,
                        url: url,
                        refreshInterval: refreshInterval,
                        isLoading: entry["isLoading"] as? Bool ?? false,
                        hasError: entry["hasError"] as? Bool ?? false,
                        articles: articles
                    ))
                } else {
                    folders.append(RSSFolder(path: itemPath, title: name))
                    collect(entry, path: itemPath)
                }
            }
        }

        collect(root, path: "")
        return RSSFeedSnapshot(
            feeds: feeds.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending },
            folders: folders.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
        )
    }
}
