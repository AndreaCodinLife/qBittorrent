import Foundation
import CoreFoundation

enum APIAuthentication: Sendable {
    case apiKey(String)
    case password(username: String, password: String)
    case anonymous
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

enum TorrentCommand: String, Sendable {
    case start, stop, recheck, reannounce
    case increasePrio, decreasePrio, topPrio, bottomPrio
    case toggleSequentialDownload, toggleFirstLastPiecePrio
}

struct NetworkInterfaceOption: Decodable, Sendable {
    let name: String
    let value: String
}

struct TorrentAddOptions: Sendable {
    var savePath = ""
    var downloadPathEnabled = false
    var downloadPath = ""
    var category = ""
    var tags = ""
    var rename = ""
    var stopped = false
    var sequential = false
    var firstLastPiece = false
    var automaticManagement = false
    var addToQueueTop = false
    var seedMode = false
    var stopCondition = "None"
    var contentLayout = "Original"
    var downloadLimitKiB = 0
    var uploadLimitKiB = 0
    var filePriorities: [Int]?

    var form: [String: String] {
        var values = [
            "category": category, "tags": tags,
            "stopped": stopped ? "true" : "false",
            "sequentialDownload": sequential ? "true" : "false",
            "firstLastPiecePrio": firstLastPiece ? "true" : "false",
            "autoTMM": automaticManagement ? "true" : "false",
            "addToTopOfQueue": addToQueueTop ? "true" : "false",
            "seedMode": seedMode ? "true" : "false",
            "stopCondition": stopCondition,
            "contentLayout": contentLayout,
            "dlLimit": "\(downloadLimitKiB * 1024)",
            "upLimit": "\(uploadLimitKiB * 1024)"
        ]
        if let filePriorities { values["filePriorities"] = filePriorities.map(String.init).joined(separator: ",") }
        if !savePath.isEmpty { values["savepath"] = savePath }
        if !rename.isEmpty { values["rename"] = rename }
        if downloadPathEnabled {
            values["useDownloadPath"] = "true"
            values["downloadPath"] = downloadPath
        }
        return values
    }
}

actor QBittorrentAPI {
    private let baseURL: URL
    private var authentication: APIAuthentication
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

    func webAPIVersion() async throws -> String {
        let data = try await request("app/webapiVersion")
        guard let version = String(data: data, encoding: .utf8) else { throw APIError.badResponse }
        return version.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func torrents(includeTrackers: Bool = false) async throws -> [Torrent] {
        let data = try await request("torrents/info", query: includeTrackers ? ["includeTrackers": "true"] : [:])
        let responses = try JSONDecoder().decode([TorrentResponse].self, from: data)
        let raw = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return responses.enumerated().map { index, response in
            let row = index < raw.count ? raw[index] : [:]
            return response.torrent(extra: TorrentResponse.formatColumns(row), sortNumbers: TorrentResponse.numericColumns(row))
        }
    }

    func transferStatus() async throws -> TransferStatus {
        let data = try await request("transfer/info")
        let response = try JSONDecoder().decode(TransferResponse.self, from: data)
        return TransferStatus(
            downloadRate: response.dl_info_speed ?? 0,
            uploadRate: response.up_info_speed ?? 0,
            totalDownloadRate: response.total_dl_speed ?? response.dl_info_speed ?? 0,
            totalUploadRate: response.total_up_speed ?? response.up_info_speed ?? 0,
            payloadDownloadRate: response.payload_dl_speed ?? response.dl_info_speed ?? 0,
            payloadUploadRate: response.payload_up_speed ?? response.up_info_speed ?? 0,
            overheadDownloadRate: response.overhead_dl_speed ?? 0,
            overheadUploadRate: response.overhead_up_speed ?? 0,
            dhtDownloadRate: response.dht_dl_speed ?? 0,
            dhtUploadRate: response.dht_up_speed ?? 0,
            trackerDownloadRate: response.tracker_dl_speed ?? 0,
            trackerUploadRate: response.tracker_up_speed ?? 0,
            dhtNodes: response.dht_nodes ?? 0,
            connectionStatus: response.connection_status ?? "disconnected",
            lastExternalAddressV4: response.last_external_address_v4,
            lastExternalAddressV6: response.last_external_address_v6
        )
    }

    func statistics() async throws -> ServerStatistics {
        let data = try await request("sync/maindata", query: ["rid": "0"])
        return try JSONDecoder().decode(ServerStatisticsResponse.self, from: data).server_state
    }

    func mainLog(after id: Int, normal: Bool = true, info: Bool = true, warning: Bool = true, critical: Bool = true) async throws -> [LogEntry] {
        let data = try await request("log/main", query: [
            "last_known_id": "\(id)", "normal": normal ? "true" : "false",
            "info": info ? "true" : "false", "warning": warning ? "true" : "false",
            "critical": critical ? "true" : "false"
        ])
        return try JSONDecoder().decode([LogEntry].self, from: data)
    }

    func enablePeerCountries() async throws {
        let data = try await request("app/preferences")
        let preferences = try JSONDecoder().decode(PeerCountryPreferences.self, from: data)
        guard !preferences.resolve_peer_countries else { return }
        _ = try await request("app/setPreferences", method: "POST", form: [
            "json": "{\"resolve_peer_countries\":true}"
        ])
    }

    func preferencesData() async throws -> Data {
        try await request("app/preferences")
    }

    func networkInterfaces() async throws -> [NetworkInterfaceOption] {
        let data = try await request("app/networkInterfaceList")
        return try JSONDecoder().decode([NetworkInterfaceOption].self, from: data)
    }

    func networkInterfaceAddresses(for interface: String) async throws -> [String] {
        let data = try await request("app/networkInterfaceAddressList", query: ["iface": interface])
        return try JSONDecoder().decode([String].self, from: data)
    }

    func rotateAPIKey() async throws -> String {
        let data = try await request("app/rotateAPIKey", method: "POST")
        let response = try JSONDecoder().decode(APIKeyRotationResponse.self, from: data)
        if case .apiKey = authentication { authentication = .apiKey(response.apiKey) }
        return response.apiKey
    }

    func deleteAPIKey() async throws {
        _ = try await request("app/deleteAPIKey", method: "POST")
        if case .apiKey = authentication { authentication = .anonymous }
    }

    func createTorrent(sourcePath: String, outputPath: String, trackers: String, webSeeds: String, comment: String, source: String, isPrivate: Bool, ignoreDotfiles: Bool, startSeeding: Bool, pieceSize: Int, format: String) async throws -> String {
        let trackerList = trackers.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let seedList = webSeeds.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "|"))
        let encodedTrackers = trackerList.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }.joined(separator: "|")
        let encodedSeeds = seedList.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }.joined(separator: "|")
        let data = try await request("torrentcreator/addTask", method: "POST", form: [
            "sourcePath": sourcePath,
            "torrentFilePath": outputPath,
            "trackers": encodedTrackers,
            "urlSeeds": encodedSeeds,
            "comment": comment,
            "source": source,
            "pieceSize": "\(pieceSize)",
            "ignoreDotfiles": ignoreDotfiles ? "true" : "false",
            "private": isPrivate ? "true" : "false",
            "format": format,
            "startSeeding": startSeeding ? "true" : "false"
        ])
        return try JSONDecoder().decode(TorrentCreationResponse.self, from: data).taskID
    }

    func torrentCreationStatus(taskID: String) async throws -> TorrentCreationStatus {
        let data = try await request("torrentcreator/status", query: ["taskID": taskID])
        guard let result = try JSONDecoder().decode([TorrentCreationStatus].self, from: data).first else { throw APIError.badResponse }
        return result
    }

    func torrentCreationTasks() async throws -> [TorrentCreationStatus] {
        let data = try await request("torrentcreator/status")
        return try JSONDecoder().decode([TorrentCreationStatus].self, from: data)
    }

    func deleteTorrentCreationTask(_ taskID: String) async throws {
        _ = try await request("torrentcreator/deleteTask", method: "POST", form: ["taskID": taskID])
    }

    func createdTorrentFile(taskID: String) async throws -> Data {
        try await request("torrentcreator/torrentFile", query: ["taskID": taskID])
    }

    func cookies() async throws -> [BackendCookie] {
        let data = try await request("app/cookies")
        return try JSONDecoder().decode([BackendCookie].self, from: data)
    }

    func setCookies(_ cookies: [BackendCookie]) async throws {
        let data = try JSONEncoder().encode(cookies)
        guard let json = String(data: data, encoding: .utf8) else { throw APIError.badResponse }
        _ = try await request("app/setCookies", method: "POST", form: ["cookies": json])
    }

    func setPreference(key: String, jsonValue: String) async throws {
        let encodedKey = try JSONEncoder().encode(key)
        guard let keyLiteral = String(data: encodedKey, encoding: .utf8) else { throw APIError.badResponse }
        _ = try await request("app/setPreferences", method: "POST", form: [
            "json": "{\(keyLiteral):\(jsonValue)}"
        ])
    }

    func properties(for hash: String) async throws -> TorrentProperties {
        let data = try await request("torrents/properties", query: ["hash": hash])
        return try JSONDecoder().decode(TorrentProperties.self, from: data)
    }

    func pieceStates(for hash: String) async throws -> [Int] {
        let data = try await request("torrents/pieceStates", query: ["hash": hash])
        return try JSONDecoder().decode([Int].self, from: data)
    }

    func pieceAvailability(for hash: String) async throws -> [Int] {
        let data = try await request("torrents/pieceAvailability", query: ["hash": hash])
        return try JSONDecoder().decode([Int].self, from: data)
    }

    func trackers(for hash: String) async throws -> [TorrentTracker] {
        let data = try await request("torrents/trackers", query: ["hash": hash])
        return try JSONDecoder().decode([TorrentTracker].self, from: data)
    }

    func files(for hash: String) async throws -> [TorrentFile] {
        let data = try await request("torrents/files", query: ["hash": hash])
        return try JSONDecoder().decode([TorrentFile].self, from: data)
    }

    func setFilePriority(hash: String, indices: [Int], priority: Int) async throws {
        _ = try await request("torrents/filePrio", method: "POST", form: [
            "hash": hash, "id": indices.map(String.init).joined(separator: "|"), "priority": "\(priority)"
        ])
    }

    func renameFile(hash: String, oldPath: String, newPath: String) async throws {
        _ = try await request("torrents/renameFile", method: "POST", form: [
            "hash": hash, "oldPath": oldPath, "newPath": newPath
        ])
    }

    func addTracker(hash: String, url: String) async throws {
        _ = try await request("torrents/addTrackers", method: "POST", form: ["hash": hash, "urls": url])
    }

    func addTrackers(hashes: [String], entries: String) async throws {
        _ = try await request("torrents/addTrackers", method: "POST", form: [
            "hash": hashes.joined(separator: "|"), "urls": entries
        ])
    }

    func editTracker(hash: String, url: String, newURL: String) async throws {
        _ = try await request("torrents/editTracker", method: "POST", form: [
            "hash": hash, "url": url, "newUrl": newURL
        ])
    }

    func moveTracker(hash: String, url: String, tier: Int) async throws {
        _ = try await request("torrents/editTracker", method: "POST", form: [
            "hash": hash, "url": url, "tier": "\(tier)"
        ])
    }

    func reannounceTrackers(hash: String, urls: [String]) async throws {
        _ = try await request("torrents/reannounce", method: "POST", form: [
            "hashes": hash, "urls": urls.joined(separator: "|")
        ])
    }

    func removeTracker(hash: String, url: String) async throws {
        _ = try await request("torrents/removeTrackers", method: "POST", form: [
            "hash": hash, "urls": url
        ])
    }

    func removeTrackers(hashes: [String], urls: [String]) async throws {
        guard !hashes.isEmpty, !urls.isEmpty else { return }
        _ = try await request("torrents/removeTrackers", method: "POST", form: [
            "hash": hashes.joined(separator: "|"), "urls": urls.joined(separator: "|")
        ])
    }

    func addWebSeed(hash: String, url: String) async throws {
        _ = try await request("torrents/addWebSeeds", method: "POST", form: ["hash": hash, "urls": url])
    }

    func editWebSeed(hash: String, url: String, newURL: String) async throws {
        _ = try await request("torrents/editWebSeed", method: "POST", form: [
            "hash": hash, "origUrl": url, "newUrl": newURL
        ])
    }

    func removeWebSeed(hash: String, url: String) async throws {
        _ = try await request("torrents/removeWebSeeds", method: "POST", form: [
            "hash": hash, "urls": url
        ])
    }

    func addPeer(hash: String, address: String) async throws {
        _ = try await request("torrents/addPeers", method: "POST", form: [
            "hashes": hash, "peers": address
        ])
    }

    func banPeer(address: String) async throws {
        _ = try await request("transfer/banPeers", method: "POST", form: ["peers": address])
    }

    func setSessionPaused(_ paused: Bool) async throws {
        _ = try await request(paused ? "transfer/pauseSession" : "transfer/resumeSession", method: "POST")
    }

    func speedLimits() async throws -> SpeedLimits {
        let data = try await request("transfer/getSpeedLimits")
        return try JSONDecoder().decode(SpeedLimits.self, from: data)
    }

    func alternativeSpeedMode() async throws -> Bool {
        let data = try await request("transfer/speedLimitsMode")
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    func setSpeedLimits(_ limits: SpeedLimits, alternativeMode: Bool) async throws {
        _ = try await request("transfer/setSpeedLimits", method: "POST", form: [
            "dl_limit": "\(limits.dl_limit)", "up_limit": "\(limits.up_limit)",
            "alt_dl_limit": "\(limits.alt_dl_limit)", "alt_up_limit": "\(limits.alt_up_limit)"
        ])
        _ = try await request("transfer/setSpeedLimitsMode", method: "POST", form: ["mode": alternativeMode ? "1" : "0"])
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

    func startSearch(_ pattern: String, category: String = "all", plugin: String = "enabled") async throws -> Int {
        let data = try await request("search/start", method: "POST", form: [
            "pattern": pattern, "category": category, "plugins": plugin
        ])
        return try JSONDecoder().decode(SearchStartResponse.self, from: data).id
    }

    func stopSearch(_ id: Int) async throws {
        _ = try await request("search/stop", method: "POST", form: ["id": "\(id)"])
    }

    func installSearchPlugin(_ source: String) async throws {
        _ = try await request("search/installPlugin", method: "POST", form: ["sources": source])
    }

    func uninstallSearchPlugin(_ name: String) async throws {
        _ = try await request("search/uninstallPlugin", method: "POST", form: ["names": name])
    }

    func enableSearchPlugin(_ name: String, enabled: Bool) async throws {
        _ = try await request("search/enablePlugin", method: "POST", form: [
            "names": name, "enable": enabled ? "true" : "false"
        ])
    }

    func updateSearchPlugins() async throws {
        _ = try await request("search/updatePlugins", method: "POST")
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

    func rssFolders() async throws -> [RSSFolder] {
        let data = try await request("rss/items")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw APIError.badResponse }
        var folders: [RSSFolder] = []
        func collect(_ node: [String: Any], path: String) {
            for (name, value) in node {
                guard let entry = value as? [String: Any], entry["url"] == nil else { continue }
                let itemPath = path.isEmpty ? name : "\(path)/\(name)"
                folders.append(RSSFolder(path: itemPath, title: name))
                collect(entry, path: itemPath)
            }
        }
        collect(root, path: "")
        return folders.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }

    func addRSSFeed(_ url: String, path: String? = nil) async throws {
        _ = try await request("rss/addFeed", method: "POST", form: ["url": url, "path": path ?? url])
    }

    func markRSSArticleRead(path: String, articleID: String) async throws {
        _ = try await request("rss/markAsRead", method: "POST", form: ["itemPath": path, "articleId": articleID])
    }

    func markRSSFeedRead(path: String) async throws {
        _ = try await request("rss/markAsRead", method: "POST", form: ["itemPath": path])
    }

    func refreshRSSFeed(path: String) async throws {
        _ = try await request("rss/refreshItem", method: "POST", form: ["itemPath": path])
    }

    func editRSSFeed(path: String, url: String) async throws {
        _ = try await request("rss/setFeedURL", method: "POST", form: ["path": path, "url": url])
    }

    func removeRSSFeed(path: String) async throws {
        _ = try await request("rss/removeItem", method: "POST", form: ["path": path])
    }

    func addRSSFolder(path: String) async throws {
        _ = try await request("rss/addFolder", method: "POST", form: ["path": path])
    }

    func moveRSSItem(path: String, to destination: String) async throws {
        _ = try await request("rss/moveItem", method: "POST", form: ["itemPath": path, "destPath": destination])
    }

    func rssRulesData() async throws -> Data { try await request("rss/rules") }

    func exportRSSRules() async throws -> Data { try await request("rss/exportRules") }

    func importRSSRules(_ data: Data) async throws {
        let boundary = "qBitX-RSS-\(UUID().uuidString)"
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"rules\"; filename=\"rules.json\"\r\nContent-Type: application/json\r\n\r\n".utf8)
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        _ = try await request("rss/importRules", method: "POST", body: body, contentType: "multipart/form-data; boundary=\(boundary)")
    }

    func setRSSRule(name: String, definition: String) async throws {
        _ = try await request("rss/setRule", method: "POST", form: ["ruleName": name, "ruleDef": definition])
    }

    func renameRSSRule(_ name: String, to newName: String) async throws {
        _ = try await request("rss/renameRule", method: "POST", form: ["ruleName": name, "newRuleName": newName])
    }

    func cloneRSSRule(_ name: String, as newName: String) async throws {
        _ = try await request("rss/cloneRule", method: "POST", form: ["sourceName": name, "cloneName": newName])
    }

    func removeRSSRule(_ name: String) async throws {
        _ = try await request("rss/removeRule", method: "POST", form: ["ruleName": name])
    }

    func rssRuleMatches(_ name: String) async throws -> Data {
        try await request("rss/matchingArticles", query: ["ruleName": name])
    }

    func start(_ hash: String) async throws {
        try await command(.start, hashes: [hash])
    }

    func stop(_ hash: String) async throws {
        try await command(.stop, hashes: [hash])
    }

    func command(_ command: TorrentCommand, hashes: [String]) async throws {
        guard !hashes.isEmpty else { return }
        _ = try await request("torrents/\(command.rawValue)", method: "POST", form: ["hashes": hashes.joined(separator: "|")])
    }

    func setTorrentOption(_ endpoint: String, hashes: [String], value: Bool) async throws {
        guard !hashes.isEmpty else { return }
        _ = try await request("torrents/\(endpoint)", method: "POST", form: [
            "hashes": hashes.joined(separator: "|"), "value": value ? "true" : "false"
        ])
    }

    func setTorrentField(_ endpoint: String, hashes: [String], field: String, value: String) async throws {
        guard !hashes.isEmpty else { return }
        _ = try await request("torrents/\(endpoint)", method: "POST", form: [
            "hashes": hashes.joined(separator: "|"), field: value
        ])
    }

    func setTorrentDownloadLimit(hashes: [String], kibPerSecond: Int64) async throws {
        _ = try await request("torrents/setDownloadLimit", method: "POST", form: ["hashes": hashes.joined(separator: "|"), "limit": "\(kibPerSecond * 1024)"])
    }

    func setTorrentUploadLimit(hashes: [String], kibPerSecond: Int64) async throws {
        _ = try await request("torrents/setUploadLimit", method: "POST", form: ["hashes": hashes.joined(separator: "|"), "limit": "\(kibPerSecond * 1024)"])
    }

    func setShareLimits(hashes: [String], ratio: Double, seedingMinutes: Int, inactiveMinutes: Int, action: String, mode: String) async throws {
        _ = try await request("torrents/setShareLimits", method: "POST", form: [
            "hashes": hashes.joined(separator: "|"), "ratioLimit": "\(ratio)",
            "seedingTimeLimit": "\(seedingMinutes)", "inactiveSeedingTimeLimit": "\(inactiveMinutes)",
            "shareLimitAction": action, "shareLimitsMode": mode
        ])
    }

    func rename(_ hash: String, to name: String) async throws {
        _ = try await request("torrents/rename", method: "POST", form: ["hash": hash, "name": name])
    }

    func exportTorrent(_ hash: String) async throws -> Data {
        try await request("torrents/export", query: ["hash": hash])
    }

    func ensureCategory(_ name: String) async throws {
        guard !name.isEmpty else { return }
        let data = try await request("torrents/categories")
        let categories = try JSONDecoder().decode([String: CategoryResponse].self, from: data)
        guard categories[name] == nil else { return }
        _ = try await request("torrents/createCategory", method: "POST", form: ["category": name])
    }

    func categoriesData() async throws -> Data { try await request("torrents/categories") }
    func tagsData() async throws -> Data { try await request("torrents/tags") }

    func createCategory(_ name: String, savePath: String, downloadPathEnabled: Bool, downloadPath: String, ratioLimit: String, seedingMinutes: String, inactiveMinutes: String, mode: String, action: String) async throws {
        _ = try await request("torrents/createCategory", method: "POST", form: categoryForm(name: name, savePath: savePath, downloadPathEnabled: downloadPathEnabled, downloadPath: downloadPath, ratioLimit: ratioLimit, seedingMinutes: seedingMinutes, inactiveMinutes: inactiveMinutes, mode: mode, action: action))
    }

    func editCategory(_ name: String, savePath: String, downloadPathEnabled: Bool, downloadPath: String, ratioLimit: String, seedingMinutes: String, inactiveMinutes: String, mode: String, action: String) async throws {
        _ = try await request("torrents/editCategory", method: "POST", form: categoryForm(name: name, savePath: savePath, downloadPathEnabled: downloadPathEnabled, downloadPath: downloadPath, ratioLimit: ratioLimit, seedingMinutes: seedingMinutes, inactiveMinutes: inactiveMinutes, mode: mode, action: action))
    }

    private func categoryForm(name: String, savePath: String, downloadPathEnabled: Bool, downloadPath: String, ratioLimit: String, seedingMinutes: String, inactiveMinutes: String, mode: String, action: String) -> [String: String] {
        [
            "category": name, "savePath": savePath,
            "downloadPathEnabled": downloadPathEnabled ? "true" : "false", "downloadPath": downloadPath,
            "ratioLimit": ratioLimit, "seedingTimeLimit": seedingMinutes,
            "inactiveSeedingTimeLimit": inactiveMinutes, "shareLimitsMode": mode, "shareLimitAction": action
        ]
    }

    func removeCategory(_ name: String) async throws {
        _ = try await request("torrents/removeCategories", method: "POST", form: ["categories": name])
    }

    func createTags(_ names: [String]) async throws {
        guard !names.isEmpty else { return }
        _ = try await request("torrents/createTags", method: "POST", form: ["tags": names.joined(separator: ",")])
    }

    func removeTag(_ name: String) async throws {
        _ = try await request("torrents/deleteTags", method: "POST", form: ["tags": name])
    }

    func addTags(_ tags: [String], hashes: [String]) async throws {
        guard !tags.isEmpty, !hashes.isEmpty else { return }
        _ = try await request("torrents/addTags", method: "POST", form: [
            "hashes": hashes.joined(separator: "|"), "tags": tags.joined(separator: ",")
        ])
    }

    func removeTorrentTags(_ tags: [String], hashes: [String]) async throws {
        guard !hashes.isEmpty else { return }
        _ = try await request("torrents/removeTags", method: "POST", form: [
            "hashes": hashes.joined(separator: "|"), "tags": tags.joined(separator: ",")
        ])
    }

    func remove(_ hash: String, deleteFiles: Bool) async throws {
        try await remove([hash], deleteFiles: deleteFiles)
    }

    func remove(_ hashes: [String], deleteFiles: Bool) async throws {
        guard !hashes.isEmpty else { return }
        _ = try await request("torrents/delete", method: "POST", form: [
            "hashes": hashes.joined(separator: "|"),
            "deleteFiles": deleteFiles ? "true" : "false"
        ])
    }

    func add(url: String, downloader: String? = nil, options: TorrentAddOptions = TorrentAddOptions()) async throws {
        try await ensureCategory(options.category)
        var form = options.form
        form["urls"] = url
        if let downloader, !downloader.isEmpty { form["downloader"] = downloader }
        let data = try await request("torrents/add", method: "POST", form: form)
        try checkAddResult(data)
    }

    func add(file data: Data, filename: String, options: TorrentAddOptions = TorrentAddOptions()) async throws {
        try await ensureCategory(options.category)
        let boundary = "qBitX-\(UUID().uuidString)"
        var body = Data()
        for (name, value) in options.form {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        let safeFilename = filename.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"torrents\"; filename=\"\(safeFilename)\"\r\nContent-Type: application/x-bittorrent\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let result = try await request("torrents/add", method: "POST", body: body, contentType: "multipart/form-data; boundary=\(boundary)")
        try checkAddResult(result)
    }

    func parseTorrentMetadata(file data: Data, filename: String) async throws -> TorrentMetadata {
        let boundary = "qBitX-\(UUID().uuidString)"
        var body = Data()
        let safeFilename = filename.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"torrents\"; filename=\"\(safeFilename)\"\r\nContent-Type: application/x-bittorrent\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let response = try await request("torrents/parseMetadata", method: "POST", body: body, contentType: "multipart/form-data; boundary=\(boundary)")
        guard let metadata = try JSONDecoder().decode([TorrentMetadata].self, from: response).first else { throw APIError.badResponse }
        return metadata
    }

    func fetchTorrentMetadata(source: String, downloader: String? = nil) async throws -> TorrentMetadata {
        for _ in 0..<60 {
            var form = ["source": source]
            if let downloader, !downloader.isEmpty { form["downloader"] = downloader }
            let response = try await request("torrents/fetchMetadata", method: "POST", form: form)
            let metadata = try JSONDecoder().decode(TorrentMetadata.self, from: response)
            if metadata.info != nil { return metadata }
            try await Task.sleep(for: .seconds(1))
        }
        throw APIError.server(status: 408, message: "Timed out while retrieving torrent metadata.")
    }

    func saveTorrentMetadata(source: String) async throws -> Data {
        try await request("torrents/saveMetadata", method: "POST", form: ["source": source])
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
    let trackers: [TorrentTracker]?
    let size: Int64?
    let progress: Double?
    let dlspeed: Int64?
    let upspeed: Int64?
    let num_seeds: Int?
    let num_leechs: Int?
    let num_complete: Int?
    let num_incomplete: Int?
    let eta: Int64?
    let ratio: Double?
    let save_path: String?
    let state: String
    let force_start: Bool?
    let seq_dl: Bool?
    let f_l_piece_prio: Bool?
    let auto_tmm: Bool?
    let super_seeding: Bool?

    func torrent(extra: [String: String], sortNumbers: [String: Double]) -> Torrent {
        Torrent(
            id: hash,
            name: name,
            category: category ?? "",
            tags: tags ?? "",
            tracker: tracker ?? "",
            trackerHosts: Array(Set((trackers ?? []).compactMap { URLComponents(string: $0.url)?.host?.lowercased() }
                + [tracker].compactMap { URLComponents(string: $0 ?? "")?.host?.lowercased() })).sorted(),
            hasTrackerWarning: (trackers ?? []).contains { tracker in
                tracker.status == 2 && (tracker.endpoints ?? []).contains { $0.status == 2 && !($0.msg?.isEmpty ?? true) }
            },
            hasTrackerError: (trackers ?? []).contains { $0.status == 5 },
            hasOtherAnnounceError: (trackers ?? []).contains { $0.status == 4 || $0.status == 6 },
            sizeBytes: size ?? 0,
            progress: progress ?? 0,
            downloadRateBytes: dlspeed ?? 0,
            uploadRateBytes: upspeed ?? 0,
            seeds: num_seeds ?? 0,
            peers: num_leechs ?? 0,
            totalSeeds: num_complete,
            totalPeers: num_incomplete,
            etaSeconds: eta ?? -1,
            ratio: ratio ?? 0,
            savePath: save_path ?? "",
            rawState: state,
            state: TorrentState(apiValue: state),
            forceStart: force_start ?? false,
            sequentialDownload: seq_dl ?? false,
            firstLastPiecePriority: f_l_piece_prio ?? false,
            automaticManagement: auto_tmm ?? false,
            superSeeding: super_seeding ?? false,
            extra: extra,
            sortNumbers: sortNumbers
        )
    }

    static func formatColumns(_ raw: [String: Any]) -> [String: String] {
        let byteFields: Set<String> = ["total_size", "downloaded", "uploaded", "downloaded_session", "uploaded_session", "amount_left", "completed"]
        let rateFields: Set<String> = ["dl_limit", "up_limit"]
        let dateFields: Set<String> = ["added_on", "completion_on", "seen_complete", "last_activity", "creation_date"]
        let durationFields: Set<String> = ["time_active", "reannounce"]
        var values: [String: String] = [:]
        for (key, value) in raw {
            if value is NSNull { continue }
            if let number = value as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    values[key] = number.boolValue ? "Yes" : "No"
                } else if byteFields.contains(key) {
                    values[key] = ByteCountFormatter.string(fromByteCount: number.int64Value, countStyle: .file)
                } else if rateFields.contains(key) {
                    values[key] = number.int64Value <= 0 ? "Unlimited" : ByteCountFormatter.string(fromByteCount: number.int64Value, countStyle: .binary) + "/s"
                } else if dateFields.contains(key) {
                    values[key] = number.int64Value <= 0 ? "—" : Date(timeIntervalSince1970: number.doubleValue).formatted(date: .abbreviated, time: .shortened)
                } else if durationFields.contains(key) {
                    values[key] = number.int64Value < 0 ? "—" : Duration.seconds(number.int64Value).formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated))
                } else {
                    values[key] = number.stringValue
                }
            } else if let string = value as? String {
                values[key] = string.isEmpty ? "—" : string
            }
        }
        return values
    }

    static func numericColumns(_ raw: [String: Any]) -> [String: Double] {
        raw.compactMapValues { value in
            guard let number = value as? NSNumber else { return nil }
            return number.doubleValue
        }
    }
}

