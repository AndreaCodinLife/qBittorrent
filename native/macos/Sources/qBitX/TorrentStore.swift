import Foundation
import Observation

enum TorrentStoreError: LocalizedError {
    case disconnected

    var errorDescription: String? { "qBitX is not connected to qBittorrent." }
}

@MainActor
@Observable
final class TorrentStore {
    private(set) var torrents: [Torrent] = []
    private(set) var transferStatus = TransferStatus()
    private(set) var serverVersion = ""
    private(set) var connectionError: String?
    private(set) var isConnected = false
    private(set) var connectionName = "Local library"
    private(set) var speedHistory: [String: [TransferSample]] = [:]

    private let backend = BundledBackend()
    private var api: QBittorrentAPI?

    func run() async {
        connectionError = nil
        isConnected = false
        speedHistory = [:]
        api = nil
        do {
            let connectedAPI: QBittorrentAPI
            if let saved = SavedRemoteConnection.load() {
                guard let secret = SavedRemoteConnection.secret() else {
                    throw ConnectionSettingsError.missingSecret
                }
                connectedAPI = try QBittorrentAPI(address: saved.address, authentication: saved.authentication(secret: secret))
                connectionName = saved.address
            } else {
                connectedAPI = try await backend.connect()
                connectionName = "Local library"
            }
            serverVersion = try await connectedAPI.verify()
            api = connectedAPI
            isConnected = true
            while !Task.isCancelled {
                await refresh()
                try await Task.sleep(for: .seconds(2))
            }
        } catch is CancellationError {
            return
        } catch {
            connectionError = error.localizedDescription
            isConnected = false
        }
    }

    func configureRemote(_ settings: SavedRemoteConnection, secret: String) async throws {
        let resolvedSecret = secret.isEmpty ? SavedRemoteConnection.secret() : secret
        guard let resolvedSecret, !resolvedSecret.isEmpty else {
            throw ConnectionSettingsError.missingSecret
        }
        let candidate = try QBittorrentAPI(address: settings.address, authentication: settings.authentication(secret: resolvedSecret))
        _ = try await candidate.verify()
        try settings.save(secret: resolvedSecret)
    }

    func useBundledBackend() {
        SavedRemoteConnection.clear()
    }

    func refresh() async {
        guard let api else { return }
        do {
            async let newTorrents = api.torrents()
            async let newStatus = api.transferStatus()
            torrents = try await newTorrents
            transferStatus = try await newStatus
            isConnected = true
            let now = Date()
            for torrent in torrents {
                var samples = speedHistory[torrent.id, default: []]
                samples.append(TransferSample(date: now, download: torrent.downloadRateBytes, upload: torrent.uploadRateBytes))
                if samples.count > 90 { samples.removeFirst(samples.count - 90) }
                speedHistory[torrent.id] = samples
            }
            let activeHashes = Set(torrents.map(\.id))
            speedHistory = speedHistory.filter { activeHashes.contains($0.key) }
            connectionError = nil
        } catch is CancellationError {
            return
        } catch {
            connectionError = error.localizedDescription
            isConnected = false
        }
    }

    func start(_ hash: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.start(hash)
        await refresh()
    }

    func stop(_ hash: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.stop(hash)
        await refresh()
    }

    func remove(_ hash: String, deleteFiles: Bool) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.remove(hash, deleteFiles: deleteFiles)
        await refresh()
    }

    func add(url: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.add(url: url)
        await refresh()
    }

    func add(file data: Data, filename: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.add(file: data, filename: filename)
        await refresh()
    }

    func properties(for hash: String) async throws -> TorrentProperties {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.properties(for: hash)
    }

    func trackers(for hash: String) async throws -> [TorrentTracker] {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.trackers(for: hash)
    }

    func files(for hash: String) async throws -> [TorrentFile] {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.files(for: hash)
    }

    func webSeeds(for hash: String) async throws -> [TorrentWebSeed] {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.webSeeds(for: hash)
    }

    func peers(for hash: String) async throws -> [TorrentPeer] {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.peers(for: hash)
    }

    func searchPlugins() async throws -> [SearchPlugin] {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.searchPlugins()
    }

    func startSearch(_ pattern: String) async throws -> Int {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.startSearch(pattern)
    }

    func searchResults(_ id: Int) async throws -> SearchResultsResponse {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.searchResults(id)
    }

    func downloadSearchResult(_ result: SearchResult) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.downloadSearchResult(result)
        await refresh()
    }

    func rssFeeds() async throws -> [RSSFeed] {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.rssFeeds()
    }

    func addRSSFeed(_ url: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.addRSSFeed(url)
    }

    func addRSSArticle(_ article: RSSArticle) async throws {
        let url = article.torrentURL.isEmpty ? article.link : article.torrentURL
        try await add(url: url)
    }

    func markRSSArticleRead(path: String, articleID: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.markRSSArticleRead(path: path, articleID: articleID)
    }
}

struct TransferSample: Identifiable {
    let date: Date
    let download: Int64
    let upload: Int64
    var id: Date { date }
}
