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
    private(set) var serverStatistics: ServerStatistics?
    private(set) var serverVersion = ""
    private(set) var serverAPIVersion = ""
    private(set) var connectionError: String?
    private(set) var isConnected = false
    private(set) var connectionName = "Local library"
    private(set) var interfaceLocale = ""
    private(set) var sessionSpeedHistory: [TransferSample] = []

    private let backend = BundledBackend()
    private var api: QBittorrentAPI?
    private var trackerSummaryRefreshedAt: Date?
    @ObservationIgnored private var serverStatisticsRefreshedAt: Date?
    @ObservationIgnored private var sleepActivity: NSObjectProtocol?
    @ObservationIgnored private var runTask: Task<Void, Never>?

    func start(retrying: Bool = false) {
        if retrying {
            runTask?.cancel()
            runTask = nil
        }
        guard runTask == nil else { return }
        runTask = Task { await run() }
    }

    func run() async {
        connectionError = nil
        isConnected = false
        serverVersion = ""
        serverAPIVersion = ""
        interfaceLocale = ""
        sessionSpeedHistory = []
        trackerSummaryRefreshedAt = nil
        serverStatistics = nil
        serverStatisticsRefreshedAt = nil
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
                try await connectedAPI.enablePeerCountries()
                connectionName = "Local library"
            }
            serverVersion = try await connectedAPI.verify()
            serverAPIVersion = (try? await connectedAPI.webAPIVersion()).flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
            if let data = try? await connectedAPI.preferencesData(),
               let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                interfaceLocale = values["locale"] as? String ?? ""
            }
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
            updateSleepInhibition()
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

    var usesBundledBackend: Bool { SavedRemoteConnection.load() == nil }

    var webAPICompatibilityMessage: String? {
        guard isConnected else { return nil }
        guard let current = Self.versionComponents(serverAPIVersion) else {
            return "qBitX could not read this server's Web API version, so full compatibility cannot be confirmed. Some newer features may be unavailable."
        }
        let minimum = [2, 16, 2]
        let count = max(current.count, minimum.count)
        let paddedCurrent = current + Array(repeating: 0, count: count - current.count)
        let paddedMinimum = minimum + Array(repeating: 0, count: count - minimum.count)
        guard paddedCurrent.lexicographicallyPrecedes(paddedMinimum) else { return nil }
        return "This server exposes Web API \(serverAPIVersion); full qBitX feature parity requires 2.16.2 or later. Some newer RSS and category settings may be unavailable."
    }

    var requiresNewerWebAPIForFullParity: Bool { webAPICompatibilityMessage != nil }

    private static func versionComponents(_ value: String) -> [Int]? {
        let components = value.split(separator: ".").compactMap { Int($0) }
        return components.count == value.split(separator: ".").count ? components : nil
    }

    func preferencesData() async throws -> Data {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.preferencesData()
    }

    func defaultSavePath() async throws -> String {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.defaultSavePath()
    }

    func sendTestEmail() async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.sendTestEmail()
    }

    func refreshIPFilter() async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.refreshIPFilter()
    }

    func watchedFoldersData() async throws -> Data {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.watchedFoldersData()
    }

    func setWatchedFolders(json: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.setWatchedFolders(json: json)
    }

    func serverDirectoryContent(path: String, mode: String) async throws -> [ServerDirectoryEntry] {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.directoryContent(path: path, mode: mode)
    }

    func freeSpace(at path: String) async throws -> Int64? {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.freeSpace(at: path)
    }

    func shouldConfirmTorrentRecheck() async throws -> Bool {
        let data = try await preferencesData()
        guard let preferences = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.badResponse
        }
        return preferences["confirm_torrent_recheck"] as? Bool ?? true
    }

    func defaultTorrentAddOptions() async throws -> TorrentAddOptions {
        let data = try await preferencesData()
        guard let preferences = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.badResponse
        }
        var options = TorrentAddOptions()
        options.savePath = preferences["save_path"] as? String ?? ""
        options.downloadPathEnabled = preferences["temp_path_enabled"] as? Bool ?? false
        options.downloadPath = preferences["temp_path"] as? String ?? ""
        options.stopped = preferences["add_stopped_enabled"] as? Bool ?? false
        options.automaticManagement = preferences["auto_tmm_enabled"] as? Bool ?? false
        options.addToQueueTop = preferences["add_to_top_of_queue"] as? Bool ?? false
        options.stopCondition = preferences["torrent_stop_condition"] as? String ?? "None"
        options.contentLayout = preferences["torrent_content_layout"] as? String ?? "Original"
        return options
    }

    func networkInterfaces() async throws -> [NetworkInterfaceOption] {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.networkInterfaces()
    }

    func networkInterfaceAddresses(for interface: String) async throws -> [String] {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.networkInterfaceAddresses(for: interface)
    }

    func rotateWebUIAPIKey() async throws -> (key: String, warning: String?) {
        guard let api else { throw TorrentStoreError.disconnected }
        let key = try await api.rotateAPIKey()
        var warning: String?
        if let saved = SavedRemoteConnection.load(), saved.authenticationMode == .apiKey {
            do { try saved.save(secret: key) }
            catch { warning = "The API key was rotated, but qBitX could not update its saved credential. Copy the new key now. \(error.localizedDescription)" }
        }
        return (key, warning)
    }

    func deleteWebUIAPIKey() async throws -> Bool {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.deleteAPIKey()
        if let saved = SavedRemoteConnection.load(), saved.authenticationMode == .apiKey {
            SavedRemoteConnection.clear()
            self.api = nil
            isConnected = false
            connectionError = "The API key was deleted. qBitX disconnected from this Web UI; configure another credential to reconnect."
            return false
        }
        return true
    }

    func createTorrent(sourcePath: String, outputPath: String, trackers: String, webSeeds: String, comment: String, source: String, isPrivate: Bool, ignoreDotfiles: Bool, startSeeding: Bool, pieceSize: Int, format: String) async throws -> String {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.createTorrent(sourcePath: sourcePath, outputPath: outputPath, trackers: trackers, webSeeds: webSeeds, comment: comment, source: source, isPrivate: isPrivate, ignoreDotfiles: ignoreDotfiles, startSeeding: startSeeding, pieceSize: pieceSize, format: format)
    }

    func torrentCreationStatus(taskID: String) async throws -> TorrentCreationStatus {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.torrentCreationStatus(taskID: taskID)
    }

    func torrentCreationTasks() async throws -> [TorrentCreationStatus] {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.torrentCreationTasks()
    }

    func deleteTorrentCreationTask(_ taskID: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.deleteTorrentCreationTask(taskID)
    }

    func createdTorrentFile(taskID: String) async throws -> Data {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.createdTorrentFile(taskID: taskID)
    }

    func cookies() async throws -> [BackendCookie] {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.cookies()
    }

    func setCookies(_ cookies: [BackendCookie]) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.setCookies(cookies)
    }

    func statistics() async throws -> ServerStatistics {
        guard let api else { throw TorrentStoreError.disconnected }
        let statistics = try await api.statistics()
        serverStatistics = statistics
        serverStatisticsRefreshedAt = Date()
        return statistics
    }

    func mainLog(after id: Int, normal: Bool = true, info: Bool = true, warning: Bool = true, critical: Bool = true) async throws -> [LogEntry] {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.mainLog(after: id, normal: normal, info: info, warning: warning, critical: critical)
    }

    func setPreference(key: String, jsonValue: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.setPreference(key: key, jsonValue: jsonValue)
        if key == "locale",
           let data = jsonValue.data(using: .utf8),
           let locale = try? JSONDecoder().decode(String.self, from: data) {
            interfaceLocale = locale
        }
    }

    func refresh() async {
        guard let api else { return }
        do {
            let now = Date()
            let shouldRefreshTrackerSummary = trackerSummaryRefreshedAt.map { now.timeIntervalSince($0) >= 15 } ?? true
            async let newTorrents = api.torrents(includeTrackers: shouldRefreshTrackerSummary)
            async let newStatus = api.transferStatus()
            var refreshedTorrents = try await newTorrents
            if shouldRefreshTrackerSummary {
                trackerSummaryRefreshedAt = now
            } else {
                let priorTorrents = Dictionary(uniqueKeysWithValues: torrents.map { ($0.id, $0) })
                refreshedTorrents = refreshedTorrents.map { torrent in
                    guard let prior = priorTorrents[torrent.id] else { return torrent }
                    var updated = torrent
                    updated.trackerHosts = prior.trackerHosts
                    updated.hasTrackerWarning = prior.hasTrackerWarning
                    updated.hasTrackerError = prior.hasTrackerError
                    updated.hasOtherAnnounceError = prior.hasOtherAnnounceError
                    return updated
                }
            }
            torrents = refreshedTorrents
            transferStatus = try await newStatus
            if serverStatisticsRefreshedAt.map({ now.timeIntervalSince($0) >= 30 }) ?? true {
                serverStatisticsRefreshedAt = now
                if let statistics = try? await api.statistics() {
                    serverStatistics = statistics
                }
            }
            isConnected = true
            MacOSStatusPresentation.updateDockSpeed(transferStatus)
            updateSleepInhibition()
            if sessionSpeedHistory.last.map({ now.timeIntervalSince($0.date) >= 2 }) ?? true {
                sessionSpeedHistory.append(TransferSample(date: now, status: transferStatus))
            }
            if sessionSpeedHistory.count > 43_200 {
                sessionSpeedHistory.removeFirst(sessionSpeedHistory.count - 43_200)
            }
            connectionError = nil
        } catch is CancellationError {
            return
        } catch {
            connectionError = error.localizedDescription
            isConnected = false
            updateSleepInhibition()
        }
    }

    func updateSleepInhibition() {
        let shouldPreventSleep = isConnected && torrents.contains { torrent in
            if torrent.rawState == "moving" { return true }

            let stoppedOrErrored = torrent.rawState.hasPrefix("stopped")
                || torrent.rawState == "error"
                || torrent.rawState == "missingFiles"
            guard !stoppedOrErrored else { return false }

            let downloading = UserDefaults.standard.bool(forKey: "qBitX.preventSleepWhenDownloading")
                && torrent.progress < 1
                && torrent.rawState != "metaDL"
                && torrent.rawState != "forcedMetaDL"
            let seeding = UserDefaults.standard.bool(forKey: "qBitX.preventSleepWhenSeeding")
                && torrent.progress >= 1
            return downloading || seeding
        }

        if shouldPreventSleep, sleepActivity == nil {
            sleepActivity = ProcessInfo.processInfo.beginActivity(
                options: .idleSystemSleepDisabled,
                reason: "qBitX is managing active transfers"
            )
        } else if !shouldPreventSleep, let sleepActivity {
            ProcessInfo.processInfo.endActivity(sleepActivity)
            self.sleepActivity = nil
        }
    }

    func start(_ hash: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.start(hash)
        await refresh()
    }

    func command(_ command: TorrentCommand, hashes: [String]) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.command(command, hashes: hashes)
        await refresh()
    }

    func setForceStart(_ value: Bool, hashes: [String]) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.setTorrentOption("setForceStart", hashes: hashes, value: value)
        await refresh()
    }

    func setSuperSeeding(_ value: Bool, hashes: [String]) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.setTorrentOption("setSuperSeeding", hashes: hashes, value: value)
        await refresh()
    }

    func setAutomaticManagement(_ value: Bool, hashes: [String]) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        guard !hashes.isEmpty else { return }
        try await api.setTorrentField("setAutoManagement", hashes: hashes, field: "enable", value: value ? "true" : "false")
        await refresh()
    }

    func setTorrentLimits(hashes: [String], downloadKiB: Int64, uploadKiB: Int64, ratio: Double, seedingMinutes: Int, inactiveMinutes: Int, action: String, mode: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.setTorrentDownloadLimit(hashes: hashes, kibPerSecond: downloadKiB)
        try await api.setTorrentUploadLimit(hashes: hashes, kibPerSecond: uploadKiB)
        try await api.setShareLimits(hashes: hashes, ratio: ratio, seedingMinutes: seedingMinutes, inactiveMinutes: inactiveMinutes, action: action, mode: mode)
        await refresh()
    }

    func categoriesData() async throws -> Data {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.categoriesData()
    }

    func tagsData() async throws -> Data {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.tagsData()
    }

    func createCategory(_ name: String, savePath: String, downloadPathEnabled: Bool, downloadPath: String, ratioLimit: String, seedingMinutes: String, inactiveMinutes: String, mode: String, action: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.createCategory(name, savePath: savePath, downloadPathEnabled: downloadPathEnabled, downloadPath: downloadPath, ratioLimit: ratioLimit, seedingMinutes: seedingMinutes, inactiveMinutes: inactiveMinutes, mode: mode, action: action)
    }

    func editCategory(_ name: String, savePath: String, downloadPathEnabled: Bool, downloadPath: String, ratioLimit: String, seedingMinutes: String, inactiveMinutes: String, mode: String, action: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.editCategory(name, savePath: savePath, downloadPathEnabled: downloadPathEnabled, downloadPath: downloadPath, ratioLimit: ratioLimit, seedingMinutes: seedingMinutes, inactiveMinutes: inactiveMinutes, mode: mode, action: action)
    }

    func removeCategory(_ name: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.removeCategory(name)
        await refresh()
    }

    func createTags(_ names: [String]) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.createTags(names)
    }

    func removeTag(_ name: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.removeTag(name)
    }

    func setLocation(_ path: String, hashes: [String]) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.setTorrentField("setLocation", hashes: hashes, field: "location", value: path)
        await refresh()
    }

    func setCategory(_ category: String, hashes: [String]) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.ensureCategory(category)
        try await api.setTorrentField("setCategory", hashes: hashes, field: "category", value: category)
        await refresh()
    }

    func setTags(_ tags: String, hashes: [String]) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.setTorrentField("setTags", hashes: hashes, field: "tags", value: tags)
        await refresh()
    }

    func addTags(_ tags: [String], hashes: [String]) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.addTags(tags, hashes: hashes)
        await refresh()
    }

    func removeTorrentTags(_ tags: [String], hashes: [String]) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.removeTorrentTags(tags, hashes: hashes)
        await refresh()
    }

    func rename(_ hash: String, to name: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.rename(hash, to: name)
        await refresh()
    }

    func exportTorrent(_ hash: String) async throws -> Data {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.exportTorrent(hash)
    }

    func remove(_ hashes: [String], deleteFiles: Bool) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.remove(hashes, deleteFiles: deleteFiles)
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

    func add(url: String, downloader: String? = nil, options: TorrentAddOptions = TorrentAddOptions()) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.add(url: url, downloader: downloader, options: options)
        await refresh()
    }

    @discardableResult
    func add(file data: Data, filename: String, options: TorrentAddOptions = TorrentAddOptions(), verifyNewTorrent: Bool = false) async throws -> String? {
        guard let api else { throw TorrentStoreError.disconnected }
        let existingTorrentIDs = verifyNewTorrent ? try? await api.torrentIDs() : nil
        let addedTorrentID = try await api.add(file: data, filename: filename, options: options)
        guard verifyNewTorrent else {
            await refresh()
            return addedTorrentID
        }
        guard let existingTorrentIDs,
              let addedTorrentID,
              !existingTorrentIDs.contains(addedTorrentID.lowercased()) else {
            await refresh()
            return nil
        }

        for _ in 0..<10 {
            guard !Task.isCancelled else { break }
            do {
                if try await api.torrentIDs().contains(addedTorrentID.lowercased()) {
                    await refresh()
                    return addedTorrentID
                }
            } catch {
                break
            }
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { break }
        }
        await refresh()
        return nil
    }

    func parseTorrentMetadata(file data: Data, filename: String) async throws -> TorrentMetadata {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.parseTorrentMetadata(file: data, filename: filename)
    }

    func fetchTorrentMetadata(source: String, downloader: String? = nil) async throws -> TorrentMetadata {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.fetchTorrentMetadata(source: source, downloader: downloader)
    }

    func saveTorrentMetadata(source: String) async throws -> Data {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.saveTorrentMetadata(source: source)
    }

    func properties(for hash: String) async throws -> TorrentProperties {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.properties(for: hash)
    }

    func pieceStates(for hash: String) async throws -> [Int] {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.pieceStates(for: hash)
    }

    func pieceAvailability(for hash: String) async throws -> [Int] {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.pieceAvailability(for: hash)
    }

    func trackers(for hash: String) async throws -> [TorrentTracker] {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.trackers(for: hash)
    }

    func files(for hash: String) async throws -> [TorrentFile] {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.files(for: hash)
    }

    func setFilePriority(hash: String, indices: [Int], priority: Int) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.setFilePriority(hash: hash, indices: indices, priority: priority)
    }

    func renameFile(hash: String, oldPath: String, newPath: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.renameFile(hash: hash, oldPath: oldPath, newPath: newPath)
    }

    func addTracker(hash: String, url: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.addTracker(hash: hash, url: url)
    }

    func addTrackers(hashes: [String], entries: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.addTrackers(hashes: hashes, entries: entries)
    }

    func editTracker(hash: String, url: String, newURL: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.editTracker(hash: hash, url: url, newURL: newURL)
    }

    func moveTracker(hash: String, url: String, tier: Int) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.moveTracker(hash: hash, url: url, tier: tier)
    }

    func reannounceTrackers(hash: String, urls: [String]) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.reannounceTrackers(hash: hash, urls: urls)
    }

    func removeTracker(hash: String, url: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.removeTracker(hash: hash, url: url)
    }

    func removeTrackers(hashes: [String], urls: [String]) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.removeTrackers(hashes: hashes, urls: urls)
    }

    func removeTrackerHostFromAllTorrents(_ host: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.removeTrackerHostFromAllTorrents(host)
        trackerSummaryRefreshedAt = nil
        await refresh()
    }

    func addWebSeed(hash: String, url: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.addWebSeed(hash: hash, url: url)
    }

    func editWebSeed(hash: String, url: String, newURL: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.editWebSeed(hash: hash, url: url, newURL: newURL)
    }

    func removeWebSeed(hash: String, url: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.removeWebSeed(hash: hash, url: url)
    }

    func addPeer(hash: String, address: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.addPeer(hash: hash, address: address)
    }

    func banPeer(address: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.banPeer(address: address)
    }

    func setSessionPaused(_ paused: Bool) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.setSessionPaused(paused)
    }

    func toggleSpeedLimitsMode() async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.toggleSpeedLimitsMode()
    }

    func speedLimits() async throws -> (SpeedLimits, Bool) {
        guard let api else { throw TorrentStoreError.disconnected }
        async let limits = api.speedLimits()
        async let mode = api.alternativeSpeedMode()
        return try await (limits, mode)
    }

    func setSpeedLimits(_ limits: SpeedLimits, alternativeMode: Bool) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.setSpeedLimits(limits, alternativeMode: alternativeMode)
        await refresh()
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

    func searchJobs() async throws -> [SearchJobStatus] {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.searchJobs()
    }

    func startSearch(_ pattern: String, category: String = "all", plugin: String = "enabled") async throws -> Int {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.startSearch(pattern, category: category, plugin: plugin)
    }

    func stopSearch(_ id: Int) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.stopSearch(id)
    }

    func deleteSearch(_ id: Int) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.deleteSearch(id)
    }

    func installSearchPlugin(_ source: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.installSearchPlugin(source)
    }

    func uninstallSearchPlugin(_ name: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.uninstallSearchPlugin(name)
    }

    func enableSearchPlugin(_ name: String, enabled: Bool) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.enableSearchPlugin(name, enabled: enabled)
    }

    func updateSearchPlugins() async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.updateSearchPlugins()
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

    func rssFolders() async throws -> [RSSFolder] {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.rssFolders()
    }

    func addRSSFeed(_ url: String, path: String? = nil) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.addRSSFeed(url, path: path)
    }

    func addRSSArticle(_ article: RSSArticle) async throws {
        let url = article.torrentURL.isEmpty ? article.link : article.torrentURL
        try await add(url: url)
    }

    func markRSSArticleRead(path: String, articleID: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.markRSSArticleRead(path: path, articleID: articleID)
    }

    func markRSSFeedRead(path: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.markRSSFeedRead(path: path)
    }

    func refreshRSSFeed(path: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.refreshRSSFeed(path: path)
    }

    func editRSSFeed(path: String, url: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.editRSSFeed(path: path, url: url)
    }

    func removeRSSFeed(path: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.removeRSSFeed(path: path)
    }

    func addRSSFolder(path: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.addRSSFolder(path: path)
    }

    func moveRSSItem(path: String, to destination: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.moveRSSItem(path: path, to: destination)
    }

    func rssRulesData() async throws -> Data {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.rssRulesData()
    }

    func exportRSSRules() async throws -> Data {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.exportRSSRules()
    }

    func importRSSRules(_ data: Data) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.importRSSRules(data)
    }

    func setRSSRule(name: String, definition: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.setRSSRule(name: name, definition: definition)
    }

    func renameRSSRule(_ name: String, to newName: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.renameRSSRule(name, to: newName)
    }

    func cloneRSSRule(_ name: String, as newName: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.cloneRSSRule(name, as: newName)
    }

    func removeRSSRule(_ name: String) async throws {
        guard let api else { throw TorrentStoreError.disconnected }
        try await api.removeRSSRule(name)
    }

    func rssRuleMatches(_ name: String) async throws -> Data {
        guard let api else { throw TorrentStoreError.disconnected }
        return try await api.rssRuleMatches(name)
    }
}