private struct TransferResponse: Decodable {
    let dl_info_speed: Int64?
    let up_info_speed: Int64?
    let total_dl_speed: Int64?
    let total_up_speed: Int64?
    let payload_dl_speed: Int64?
    let payload_up_speed: Int64?
    let overhead_dl_speed: Int64?
    let overhead_up_speed: Int64?
    let dht_dl_speed: Int64?
    let dht_up_speed: Int64?
    let tracker_dl_speed: Int64?
    let tracker_up_speed: Int64?
    let dht_nodes: Int?
    let connection_status: String?
    let last_external_address_v4: String?
    let last_external_address_v6: String?
}

struct ServerStatistics: Decodable, Sendable {
    let alltime_dl: Int64?
    let alltime_ul: Int64?
    let dl_info_data: Int64?
    let up_info_data: Int64?
    let total_wasted_session: Int64?
    let free_space_on_disk: Int64?
    let last_external_address_v4: String?
    let last_external_address_v6: String?
    let total_peer_connections: Int?
    let global_ratio: String?
    let read_cache_hits: String?
    let total_buffers_size: Int64?
    let write_cache_overload: String?
    let read_cache_overload: String?
    let queued_io_jobs: Int?
    let average_time_queue: Double?
    let total_queued_size: Int64?
    let queued_tracker_announces: Int?
    let request_latency: Int?
}

