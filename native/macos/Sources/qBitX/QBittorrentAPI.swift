import Foundation

enum APIAuthentication: Sendable {
    case apiKey(String)
    case password(username: String, password: String)
}

enum APIError: LocalizedError {
    case invalidAddress
    case unauthorized
    case badResponse
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress: "Enter an HTTP or HTTPS address for the qBittorrent Web UI."
        case .unauthorized: "The Web UI rejected the credentials or API key."
        case .badResponse: "The server did not return a qBittorrent API response."
        case let .server(status, message): "qBittorrent returned HTTP \(status): \(message)"
        }
    }
}

actor QBittorrentAPI {
    private let baseURL: URL
    private let authentication: APIAuthentication
    private let session: URLSession

    init(address: String, authentication: APIAuthentication) throws {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { throw APIError.invalidAddress }
        baseURL = url
        self.authentication = authentication
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        session = URLSession(configuration: configuration)
    }

    func verify() async throws -> String {
        if case let .password(username, password) = authentication {
            _ = try await request("auth/login", method: "POST", form: ["username": username, "password": password])
        }
        let data = try await request("app/version")
        guard let version = String(data: data, encoding: .utf8), version.hasPrefix("v") else {
            throw APIError.badResponse
        }
        return version.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func torrents() async throws -> [Torrent] {
        let data = try await request("torrents/info")
        return try JSONDecoder().decode([TorrentResponse].self, from: data).map(\.torrent)
    }

    func transferStatus() async throws -> TransferStatus {
        let data = try await request("transfer/info")
        let response = try JSONDecoder().decode(TransferResponse.self, from: data)
        return TransferStatus(
            downloadRate: response.dl_info_speed ?? 0,
            uploadRate: response.up_info_speed ?? 0,
            dhtNodes: response.dht_nodes ?? 0,
            connectionStatus: response.connection_status ?? "disconnected"
        )
    }

    func enablePeerCountries() async throws {
        let data = try await request("app/preferences")
        let preferences = try JSONDecoder().decode(PeerCountryPreferences.self, from: data)
        guard !preferences.resolve_peer_countries else { return }
        _ = try await request("app/setPreferences", method: "POST", form: [
            "json": "{\"resolve_peer_countries\":true}"
        ])
    }

    func properties(for hash: String) async throws -> TorrentProperties {
        let data = try await request("torrents/properties", query: ["hash": hash])
        return try JSONDecoder().decode(TorrentProperties.self, from: data)
    }

    func trackers(for hash: String) async throws -> [TorrentTracker] {
        let data = try await request("torrents/trackers", query: ["hash": hash])
        return try JSONDecoder().decode([TorrentTracker].self, from: data)
    }

    func files(for hash: String) async throws -> [TorrentFile] {
        let data = try await request("torrents/files", query: ["hash": hash])
        return try JSONDecoder().decode([TorrentFile].self, from: data)
    }

    func webSeeds(for hash: String) async throws -> [TorrentWebSeed] {
        let data = try await request("torrents/webseeds", query: ["hash": hash])
        return try JSONDecoder().decode([TorrentWebSeed].self, from: data)
    }

    func peers(for hash: String) async throws -> [TorrentPeer] {
        let data = try await request("sync/torrentPeers", query: ["hash": hash, "rid": "0"])
        let response = try JSONDecoder().decode(PeerSyncResponse.self, from: data)
        return Array((response.peers ?? [:]).values).sorted { $0.ip < $1.ip }
    }

    func searchPlugins() async throws -> [SearchPlugin] {
        let data = try await request("search/plugins")
        return try JSONDecoder().decode([SearchPlugin].self, from: data)
    }

    func startSearch(_ pattern: String) async throws -> Int {
        let data = try await request("search/start", method: "POST", form: [
            "pattern": pattern, "category": "all", "plugins": "enabled"
        ])
        return try JSONDecoder().decode(SearchStartResponse.self, from: data).id
    }

    func searchResults(_ id: Int) async throws -> SearchResultsResponse {
        let data = try await request("search/results", query: ["id": "\(id)"])
        return try JSONDecoder().decode(SearchResultsResponse.self, from: data)
    }

    func downloadSearchResult(_ result: SearchResult) async throws {
        _ = try await request("search/downloadTorrent", method: "POST", form: [
            "torrentUrl": result.fileUrl, "pluginName": result.engineName
        ])
    }

    func rssFeeds() async throws -> [RSSFeed] {
        let data = try await request("rss/items", query: ["withData": "true"])
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.badResponse
        }
        var feeds: [RSSFeed] = []
        func collect(_ node: [String: Any], path: String) {
            for (name, value) in node {
                guard let entry = value as? [String: Any] else { continue }
                let itemPath = path.isEmpty ? name : "\(path)/\(name)"
                if let url = entry["url"] as? String {
                    let articles = (entry["articles"] as? [[String: Any]] ?? []).map { article in
                        RSSArticle(
                            id: article["id"] as? String ?? UUID().uuidString,
                            title: article["title"] as? String ?? "Untitled",
                            link: article["link"] as? String ?? "",
                            torrentURL: article["torrentURL"] as? String ?? "",
                            date: article["date"] as? String ?? "",
                            isRead: article["isRead"] as? Bool ?? false
                        )
                    }
                    let feedTitle = (entry["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    feeds.append(RSSFeed(path: itemPath, title: feedTitle.isEmpty ? name : feedTitle, url: url, articles: articles))
                } else {
                    collect(entry, path: itemPath)
                }
            }
        }
        collect(root, path: "")
        return feeds.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func addRSSFeed(_ url: String) async throws {
        _ = try await request("rss/addFeed", method: "POST", form: ["url": url, "path": url])
    }

    func markRSSArticleRead(path: String, articleID: String) async throws {
        _ = try await request("rss/markAsRead", method: "POST", form: ["itemPath": path, "articleId": articleID])
    }

    func start(_ hash: String) async throws {
        _ = try await request("torrents/start", method: "POST", form: ["hashes": hash])
    }

    func stop(_ hash: String) async throws {
        _ = try await request("torrents/stop", method: "POST", form: ["hashes": hash])
    }

    func remove(_ hash: String, deleteFiles: Bool) async throws {
        _ = try await request("torrents/delete", method: "POST", form: [
            "hashes": hash,
            "deleteFiles": deleteFiles ? "true" : "false"
        ])
    }

    func add(url: String) async throws {
        let data = try await request("torrents/add", method: "POST", form: ["urls": url])
        try checkAddResult(data)
    }

    func add(file data: Data, filename: String) async throws {
        let boundary = "qBitX-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"torrents\"; filename=\"\(filename.replacingOccurrences(of: "\"", with: ""))\"\r\nContent-Type: application/x-bittorrent\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let result = try await request("torrents/add", method: "POST", body: body, contentType: "multipart/form-data; boundary=\(boundary)")
        try checkAddResult(result)
    }

    private func checkAddResult(_ data: Data) throws {
        guard let result = try? JSONDecoder().decode(AddTorrentResponse.self, from: data) else { return }
        if result.failure_count > 0 && result.success_count == 0 && result.pending_count == 0 {
            throw APIError.server(status: 409, message: "The torrent could not be added.")
        }
    }

    private func request(
        _ endpoint: String,
        method: String = "GET",
        query: [String: String] = [:],
        form: [String: String]? = nil,
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> Data {
        var url = baseURL.appending(path: "api/v2/\(endpoint)")
        if !query.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            guard let result = components?.url else { throw APIError.invalidAddress }
            url = result
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("qBitX", forHTTPHeaderField: "User-Agent")
        if case let .apiKey(key) = authentication {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        if let form {
            var components = URLComponents()
            components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
            request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        } else if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.badResponse }
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw APIError.unauthorized
        default:
            let message = String(data: data.prefix(200), encoding: .utf8) ?? "Unknown error"
            throw APIError.server(status: response.statusCode, message: message)
        }
    }
}

private struct TorrentResponse: Decodable {
    let hash: String
    let name: String
    let category: String?
    let tags: String?
    let tracker: String?
    let size: Int64?
    let progress: Double?
    let dlspeed: Int64?
    let upspeed: Int64?
    let num_seeds: Int?
    let num_leechs: Int?
    let eta: Int64?
    let ratio: Double?
    let save_path: String?
    let state: String

    var torrent: Torrent {
        Torrent(
            id: hash,
            name: name,
            category: category ?? "",
            tags: tags ?? "",
            tracker: tracker ?? "",
            sizeBytes: size ?? 0,
            progress: progress ?? 0,
            downloadRateBytes: dlspeed ?? 0,
            uploadRateBytes: upspeed ?? 0,
            seeds: num_seeds ?? 0,
            peers: num_leechs ?? 0,
            etaSeconds: eta ?? -1,
            ratio: ratio ?? 0,
            savePath: save_path ?? "",
            state: TorrentState(apiValue: state)
        )
    }
}

private struct TransferResponse: Decodable {
    let dl_info_speed: Int64?
    let up_info_speed: Int64?
    let dht_nodes: Int?
    let connection_status: String?
}

private struct PeerCountryPreferences: Decodable {
    let resolve_peer_countries: Bool
}

struct TorrentProperties: Decodable, Sendable {
    let total_downloaded: Int64?
    let total_uploaded: Int64?
    let save_path: String?
    let addition_date: Int64?
    let completion_date: Int64?
    let comment: String?
    let created_by: String?
}

struct TorrentTracker: Decodable, Identifiable, Sendable {
    let url: String
    let status: Int?
    let num_peers: Int?
    let num_seeds: Int?
    let msg: String?
    var id: String { url }
}

struct TorrentFile: Decodable, Identifiable, Sendable {
    let index: Int
    let name: String
    let size: Int64
    let progress: Double
    let priority: Int
    var id: Int { index }
}

struct TorrentWebSeed: Decodable, Identifiable, Sendable {
    let url: String
    var id: String { url }
}

private struct PeerSyncResponse: Decodable {
    let peers: [String: TorrentPeer]?
}

struct TorrentPeer: Decodable, Identifiable, Sendable {
    let ip: String
    let port: Int?
    let client: String?
    let progress: Double?
    let dl_speed: Int64?
    let up_speed: Int64?
    let country: String?
    let country_code: String?
    var id: String { "\(ip):\(port ?? 0)" }
    var countryName: String { country.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown" }

    var countryFlag: String? {
        guard let country_code else { return nil }
        let letters = Array(country_code.uppercased().utf8)
        guard letters.count == 2, letters.allSatisfy({ (65...90).contains($0) }) else { return nil }
        return String(String.UnicodeScalarView(letters.map { UnicodeScalar(127397 + Int($0))! }))
    }
}

struct SearchPlugin: Decodable, Identifiable, Sendable {
    let name: String
    let fullName: String?
    let enabled: Bool?
    var id: String { name }
}

private struct SearchStartResponse: Decodable {
    let id: Int
}

struct SearchResultsResponse: Decodable, Sendable {
    let status: String
    let results: [SearchResult]
    let total: Int
}

struct SearchResult: Decodable, Identifiable, Sendable {
    let fileName: String
    let fileUrl: String
    let fileSize: Int64
    let nbSeeders: Int
    let nbLeechers: Int
    let engineName: String
    var id: String { "\(engineName)|\(fileUrl)" }
}

struct RSSFeed: Identifiable, Sendable {
    let path: String
    let title: String
    let url: String
    let articles: [RSSArticle]
    var id: String { path }
}

struct RSSArticle: Identifiable, Sendable {
    let id: String
    let title: String
    let link: String
    let torrentURL: String
    let date: String
    let isRead: Bool
}

private struct AddTorrentResponse: Decodable {
    let failure_count: Int
    let success_count: Int
    let pending_count: Int
}