struct TransferSample: Identifiable {
    let date: Date
    let totalDownload: Int64
    let totalUpload: Int64
    let payloadDownload: Int64
    let payloadUpload: Int64
    let overheadDownload: Int64
    let overheadUpload: Int64
    let dhtDownload: Int64
    let dhtUpload: Int64
    let trackerDownload: Int64
    let trackerUpload: Int64

    init(date: Date, status: TransferStatus) {
        self.date = date
        totalDownload = status.totalDownloadRate
        totalUpload = status.totalUploadRate
        payloadDownload = status.payloadDownloadRate
        payloadUpload = status.payloadUploadRate
        overheadDownload = status.overheadDownloadRate
        overheadUpload = status.overheadUploadRate
        dhtDownload = status.dhtDownloadRate
        dhtUpload = status.dhtUploadRate
        trackerDownload = status.trackerDownloadRate
        trackerUpload = status.trackerUploadRate
    }

    func value(for series: SpeedGraphSeries) -> Int64 {
        switch series {
        case .totalUpload: totalUpload
        case .totalDownload: totalDownload
        case .payloadUpload: payloadUpload
        case .payloadDownload: payloadDownload
        case .overheadUpload: overheadUpload
        case .overheadDownload: overheadDownload
        case .dhtUpload: dhtUpload
        case .dhtDownload: dhtDownload
        case .trackerUpload: trackerUpload
        case .trackerDownload: trackerDownload
        }
    }

    var id: Date { date }
}

enum SpeedGraphSeries: String, CaseIterable, Identifiable {
    case totalUpload, totalDownload
    case payloadUpload, payloadDownload
    case overheadUpload, overheadDownload
    case dhtUpload, dhtDownload
    case trackerUpload, trackerDownload

    var id: String { rawValue }

    var title: String {
        switch self {
        case .totalUpload: "Total Upload"
        case .totalDownload: "Total Download"
        case .payloadUpload: "Payload Upload"
        case .payloadDownload: "Payload Download"
        case .overheadUpload: "Overhead Upload"
        case .overheadDownload: "Overhead Download"
        case .dhtUpload: "DHT Upload"
        case .dhtDownload: "DHT Download"
        case .trackerUpload: "Tracker Upload"
        case .trackerDownload: "Tracker Download"
        }
    }
}