struct LogEntry: Decodable, Identifiable, Sendable {
    let id: Int
    let timestamp: Int64
    let type: Int
    let message: String
}

private struct PeerCountryPreferences: Decodable {
    let resolve_peer_countries: Bool
}

private struct CategoryResponse: Decodable {}

struct SpeedLimits: Decodable, Sendable {
    let dl_limit: Int64
    let up_limit: Int64
    let alt_dl_limit: Int64
    let alt_up_limit: Int64
}

struct TorrentProperties: Decodable, Sendable {
    let total_downloaded: Int64?
    let total_downloaded_session: Int64?
    let total_uploaded: Int64?
    let total_uploaded_session: Int64?
    let total_wasted: Int64?
    let dl_speed: Int64?
    let up_speed: Int64?
    let save_path: String?
    let download_path: String?
    let addition_date: Int64?
    let completion_date: Int64?
    let comment: String?
    let created_by: String?
    let total_size: Int64?
    let eta: Int64?
    let nb_connections: Int?
    let nb_connections_limit: Int?
    let dl_speed_avg: Int64?
    let up_speed_avg: Int64?
    let dl_limit: Int64?
    let up_limit: Int64?
    let time_elapsed: Int64?
    let seeding_time: Int64?
    let availability: Double?
    let share_ratio: Double?
    let popularity: Double?
    let reannounce: Int64?
    let pieces_num: Int?
    let piece_size: Int64?
    let pieces_have: Int?
    let seeds: Int?
    let seeds_total: Int?
    let peers: Int?
    let peers_total: Int?
    let is_private: Bool?
    let infohash_v1: String?
    let infohash_v2: String?
    let has_metadata: Bool?
    let progress: Double?
    let creation_date: Int64?
    let last_seen: Int64?
}

struct TorrentTracker: Decodable, Identifiable, Sendable {
    let url: String
    let tier: Int?
    let status: Int?
    let updating: Bool?
    let num_peers: Int?
    let num_seeds: Int?
    let num_leeches: Int?
    let num_downloaded: Int?
    let msg: String?
    let next_announce: Int64?
    let min_announce: Int64?
    let endpoints: [TorrentTrackerEndpoint]?
    var id: String { url }
}

struct TorrentTrackerEndpoint: Decodable, Identifiable, Sendable {
    let name: String
    let bt_version: Int?
    let updating: Bool?
    let status: Int?
    let msg: String?
    let num_peers: Int?
    let num_seeds: Int?
    let num_leeches: Int?
    let num_downloaded: Int?
    let next_announce: Int64?
    let min_announce: Int64?
    var id: String { "\(name)-\(bt_version ?? 0)" }
}

struct TorrentFile: Decodable, Identifiable, Sendable {
    let index: Int
    let name: String
    let size: Int64
    let progress: Double
    let priority: Int
    let availability: Double?
    var id: Int { index }
}

struct TorrentWebSeed: Decodable, Identifiable, Sendable {
    let url: String
    var id: String { url }
}

private struct PeerSyncResponse: Decodable {
    let peers: [String: TorrentPeer]?
}

private struct ServerStatisticsResponse: Decodable {
    let server_state: ServerStatistics
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
    let peer_id_client: String?
    let connection: String?
    let flags: String?
    let flags_desc: String?
    let downloaded: Int64?
    let uploaded: Int64?
    let relevance: Double?
    let contribution: Double?
    let files: String?
    let host_name: String?
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
    let version: String?
    let supportedCategories: [SearchCategory]?
    var id: String { name }
}

struct SearchCategory: Decodable, Hashable, Sendable {
    let id: String
    let name: String
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
    let siteUrl: String
    let descrLink: String
    let pubDate: Int64
    var id: String { "\(engineName)|\(fileUrl)" }

    private enum CodingKeys: String, CodingKey {
        case fileName, fileUrl, fileSize, nbSeeders, nbLeechers, engineName, siteUrl, descrLink, pubDate
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fileName = try values.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        fileUrl = try values.decodeIfPresent(String.self, forKey: .fileUrl) ?? ""
        fileSize = try values.decodeIfPresent(Int64.self, forKey: .fileSize) ?? 0
        nbSeeders = try values.decodeIfPresent(Int.self, forKey: .nbSeeders) ?? 0
        nbLeechers = try values.decodeIfPresent(Int.self, forKey: .nbLeechers) ?? 0
        engineName = try values.decodeIfPresent(String.self, forKey: .engineName) ?? ""
        siteUrl = try values.decodeIfPresent(String.self, forKey: .siteUrl) ?? ""
        descrLink = try values.decodeIfPresent(String.self, forKey: .descrLink) ?? ""
        pubDate = try values.decodeIfPresent(Int64.self, forKey: .pubDate) ?? 0
    }
}

struct RSSFeed: Identifiable, Sendable {
    let path: String
    let title: String
    let url: String
    let articles: [RSSArticle]
    var id: String { path }
}

struct RSSFolder: Identifiable, Sendable {
    let path: String
    let title: String
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

private struct APIKeyRotationResponse: Decodable {
    let apiKey: String
}

struct TorrentMetadata: Decodable, Sendable {
    let id: String?
    let infohash_v1: String?
    let infohash_v2: String?
    let info: TorrentMetadataInfo?
    let comment: String?
    let creation_date: Int64?

    private enum CodingKeys: String, CodingKey {
        case id = "hash"
        case infohash_v1, infohash_v2, info, comment, creation_date
    }

    var magnetURI: String? {
        var items: [URLQueryItem] = []
        if let infohash_v1, !infohash_v1.isEmpty { items.append(URLQueryItem(name: "xt", value: "urn:btih:\(infohash_v1)")) }
        if let infohash_v2, !infohash_v2.isEmpty {
            let hash = infohash_v2.hasPrefix("1220") ? infohash_v2 : "1220\(infohash_v2)"
            items.append(URLQueryItem(name: "xt", value: "urn:btmh:\(hash)"))
        }
        if let name = info?.name { items.append(URLQueryItem(name: "dn", value: name)) }
        guard !items.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "magnet"
        components.queryItems = items
        return components.string
    }
}

struct TorrentMetadataInfo: Decodable, Sendable {
    let name: String?
    let files: [TorrentMetadataFile]?
    let length: Int64?
    let piece_length: Int64?
    let pieces_num: Int?
    let privateTorrent: Bool?

    private enum CodingKeys: String, CodingKey {
        case name, files, length, piece_length, pieces_num
        case privateTorrent = "private"
    }
}

struct TorrentMetadataFile: Decodable, Identifiable, Sendable {
    let path: String
    let length: Int64
    let priority: Int?
    var id: String { path }
}

private struct TorrentCreationResponse: Decodable { let taskID: String }

struct TorrentCreationStatus: Decodable, Identifiable, Sendable {
    let taskID: String
    let sourcePath: String?
    let status: String
    let progress: Double?
    let errorMessage: String?
    let torrentFilePath: String?
    var id: String { taskID }
}

struct BackendCookie: Codable, Identifiable, Sendable {
    var name: String
    var domain: String
    var path: String
    var value: String
    var expirationDate: Int64
    var id: String { "\(domain)|\(path)|\(name)" }
}
