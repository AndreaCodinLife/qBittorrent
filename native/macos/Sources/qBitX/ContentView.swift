import SwiftUI
import QBitXThemeSupport
import Charts
import UniformTypeIdentifiers
import TorrentSourceFileSupport
import LocalAuthentication
import Darwin

private enum MainTab: String, CaseIterable, Identifiable {
    case transfers = "Transfers"
    case search = "Search"
    case rss = "RSS"
    var id: String { rawValue }
}

private enum DetailTab: String, CaseIterable, Identifiable {
    case general = "General"
    case trackers = "Trackers"
    case peers = "Peers"
    case httpSources = "HTTP Sources"
    case content = "Content"
    case speed = "Speed"
    var id: String { rawValue }
}

private struct TorrentSort: Identifiable, Equatable {
    let title: String
    let key: String
    var id: String { key }

    static let allCases = [
        TorrentSort(title: "Queue Position", key: "priority"),
        TorrentSort(title: "Name", key: "name"),
        TorrentSort(title: "Size", key: "size"),
        TorrentSort(title: "Total Size", key: "total_size"),
        TorrentSort(title: "Progress", key: "progress"),
        TorrentSort(title: "Status", key: "state"),
        TorrentSort(title: "Seeds", key: "num_seeds"),
        TorrentSort(title: "Peers", key: "num_leechs"),
        TorrentSort(title: "Down Speed", key: "dlspeed"),
        TorrentSort(title: "Up Speed", key: "upspeed"),
        TorrentSort(title: "ETA", key: "eta"),
        TorrentSort(title: "Ratio", key: "ratio"),
        TorrentSort(title: "Popularity", key: "popularity"),
        TorrentSort(title: "Category", key: "category"),
        TorrentSort(title: "Tags", key: "tags"),
        TorrentSort(title: "Added On", key: "added_on"),
        TorrentSort(title: "Seeding Since", key: "completion_on"),
        TorrentSort(title: "Tracker", key: "tracker"),
        TorrentSort(title: "Down Limit", key: "dl_limit"),
        TorrentSort(title: "Up Limit", key: "up_limit"),
        TorrentSort(title: "Downloaded", key: "downloaded"),
        TorrentSort(title: "Uploaded", key: "uploaded"),
        TorrentSort(title: "Session Downloaded", key: "downloaded_session"),
        TorrentSort(title: "Session Uploaded", key: "uploaded_session"),
        TorrentSort(title: "Amount Left", key: "amount_left"),
        TorrentSort(title: "Active Time", key: "time_active"),
        TorrentSort(title: "Save Path", key: "save_path"),
        TorrentSort(title: "Completed", key: "completed"),
        TorrentSort(title: "Ratio Limit", key: "ratio_limit"),
        TorrentSort(title: "Last Seen Complete", key: "seen_complete"),
        TorrentSort(title: "Last Activity", key: "last_activity"),
        TorrentSort(title: "Availability", key: "availability"),
        TorrentSort(title: "Download Path", key: "download_path"),
        TorrentSort(title: "Infohash v1", key: "infohash_v1"),
        TorrentSort(title: "Infohash v2", key: "infohash_v2"),
        TorrentSort(title: "Reannounce", key: "reannounce"),
        TorrentSort(title: "Private", key: "private"),
        TorrentSort(title: "Created On", key: "creation_date")
    ]

    static let name = allCases[1]
}

private enum TorrentDisplayValues {
    static let hiddenWhenZero: Set<String> = [
        "size", "total_size", "seeds", "peers", "ratio", "ratio_limit", "popularity", "dl_limit", "up_limit",
        "downloaded", "uploaded", "downloaded_session", "uploaded_session", "amount_left", "completed",
        "availability", "reannounce", "time_active", "private"
    ]
    static let hiddenWhenInfinite: Set<String> = ["ratio", "ratio_limit", "popularity", "dl_limit", "up_limit"]
    static let infinityLabels = ["unlimited", "infinity", "∞"]
}

private struct TorrentCompletionState: Equatable {
    let isComplete: Bool
    let rawState: String
}

private struct TorrentCompletionSnapshot: Equatable {
    let stateByID: [String: TorrentCompletionState]

    init(_ torrents: [Torrent]) {
        stateByID = Dictionary(uniqueKeysWithValues: torrents.map {
            ($0.id, TorrentCompletionState(isComplete: $0.progress >= 1, rawState: $0.rawState))
        })
    }
}

private struct RecursiveTorrentCandidate: Identifiable {
    let relativePath: String
    let savePath: String
    var id: String { "\(savePath)|\(relativePath)" }
    var filename: String { URL(fileURLWithPath: relativePath).lastPathComponent }
}

private struct PendingDuplicateTorrent: Identifiable {
    let id: String
    let name: String
    let isPrivate: Bool
    let mergeByDefault: Bool
    let trackers: [TorrentMetadataTracker]
    let webSeeds: [String]
}

private struct TrackerTableRow: Identifiable {
    let tracker: TorrentTracker
    let endpoint: TorrentTrackerEndpoint?
    let children: [TrackerTableRow]?

    init(tracker: TorrentTracker, endpoint: TorrentTrackerEndpoint?, children: [TrackerTableRow]? = nil) {
        self.tracker = tracker
        self.endpoint = endpoint
        self.children = children
    }

    var id: String {
        guard let endpoint else { return "tracker:\(tracker.url)" }
        return "endpoint:\(tracker.url):\(endpoint.id)"
    }
    var flattened: [TrackerTableRow] { [self] + (children ?? []).flatMap(\.flattened) }
    var urlSortValue: String { endpoint?.name ?? tracker.url }
    var tierSortValue: Int { endpoint == nil ? (tracker.tier ?? -1) : -1 }
    var protocolSortValue: Int { endpoint?.bt_version ?? -1 }
    var statusSortValue: Int { endpoint.map { $0.status ?? -1 } ?? tracker.status ?? -1 }
    var isUpdating: Bool { endpoint.map { $0.updating ?? false } ?? tracker.updating ?? false }
    var peersSortValue: Int { endpoint.map { $0.num_peers ?? -1 } ?? tracker.num_peers ?? -1 }
    var seedsSortValue: Int { endpoint.map { $0.num_seeds ?? -1 } ?? tracker.num_seeds ?? -1 }
    var leechesSortValue: Int { endpoint.map { $0.num_leeches ?? -1 } ?? tracker.num_leeches ?? -1 }
    var downloadedSortValue: Int { endpoint.map { $0.num_downloaded ?? -1 } ?? tracker.num_downloaded ?? -1 }
    var messageSortValue: String { endpoint.map { $0.msg ?? "" } ?? tracker.msg ?? "" }
    var nextAnnounceSortValue: Int64 { endpoint.map { $0.next_announce ?? -1 } ?? tracker.next_announce ?? -1 }
    var minAnnounceSortValue: Int64 { endpoint.map { $0.min_announce ?? -1 } ?? tracker.min_announce ?? -1 }
}

private struct TorrentContentRow: Identifiable {
    let id: String
    let name: String
    let path: String
    let file: TorrentFile?
    let children: [TorrentContentRow]?

    var isDirectory: Bool { file == nil }
    var flattened: [TorrentContentRow] { [self] + (children ?? []).flatMap(\.flattened) }
    var fileIDs: Set<Int> {
        var result = Set(file.map { [$0.index] } ?? [])
        for child in children ?? [] { result.formUnion(child.fileIDs) }
        return result
    }
    var sizeSortValue: Int64 {
        if let file { return file.size }
        return (children ?? []).reduce(0) { $0 + $1.sizeSortValue }
    }
    var remainingSortValue: Int64 {
        if let file {
            guard file.priority != 0 else { return 0 }
            return Int64(Double(file.size) * max(0, 1 - file.progress))
        }
        return (children ?? []).filter { $0.prioritySortValue != 0 }.reduce(0) { $0 + $1.remainingSortValue }
    }
    var availabilitySortValue: Double {
        if let file { return file.size > 0 ? (file.availability ?? -1) : 0 }
        let activeChildren = (children ?? []).filter { $0.prioritySortValue != 0 }
        let activeSize = activeChildren.reduce(Int64(0)) { $0 + $1.sizeSortValue }
        guard activeSize > 0 else { return -1 }
        let weightedAvailability = activeChildren.reduce(0.0) { total, child in
            guard child.availabilitySortValue >= 0 else { return total }
            return total + child.availabilitySortValue * Double(child.sizeSortValue)
        }
        return weightedAvailability / Double(activeSize)
    }
    var progressSortValue: Double {
        if let file { return file.size > 0 ? file.progress : 1 }
        let activeChildren = (children ?? []).filter { $0.prioritySortValue != 0 }
        let activeSize = activeChildren.reduce(Int64(0)) { $0 + $1.sizeSortValue }
        guard activeSize > 0 else { return 1 }
        let completed = activeChildren.reduce(0.0) { $0 + Double($1.sizeSortValue) * $1.progressSortValue }
        return min(1, completed / Double(activeSize))
    }
    var prioritySortValue: Int {
        if let file { return file.priority }
        let priorities = Set((children ?? []).flatMap(\.flattened).compactMap { $0.file?.priority })
        return priorities.count == 1 ? (priorities.first ?? -1) : -1
    }
}

private final class TorrentContentNodeBuilder {
    let name: String
    let path: String
    var file: TorrentFile?
    var childOrder: [String] = []
    var children: [String: TorrentContentNodeBuilder] = [:]

    init(name: String, path: String) {
        self.name = name
        self.path = path
    }

    func child(named name: String) -> TorrentContentNodeBuilder {
        if let child = children[name] { return child }
        let childPath = path.isEmpty ? name : "\(path)/\(name)"
        let child = TorrentContentNodeBuilder(name: name, path: childPath)
        children[name] = child
        childOrder.append(name)
        return child
    }

    func makeRow() -> TorrentContentRow {
        let childRows = childOrder.compactMap { children[$0]?.makeRow() }
        return TorrentContentRow(
            id: file.map { "file:\($0.index)" } ?? "folder:\(path)",
            name: name,
            path: path,
            file: file,
            children: childRows.isEmpty ? nil : childRows
        )
    }
}

struct ContentView: View {
    @Bindable var store: TorrentStore
    @Bindable var programUpdateChecker: ProgramUpdateState
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("qBitX.showFiltersSidebar") private var showFiltersSidebar = true
    @AppStorage("qBitX.showStatusBar") private var showStatusBar = true
    @AppStorage("qBitX.showDetailPane") private var showDetailPane = true
    @AppStorage("qBitX.showToolbar") private var showToolbar = true
    @AppStorage("qBitX.toolbarStyle") private var toolbarStyle = "system"
    @AppStorage("qBitX.showSpeedInTitleBar") private var showSpeedInTitleBar = false
    @AppStorage("qBitX.showSpeedInDock") private var showSpeedInDock = false
    @AppStorage("qBitX.showSpeedInMenuBar") private var showSpeedInMenuBar = false
    @AppStorage("qBitX.showFreeDiskSpace") private var showFreeDiskSpace = false
    @AppStorage("qBitX.showExternalIP") private var showExternalIP = false
    @AppStorage("qBitX.dragContentFiles") private var dragContentFiles = false
    @AppStorage("qBitX.contentFileFilterMode") private var contentFileFilterMode = "wildcards"
    @AppStorage("qBitX.showTorrentAdditionDialog") private var showTorrentAdditionDialog = true
    @AppStorage("qBitX.autoDeleteTorrentFileMode") private var autoDeleteTorrentFileMode = 0
    @AppStorage("qBitX.appearance") private var appearance = "system"
    @AppStorage("qBitX.themePalette") private var themePaletteJSON = ""
    @AppStorage("qBitX.doubleClick.downloading") private var downloadingDoubleClickAction = TorrentDoubleClickAction.toggleStop.rawValue
    @AppStorage("qBitX.doubleClick.completed") private var completedDoubleClickAction = TorrentDoubleClickAction.openDestination.rawValue
    @AppStorage("qBitX.hideZeroValues") private var hideZeroValues = false
    @AppStorage("qBitX.hideZeroValuesMode") private var hideZeroValuesMode = "always"
    @AppStorage("qBitX.confirmTorrentDeletion") private var confirmTorrentDeletion = true
    @AppStorage("qBitX.confirmRemoveAllTags") private var confirmRemoveAllTags = true
    @AppStorage("qBitX.confirmRemoveTrackerFromAllTorrents") private var confirmRemoveTrackerFromAllTorrents = true
    @AppStorage("qBitX.startMinimized") private var startMinimized = false
    @AppStorage("qBitX.showSplashOnStartup") private var showSplashOnStartup = true
    @AppStorage("qBitX.checkForUpdatesAutomatically") private var checkForUpdatesAutomatically = true
    @AppStorage("qBitX.alternatingTransferRows") private var alternatingTransferRows = true
    @AppStorage("qBitX.colorTransfersByState") private var colorTransfersByState = true
    @AppStorage("qBitX.progressBarFollowsStateColor") private var progressBarFollowsStateColor = false
    @AppStorage("qBitX.preventSleepWhenDownloading") private var preventSleepWhenDownloading = false
    @AppStorage("qBitX.preventSleepWhenSeeding") private var preventSleepWhenSeeding = false
    @AppStorage("qBitX.confirmAutoCompletionAction") private var confirmAutoCompletionAction = true
    @AppStorage("qBitX.showTrackerStatusFilter") private var showTrackerStatusFilter = true
    @AppStorage("qBitX.separateTrackerStatusFilter") private var separateTrackerStatusFilter = false
    @AppStorage("qBitX.hideZeroStatusFilters") private var hideZeroStatusFilters = false
    @AppStorage("qBitX.interfaceLocked") private var interfaceLocked = false
    @AppStorage("qBitX.downloadCompletionAction") private var downloadCompletionAction = "none"
    @AppStorage("qBitX.recursiveDownloadEnabled") private var recursiveDownloadEnabled = true
    @AppStorage("qBitX.systemNotificationsEnabled") private var systemNotificationsEnabled = true
    @AppStorage("qBitX.notifyTorrentAdded") private var notifyOnTorrentAdded = false
    @AppStorage("qBitX.notifyDownloadComplete") private var notifyOnDownloadComplete = true
    @AppStorage("qBitX.notifyTorrentError") private var notifyOnTorrentError = true
    @State private var selectedTorrentIDs: Set<String> = []
    @SceneStorage("qBitX.transferColumns") private var columnCustomization = TableColumnCustomization<Torrent>()
    @SceneStorage("qBitX.peerColumns") private var peerColumnCustomization = TableColumnCustomization<TorrentPeer>()
    @SceneStorage("qBitX.trackerColumns") private var trackerColumnCustomization = TableColumnCustomization<TrackerTableRow>()
    @SceneStorage("qBitX.contentColumns") private var contentColumnCustomization = TableColumnCustomization<TorrentContentRow>()
    @State private var selectedPeerIDs: Set<String> = []
    @State private var selectedTrackerRowIDs: Set<String> = []
    @State private var peerSortOrder = [KeyPathComparator<TorrentPeer>(\.ip)]
    @State private var trackerSortOrder = [KeyPathComparator<TrackerTableRow>(\.urlSortValue)]
    @State private var contentSortOrder = [KeyPathComparator<TorrentContentRow>(\.name)]
    @State private var contentFileFilter = ""
    @State private var textAction: TorrentTextAction?
    @State private var detailInput: DetailInput?
    @State private var statusFilter: TorrentFilter = .all
    @State private var trackerStatusFilter: TrackerStatusFilter?
    @State private var categoryFilter: String?
    @State private var tagFilter: String?
    @State private var trackerFilter: String?
    @State private var searchText = ""
    @FocusState private var torrentFilterFocused: Bool
    @State private var sortField: TorrentSort = .name
    @State private var sortDescending = false
    @AppStorage("qBitX.speedGraphPeriod") private var speedGraphPeriod = 300
    @AppStorage("qBitX.speedGraph.totalUpload") private var showTotalUploadGraph = true
    @AppStorage("qBitX.speedGraph.totalDownload") private var showTotalDownloadGraph = true
    @AppStorage("qBitX.speedGraph.payloadUpload") private var showPayloadUploadGraph = true
    @AppStorage("qBitX.speedGraph.payloadDownload") private var showPayloadDownloadGraph = true
    @AppStorage("qBitX.speedGraph.overheadUpload") private var showOverheadUploadGraph = true
    @AppStorage("qBitX.speedGraph.overheadDownload") private var showOverheadDownloadGraph = true
    @AppStorage("qBitX.speedGraph.dhtUpload") private var showDHTUploadGraph = true
    @AppStorage("qBitX.speedGraph.dhtDownload") private var showDHTDownloadGraph = true
    @AppStorage("qBitX.speedGraph.trackerUpload") private var showTrackerUploadGraph = true
    @AppStorage("qBitX.speedGraph.trackerDownload") private var showTrackerDownloadGraph = true
    @State private var mainTab: MainTab = .transfers
    @State private var detailTab: DetailTab = .general
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var showsURLSheet = false
    @State private var incomingTorrentURL: String?
    @State private var pendingExternalURLs: [URL] = []
    @State private var pendingExternalFiles: [PendingTorrentFile] = []
    @State private var pendingFileImportError: String?
    @State private var isAddingExternalTorrent = false
    @State private var showsFileImporter = false
    @State private var pendingTorrentFile: PendingTorrentFile?
    @State private var showsRemoveConfirmation = false
    @State private var showsClearTagsConfirmation = false
    @State private var recheckConfirmationHashes: [String]?
    @State private var trackerHostRemovalConfirmation: String?
    @State private var automaticManagementConfirmationHashes: [String]?
    @State private var clearTagsHashes: [String] = []
    @State private var showsConnectionSettings = false
    @State private var showsAppPreferences = false
    @State private var showsBackendPreferences = false
    @State private var showsSpeedLimits = false
    @State private var showsStatistics = false
    @State private var showsExecutionLog = false
    @State private var showsTorrentCreator = false
    @State private var showsCookies = false
    @State private var torrentOptionsTarget: TorrentOptionsTarget?
    @State private var trackerBatchEditorTarget: TrackerBatchEditorTarget?
    @State private var contentLayoutEditorTarget: ContentLayoutEditorTarget?
    @State private var showsOrganization = false
    @State private var organizationInitialCategory: String?
    @State private var showsAbout = false
    @State private var showsFileAssociations = false
    @State private var previewTorrent: Torrent?
    @State private var previewTorrentQueue: [Torrent] = []
    @State private var authenticationError: String?
    @State private var hasObservedTorrentCompletionSnapshot = false
    @State private var showsDownloadCompletionAction = false
    @State private var showsRecursiveTorrentConfirmation = false
    @State private var recursiveTorrentCandidates: [RecursiveTorrentCandidate] = []
    @State private var recursiveTorrentSourceNames: [String] = []
    @State private var inspectedRecursiveTorrentIDs: Set<String> = []
    @State private var actionError: String?
    @State private var retryID = 0
    @State private var commandActions: QBitXCommandActions?
    @State private var properties: TorrentProperties?
    @State private var pieceStates: [Int] = []
    @State private var pieceAvailability: [Int] = []
    @State private var trackers: [TorrentTracker] = []
    @State private var categoryCatalog: Set<String> = []
    @State private var tagCatalog: Set<String> = []
    @State private var files: [TorrentFile] = []
    @State private var peers: [TorrentPeer] = []
    @State private var webSeeds: [TorrentWebSeed] = []
    @State private var selectedContentNodeIDs: Set<String> = []
    @State private var themePalette = QBitXThemePalette()

    private var torrents: [Torrent] { store.torrents }
    private var torrentCompletionSnapshot: TorrentCompletionSnapshot { TorrentCompletionSnapshot(torrents) }

    private var visibleTorrents: [Torrent] {
        torrents.filter { torrent in
            statusFilter.includes(torrent)
                && (trackerStatusFilter.map { $0.includes(torrent) } ?? true)
                && (categoryFilter.map { category in torrent.category == category || torrent.category.hasPrefix(category + "/") } ?? true)
                && (tagFilter.map { tag in torrent.tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(tag) } ?? true)
                && (trackerFilter.map { host in host.isEmpty ? torrent.trackerHosts.isEmpty : torrent.trackerHosts.contains(host) } ?? true)
                && (searchText.isEmpty || torrent.name.localizedCaseInsensitiveContains(searchText))
        }.sorted { left, right in
            let leftNumber = sortNumber(for: sortField.key, torrent: left)
            let rightNumber = sortNumber(for: sortField.key, torrent: right)
            let result: ComparisonResult
            if let leftNumber, let rightNumber {
                result = compare(leftNumber, rightNumber)
            } else {
                result = sortText(for: sortField.key, torrent: left).localizedStandardCompare(sortText(for: sortField.key, torrent: right))
            }
            return sortDescending ? result == .orderedDescending : result == .orderedAscending
        }
    }

    private func sortNumber(for key: String, torrent: Torrent) -> Double? {
        switch key {
        case "size": return Double(torrent.sizeBytes)
        case "progress": return torrent.progress
        case "num_seeds": return Double(torrent.seeds)
        case "num_leechs": return Double(torrent.peers)
        case "dlspeed": return Double(torrent.downloadRateBytes)
        case "upspeed": return Double(torrent.uploadRateBytes)
        case "eta": return Double(torrent.etaSeconds)
        case "ratio": return torrent.ratio
        case "category": return nil
        default: return torrent.sortNumbers[key]
        }
    }

    private func sortText(for key: String, torrent: Torrent) -> String {
        switch key {
        case "name": return torrent.name
        case "state": return torrent.state.rawValue
        case "category": return torrent.category
        default: return torrent.column(key)
        }
    }

    private func compare<T: Comparable>(_ left: T, _ right: T) -> ComparisonResult {
        if left < right { return .orderedAscending }
        if left > right { return .orderedDescending }
        return .orderedSame
    }

    private func shouldHideZeroValues(for torrent: Torrent) -> Bool {
        hideZeroValues && (hideZeroValuesMode == "always" || (hideZeroValuesMode == "stopped" && torrent.rawState == "stoppedDL"))
    }

    private func displayValue(_ value: String, numericValue: Double?, key: String, torrent: Torrent) -> String {
        guard shouldHideZeroValues(for: torrent) else { return value }
        if TorrentDisplayValues.hiddenWhenZero.contains(key), numericValue == 0 { return "" }
        if TorrentDisplayValues.hiddenWhenInfinite.contains(key),
           let numericValue, numericValue < 0 { return "" }
        if TorrentDisplayValues.hiddenWhenInfinite.contains(key),
           TorrentDisplayValues.infinityLabels.contains(where: value.localizedCaseInsensitiveContains) { return "" }
        return value
    }

    private func displayColumn(_ key: String, torrent: Torrent) -> String {
        displayValue(torrent.column(key), numericValue: torrent.sortNumbers[key], key: key, torrent: torrent)
    }

    private func stateColored<Content: View>(_ content: Content, for torrent: Torrent) -> some View {
        content.foregroundStyle(colorTransfersByState ? stateColor(for: torrent) : Color.primary)
    }

    private func stateColor(for torrent: Torrent) -> Color {
        switch torrent.rawState {
        case "downloading": themedStateColor("TransferList.Downloading", fallback: .blue)
        case "metaDL": themedStateColor("TransferList.DownloadingMetadata", fallback: .blue)
        case "forcedMetaDL": themedStateColor("TransferList.ForcedDownloadingMetadata", fallback: .blue)
        case "forcedDL": themedStateColor("TransferList.ForcedDownloading", fallback: .blue)
        case "uploading": themedStateColor("TransferList.Uploading", fallback: .green)
        case "forcedUP": themedStateColor("TransferList.ForcedUploading", fallback: .green)
        case "stalledUP": themedStateColor("TransferList.StalledUploading", fallback: .orange)
        case "stalledDL": themedStateColor("TransferList.StalledDownloading", fallback: .orange)
        case "queuedDL": themedStateColor("TransferList.QueuedDownloading", fallback: .gray)
        case "queuedUP": themedStateColor("TransferList.QueuedUploading", fallback: .gray)
        case "checkingDL": themedStateColor("TransferList.CheckingDownloading", fallback: .purple)
        case "checkingUP": themedStateColor("TransferList.CheckingUploading", fallback: .purple)
        case "checkingResumeData": themedStateColor("TransferList.CheckingResumeData", fallback: .purple)
        case "stoppedDL": themedStateColor("TransferList.StoppedDownloading", fallback: .gray)
        case "stoppedUP": themedStateColor("TransferList.StoppedUploading", fallback: .gray)
        case "moving": themedStateColor("TransferList.Moving", fallback: .purple)
        case "missingFiles": themedStateColor("TransferList.MissingFiles", fallback: .red)
        case "error": themedStateColor("TransferList.Error", fallback: .red)
        default: .blue
        }
    }

    private var isUsingDarkThemeColors: Bool {
        switch appearance {
        case "dark": true
        case "light": false
        default: colorScheme == .dark
        }
    }

    private func themeColor(for id: String) -> Color? {
        guard let color = themePalette.color(for: id, isDark: isUsingDarkThemeColors) else { return nil }
        return Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }

    private func themedStateColor(_ id: String, fallback: Color) -> Color {
        themeColor(for: id) ?? fallback
    }

    private func loadThemePalette() {
        themePalette = QBitXThemePalette(storedJSON: themePaletteJSON) ?? QBitXThemePalette()
    }

    private var selectedTorrent: Torrent? {
        torrents.first { $0.id == selectedTorrentID }
    }

    private var filteredContentFiles: [TorrentFile] {
        guard !contentFileFilter.isEmpty else { return files }
        return files.filter { filePathMatches($0.name, pattern: contentFileFilter, mode: contentFileFilterMode) }
    }
    private var filteredContentRows: [TorrentContentRow] {
        let root = TorrentContentNodeBuilder(name: "", path: "")
        for file in filteredContentFiles {
            let components = file.name.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard let last = components.last else { continue }
            var node = root
            for component in components.dropLast() { node = node.child(named: component) }
            node.child(named: last).file = file
        }
        return root.childOrder.compactMap { root.children[$0]?.makeRow() }
    }
    private var filteredContentNodeIDs: Set<String> {
        Set(filteredContentRows.flatMap(\.flattened).map(\.id))
    }
    private var sortedFilteredContentRows: [TorrentContentRow] {
        sortContentRows(filteredContentRows)
    }
    private var selectedFileIDs: Set<Int> {
        filteredContentRows.flatMap(\.flattened)
            .filter { selectedContentNodeIDs.contains($0.id) }
            .reduce(into: Set<Int>()) { $0.formUnion($1.fileIDs) }
    }

    private func selectAllFilteredContentFiles() {
        selectedContentNodeIDs.formUnion(filteredContentRows.flatMap(\.flattened).compactMap { $0.file == nil ? nil : $0.id })
    }

    private func deselectFilteredContent() {
        selectedContentNodeIDs.subtract(filteredContentNodeIDs)
    }

    private func sortContentRows(_ rows: [TorrentContentRow]) -> [TorrentContentRow] {
        rows.sorted(using: contentSortOrder).map { row in
            TorrentContentRow(id: row.id, name: row.name, path: row.path, file: row.file, children: row.children.map(sortContentRows))
        }
    }

    private var appColorSchemePreference: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    private var selectedTorrentID: String? {
        visibleTorrents.first { selectedTorrentIDs.contains($0.id) }?.id ?? selectedTorrentIDs.first
    }

    private var selectedHashes: [String] { selectedTorrentIDs.sorted() }

    private var allFilterCategories: [String] {
        categoryCatalog.union(torrents.map(\.category)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var allFilterTags: [String] {
        let assigned = torrents.flatMap { $0.tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
        return tagCatalog.union(assigned.filter { !$0.isEmpty }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func torrentHasTag(_ torrent: Torrent, _ tag: String) -> Bool {
        torrent.tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(tag)
    }

    private var allFilterTrackerHosts: [String] {
        Array(Set(torrents.flatMap(\.trackerHosts))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func isSelected(_ item: TorrentFilter) -> Bool {
        statusFilter == item && trackerStatusFilter == nil && categoryFilter == nil && tagFilter == nil && trackerFilter == nil
    }

    private func isSelected(_ item: TrackerStatusFilter) -> Bool {
        statusFilter == .all && categoryFilter == nil && tagFilter == nil && trackerFilter == nil
            && (item == .all ? trackerStatusFilter == nil : trackerStatusFilter == item)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            filterSidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        } detail: {
            VStack(spacing: 0) {
                mainTabs
                Divider()
                ZStack {
                    if store.hasCompletedInitialConnection {
                        SearchPane(store: store, isSearchTabVisible: Binding(get: { mainTab == .search }, set: { _ in }))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(mainTab == .search ? 1 : 0)
                            .allowsHitTesting(mainTab == .search)
                            .accessibilityHidden(mainTab != .search)

                        if mainTab == .transfers {
                            if showDetailPane {
                                VSplitView {
                                    torrentTable.frame(minHeight: 240)
                                    detailsPane.frame(minHeight: 170)
                                }
                            } else {
                                torrentTable
                            }
                        }
                        if mainTab == .rss {
                            RSSPane(store: store)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else if !showSplashOnStartup {
                        ProgressView("Starting qBittorrent…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showStatusBar {
                    Divider()
                    statusBar
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .confirmationDialog("Recursive download confirmation", isPresented: $showsRecursiveTorrentConfirmation, titleVisibility: .visible) {
                Button("Add Torrent Files (\(recursiveTorrentCandidates.count))") {
                    addRecursiveTorrentCandidates()
                }
                Button("Never") {
                    recursiveDownloadEnabled = false
                    discardRecursiveTorrentCandidates()
                }
                Button("No", role: .cancel) {
                    discardRecursiveTorrentCandidates()
                }
            } message: {
                Text(recursiveTorrentConfirmationMessage)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.locale, store.interfaceLocale.isEmpty ? .current : Locale(identifier: store.interfaceLocale))
        .preferredColorScheme(appColorSchemePreference)
        .onOpenURL(perform: handleOpenURL)
        .task(id: retryID) { store.start(retrying: retryID > 0) }
        .modifier(ProgramUpdatePresentation(checker: programUpdateChecker, automaticallyCheck: checkForUpdatesAutomatically))
        .task(id: store.isConnected) { if store.isConnected { await loadFilterCatalogs() } }
        .task(id: "\(selectedTorrentID ?? "")|\(detailTab.rawValue)|\(store.isConnected)") {
            selectedPeerIDs = []
            selectedTrackerRowIDs = []
            await loadDetails()
        }
        .task(id: "\(selectedTorrentID ?? "")|\(detailTab.rawValue)|\(store.isConnected)|\(mainTab.rawValue)|\(showDetailPane)") {
            guard selectedTorrentID != nil, mainTab == .transfers, showDetailPane, store.isConnected else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
                await refreshDetails(reportErrors: false)
            }
        }
        .onChange(of: torrents.map(\.id)) { _, ids in
            selectedTorrentIDs.formIntersection(ids)
            if selectedTorrentIDs.isEmpty, let first = ids.first { selectedTorrentIDs = [first] }
        }
        .onChange(of: torrentCompletionSnapshot) { previous, current in
            observeTorrentCompletions(from: previous, to: current)
        }
        .onChange(of: showsOrganization) { wasPresented, isPresented in
            if wasPresented && !isPresented { Task { await loadFilterCatalogs() } }
        }
        .onChange(of: store.isConnected) { _, isConnected in
            if isConnected { presentNextExternalURLIfReady() }
        }
        .onAppear {
            if commandActions == nil { commandActions = makeCommandActions() }
            loadThemePalette()
            sidebarVisibility = showFiltersSidebar ? .all : .detailOnly
            syncWindowTitle()
            MacOSStatusPresentation.updateDockSpeed(store.transferStatus, enabled: showSpeedInDock)
            store.updateSleepInhibition()
            if startMinimized {
                DispatchQueue.main.async { NSApp.keyWindow?.miniaturize(nil) }
            }
        }
        .onChange(of: themePaletteJSON) { _, _ in loadThemePalette() }
        .onChange(of: showSpeedInDock) { _, enabled in
            MacOSStatusPresentation.updateDockSpeed(store.transferStatus, enabled: enabled)
        }
        .onChange(of: preventSleepWhenDownloading) { _, _ in store.updateSleepInhibition() }
        .onChange(of: preventSleepWhenSeeding) { _, _ in store.updateSleepInhibition() }
        .onChange(of: showFiltersSidebar) { _, visible in sidebarVisibility = visible ? .all : .detailOnly }
        .onChange(of: "\(store.transferStatus.downloadText)|\(store.transferStatus.uploadText)|\(showSpeedInTitleBar)") { _, _ in syncWindowTitle() }
        .overlay {
            if interfaceLocked { lockedOverlay }
        }
        .overlay {
            if showSplashOnStartup && !store.hasCompletedInitialConnection {
                startupSplash
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.hasCompletedInitialConnection)
        .toolbar { toolbarContent }
        .toolbarVisibility(showToolbar ? .visible : .hidden, for: .windowToolbar)
        .focusedSceneValue(\.qBitXCommandActions, commandActions)
        .sheet(isPresented: $showsURLSheet, onDismiss: {
            incomingTorrentURL = nil
            presentNextExternalURLIfReady()
        }) {
            AddTorrentSheet(file: nil, store: store, initialURL: incomingTorrentURL ?? "", showOptions: showTorrentAdditionDialog) { url, downloader, options in
                try await store.add(url: url, downloader: downloader, options: options)
                return false
            }
        }
        .sheet(item: $pendingTorrentFile, onDismiss: presentNextExternalURLIfReady) { file in
            AddTorrentSheet(file: file, store: store, showOptions: showTorrentAdditionDialog) { source, _, options in
                if source.hasPrefix("magnet:") {
                    try await store.add(url: source, options: options)
                    return false
                } else {
                    var uploadOptions = options
                    uploadOptions.filePriorities = nil
                    return try await store.add(
                        file: file.data,
                        filename: file.name,
                        options: uploadOptions,
                        verifyNewTorrent: autoDeleteTorrentFileMode > 0
                    ) != nil
                }
            }
        }
        .sheet(isPresented: $showsConnectionSettings) {
            ConnectionSettingsView(store: store) { retryID += 1 }
        }
        .sheet(isPresented: $showsAppPreferences) { AppPreferencesView(store: store) }
        .sheet(isPresented: $showsBackendPreferences) { BackendPreferencesView(store: store) }
        .sheet(isPresented: $showsSpeedLimits) { SpeedLimitsView(store: store) }
        .sheet(isPresented: $showsStatistics) { StatisticsView(store: store) }
        .sheet(isPresented: $showsExecutionLog) { ExecutionLogView(store: store) }
        .sheet(isPresented: $showsTorrentCreator) { TorrentCreatorView(store: store) }
        .sheet(isPresented: $showsCookies) { CookiesView(store: store) }
        .sheet(item: $torrentOptionsTarget) { target in TorrentOptionsView(store: store, hashes: target.hashes) }
        .sheet(item: $trackerBatchEditorTarget) { target in TrackerBatchEditor(store: store, hashes: target.hashes) }
        .sheet(item: $contentLayoutEditorTarget) { target in
            TorrentContentLayoutEditor(store: store, hash: target.hash, torrentName: target.torrentName, initialFileIDs: target.initialFileIDs)
        }
        .sheet(item: $previewTorrent, onDismiss: presentNextPreview) { torrent in
            TorrentPreviewView(torrent: torrent, store: store) { url in NSWorkspace.shared.open(url) }
        }
        .sheet(isPresented: $showsOrganization) { OrganizationView(store: store, initialCategoryName: organizationInitialCategory) }
        .sheet(isPresented: $showsAbout) { AboutView(serverVersion: store.serverVersion) }
        .sheet(isPresented: $showsFileAssociations) { FileAssociationView() }
        .sheet(item: $textAction) { action in
            ValueSheet(
                title: action.title,
                hint: action.hint,
                initialValue: initialValue(for: action),
                allowsEmpty: action == .category || action == .tags,
                pathStore: action == .location ? store : nil
            ) { value in
                try await applyTextAction(action, value: value)
            }
        }
        .sheet(item: $detailInput) { input in
            ValueSheet(
                title: input.title,
                hint: input.hint,
                initialValue: input.initialValue,
                allowsMultiline: input.operation == .addPeer
            ) { value in
                try await applyDetailInput(input, value: value)
            }
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "torrent") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            do {
                queueExternalTorrentFiles(try result.get())
            } catch { actionError = error.localizedDescription }
        }
        .confirmationDialog("Remove selected torrents?", isPresented: $showsRemoveConfirmation) {
            Button("Remove Torrent") { removeSelectedTorrent(deleteFiles: false) }
            Button("Remove Torrent and Downloaded Files", role: .destructive) { removeSelectedTorrent(deleteFiles: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removing downloaded files cannot be undone.")
        }
        .confirmationDialog("Remove all tags from selected torrents?", isPresented: $showsClearTagsConfirmation) {
            Button("Remove All Tags", role: .destructive) {
                removeAllTags(from: clearTagsHashes)
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Recheck selected torrents?", isPresented: Binding(
            get: { recheckConfirmationHashes != nil },
            set: { if !$0 { recheckConfirmationHashes = nil } }
        ), titleVisibility: .visible) {
            Button("Recheck") {
                guard let hashes = recheckConfirmationHashes else { return }
                recheckConfirmationHashes = nil
                runBulkAction(hashes: hashes) { try await store.command(.recheck, hashes: $0) }
            }
            Button("Cancel", role: .cancel) { recheckConfirmationHashes = nil }
        } message: {
            Text("Are you sure you want to recheck the selected torrents?")
        }
        .confirmationDialog("Remove tracker from all torrents?", isPresented: Binding(
            get: { trackerHostRemovalConfirmation != nil },
            set: { if !$0 { trackerHostRemovalConfirmation = nil } }
        ), titleVisibility: .visible) {
            Button("Remove Tracker", role: .destructive) {
                removePendingTrackerHost()
            }
            Button("Remove Tracker and Don’t Ask Again", role: .destructive) {
                confirmRemoveTrackerFromAllTorrents = false
                removePendingTrackerHost()
            }
            Button("Cancel", role: .cancel) { trackerHostRemovalConfirmation = nil }
        } message: {
            Text("Remove all announce URLs for \(trackerHostRemovalConfirmation ?? "this tracker") from every torrent?")
        }
        .confirmationDialog("Enable Automatic Torrent Management?", isPresented: Binding(
            get: { automaticManagementConfirmationHashes != nil },
            set: { if !$0 { automaticManagementConfirmationHashes = nil } }
        ), titleVisibility: .visible) {
            Button("Enable") {
                guard let hashes = automaticManagementConfirmationHashes else { return }
                automaticManagementConfirmationHashes = nil
                runBulkAction(hashes: hashes) { try await store.setAutomaticManagement(true, hashes: $0) }
            }
            Button("Cancel", role: .cancel) { automaticManagementConfirmationHashes = nil }
        } message: {
            Text("Automatic management may move the selected torrents to their category folders.")
        }
        .confirmationDialog("All downloads are complete", isPresented: $showsDownloadCompletionAction) {
            Button(downloadCompletionLabel, role: downloadCompletionAction == "shutdown" || downloadCompletionAction == "restart" ? .destructive : nil) {
                performDownloadCompletionAction()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("qBitX is set to \(downloadCompletionLabel.lowercased()) when all downloads finish.")
        }
        .alert("Action failed", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .alert("Unable to unlock qBitX", isPresented: Binding(
            get: { authenticationError != nil },
            set: { if !$0 { authenticationError = nil } }
        )) {
            Button("OK") { authenticationError = nil }
        } message: {
            Text(authenticationError ?? "")
        }
    }

    private func makeCommandActions() -> QBitXCommandActions {
        QBitXCommandActions(
            addTorrentFile: { showsFileImporter = true },
            addTorrentURL: { showsURLSheet = true },
            pasteTorrentLinks: pasteTorrentLinks,
            createTorrent: { showsTorrentCreator = true },
            removeSelected: { requestRemoval(hashes: selectedHashes) },
            startSelected: { runBulkAction { try await store.command(.start, hashes: $0) } },
            stopSelected: { runBulkAction { try await store.command(.stop, hashes: $0) } },
            forceStartSelected: { runBulkAction { try await store.setForceStart(true, hashes: $0) } },
            recheckSelected: { requestTorrentRecheck(hashes: selectedHashes) },
            moveSelectedToTop: { runBulkAction { try await store.command(.topPrio, hashes: $0) } },
            moveSelectedUp: { runBulkAction { try await store.command(.increasePrio, hashes: $0) } },
            moveSelectedDown: { runBulkAction { try await store.command(.decreasePrio, hashes: $0) } },
            moveSelectedToBottom: { runBulkAction { try await store.command(.bottomPrio, hashes: $0) } },
            pauseSession: { setSessionPaused(true) },
            resumeSession: { setSessionPaused(false) },
            toggleSpeedLimitsMode: toggleSpeedLimitsMode,
            showAppPreferences: { showsAppPreferences = true },
            showPreferences: { showsBackendPreferences = true },
            showStatistics: { showsStatistics = true },
            showSpeedLimits: { showsSpeedLimits = true },
            focusTorrentFilter: { mainTab = .transfers; torrentFilterFocused = true },
            selectTransfers: { mainTab = .transfers },
            selectSearch: { mainTab = .search },
            selectRSS: { mainTab = .rss },
            showExecutionLog: { showsExecutionLog = true },
            openDocumentation: { openURL("https://www.qbittorrent.org/documentation") },
            checkForUpdates: { Task { await programUpdateChecker.check(manual: true) } },
            donate: { openURL("https://www.qbittorrent.org/donate") },
            showAbout: { showsAbout = true }
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
                Button { showsFileImporter = true } label: {
                    toolbarLabel("Add Torrent", image: "plus")
                }
                .help("Open a .torrent file")

                Button { showsURLSheet = true } label: {
                    toolbarLabel("Add URL", image: "link.badge.plus")
                }
                .help("Add a magnet link or torrent URL")

                Button(role: .destructive) { requestRemoval(hashes: selectedHashes) } label: {
                    toolbarLabel("Remove", image: "trash")
                }
                .disabled(selectedTorrent == nil)

                Button { runBulkAction { try await store.command(.start, hashes: $0) } } label: {
                    toolbarLabel("Start", image: "play.fill")
                }
                .disabled(selectedTorrent == nil)

                Button { runBulkAction { try await store.command(.stop, hashes: $0) } } label: {
                    toolbarLabel("Stop", image: "pause.fill")
                }
                .disabled(selectedTorrent == nil)

                Menu {
                    Button("Move to Top") { runBulkAction { try await store.command(.topPrio, hashes: $0) } }
                    Button("Move Up") { runBulkAction { try await store.command(.increasePrio, hashes: $0) } }
                    Button("Move Down") { runBulkAction { try await store.command(.decreasePrio, hashes: $0) } }
                    Button("Move to Bottom") { runBulkAction { try await store.command(.bottomPrio, hashes: $0) } }
                } label: {
                    toolbarLabel("Queue", image: "arrow.up.arrow.down")
                }
                .disabled(selectedTorrent == nil)

                Button { showsTorrentCreator = true } label: {
                    toolbarLabel("Create Torrent", image: "doc.badge.plus")
                }
                .disabled(!store.usesBundledBackend)
                .help("Create a .torrent file")

                Menu {
                    Button("Pause Session") { setSessionPaused(true) }
                    Button("Resume Session") { setSessionPaused(false) }
                    Divider()
                    Button("Speed Limits…") { showsSpeedLimits = true }
                    Button("Toggle Alternative Speed Limits") { toggleSpeedLimitsMode() }
                    Menu("When Downloads Complete") {
                        completionActionButton("none", title: "Do Nothing")
                        completionActionButton("quit", title: "Quit qBitX")
                        completionActionButton("sleep", title: "Sleep System")
                        Button("Hibernate System (unavailable on macOS)") {}
                            .disabled(true)
                        completionActionButton("restart", title: "Restart System")
                        completionActionButton("shutdown", title: "Shut Down System")
                    }
                } label: {
                    toolbarLabel("Session", image: "pause.circle")
                }

                Button {
                    if let selectedTorrent { openDestinationFolder(for: selectedTorrent) }
                } label: {
                    toolbarLabel("Open Destination", image: "folder")
                }
                .disabled(selectedTorrent?.savePath.isEmpty ?? true)

                viewToolbarMenu
                settingsToolbarMenu
                helpToolbarMenu
        }
    }

    private func toolbarLabel(_ title: String, image: String) -> some View {
        Label(LocalizedStringKey(title), systemImage: image).labelStyle(ToolbarLabelStyle(style: toolbarStyle))
    }

    private var lockedOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill").font(.system(size: 34))
            Text("qBitX is Locked").font(.title2.weight(.semibold))
            Text("Authenticate with your Mac account to return to the transfer list.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Unlock qBitX") { unlockInterface() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .contentShape(Rectangle())
    }

    private var startupSplash: some View {
        ZStack {
            Color.black.opacity(0.12)
            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                Text("qBitX")
                    .font(.title2.weight(.semibold))
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Starting qBitX")
            }
            .padding(28)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func unlockInterface() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authenticationError = error?.localizedDescription ?? "Mac account authentication is unavailable."
            return
        }
        Task { @MainActor in
            do {
                let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock qBitX")
                interfaceLocked = !success
            } catch { authenticationError = error.localizedDescription }
        }
    }

    private func syncWindowTitle() {
        let base = "qBitX"
        let speed = showSpeedInTitleBar ? " · ↓ \(store.transferStatus.downloadText) · ↑ \(store.transferStatus.uploadText)" : ""
        NSApp.keyWindow?.title = base + speed
    }

    private func openURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    private func handleOpenURL(_ url: URL) {
        guard (url.isFileURL && url.pathExtension.lowercased() == "torrent")
            || url.scheme?.lowercased() == "magnet" else {
            actionError = "qBitX can open .torrent files and magnet links."
            return
        }
        pendingExternalURLs.append(url)
        presentNextExternalURLIfReady()
    }

    private func queueExternalTorrentFiles(_ urls: [URL]) {
        var importedFiles: [PendingTorrentFile] = []
        var failures: [String] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                importedFiles.append(PendingTorrentFile(name: url.lastPathComponent, data: try Data(contentsOf: url), sourceURL: url))
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        pendingExternalFiles.append(contentsOf: importedFiles)
        if !failures.isEmpty {
            pendingFileImportError = failures.joined(separator: "\n")
        }
        presentNextExternalURLIfReady()
    }

    private func presentNextExternalURLIfReady() {
        guard store.isConnected, pendingTorrentFile == nil, !showsURLSheet, !isAddingExternalTorrent else { return }
        if !pendingExternalFiles.isEmpty {
            let file = pendingExternalFiles.removeFirst()
            if showTorrentAdditionDialog {
                pendingTorrentFile = file
            } else {
                addExternalTorrent(file: file)
            }
            return
        }
        while !pendingExternalURLs.isEmpty {
            let url = pendingExternalURLs.removeFirst()
            if url.isFileURL {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let file = PendingTorrentFile(name: url.lastPathComponent, data: try Data(contentsOf: url), sourceURL: url)
                    if showTorrentAdditionDialog {
                        pendingTorrentFile = file
                    } else {
                        addExternalTorrent(file: file)
                    }
                    return
                } catch {
                    actionError = error.localizedDescription
                    continue
                }
            }

            if showTorrentAdditionDialog {
                incomingTorrentURL = url.absoluteString
                showsURLSheet = true
            } else {
                addExternalTorrent(url: url.absoluteString)
            }
            return
        }
        if let error = pendingFileImportError {
            pendingFileImportError = nil
            actionError = error
        }
    }

    private func defaultTorrentAddOptions() async throws -> TorrentAddOptions {
        var options = try await store.defaultTorrentAddOptions()
        if options.category.isEmpty {
            options.category = UserDefaults.standard.string(forKey: "qBitX.addTorrentDefaultCategory") ?? ""
        }
        return options
    }

    private func addExternalTorrent(file: PendingTorrentFile) {
        guard !isAddingExternalTorrent else { return }
        isAddingExternalTorrent = true
        Task {
            do {
                let options = try await defaultTorrentAddOptions()
                let addedTorrentID = try await store.add(
                    file: file.data,
                    filename: file.name,
                    options: options,
                    verifyNewTorrent: autoDeleteTorrentFileMode > 0
                )
                if addedTorrentID != nil && autoDeleteTorrentFileMode > 0 {
                    try removeLocalTorrentSource(file)
                }
            } catch { actionError = error.localizedDescription }
            isAddingExternalTorrent = false
            presentNextExternalURLIfReady()
        }
    }

    private func addExternalTorrent(url: String) {
        guard !isAddingExternalTorrent else { return }
        isAddingExternalTorrent = true
        Task {
            do {
                let options = try await defaultTorrentAddOptions()
                try await store.add(url: url, options: options)
            } catch { actionError = error.localizedDescription }
            isAddingExternalTorrent = false
            presentNextExternalURLIfReady()
        }
    }

    private func pasteTorrentLinks() {
        guard let clipboard = NSPasteboard.general.string(forType: .string) else { return }
        let links = clipboard.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && (isTorrentLink($0) || localTorrentURL($0) != nil) }
        guard !links.isEmpty else { return }
        pendingExternalURLs.append(contentsOf: links.compactMap { localTorrentURL($0) ?? URL(string: $0) })
        presentNextExternalURLIfReady()
    }

    private func localTorrentURL(_ value: String) -> URL? {
        let url = value.lowercased().hasPrefix("file:") ? URL(string: value) : URL(fileURLWithPath: value)
        guard let url, url.isFileURL, url.pathExtension.lowercased() == "torrent",
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func isTorrentLink(_ value: String) -> Bool {
        if value.lowercased().hasPrefix("magnet:") { return true }
        guard let scheme = URLComponents(string: value)?.scheme?.lowercased() else { return false }
        return ["http", "https", "ftp"].contains(scheme)
    }

    private var viewToolbarMenu: some View {
        Menu {
            Toggle("Show Filter Sidebar", isOn: $showFiltersSidebar)
            Toggle("Show Detail Pane", isOn: $showDetailPane)
            Toggle("Show Status Bar", isOn: $showStatusBar)
            Toggle("Show Toolbar", isOn: $showToolbar)
            Toggle("Show Speed in Window Title", isOn: $showSpeedInTitleBar)
            Toggle("Show Tracker Status Filters", isOn: $showTrackerStatusFilter)
            Toggle("Separate Tracker Status Filters", isOn: $separateTrackerStatusFilter)
            Toggle("Hide Empty Status Filters", isOn: $hideZeroStatusFilters)
            Menu("Toolbar Style") {
                toolbarStyleButton("system", title: "Follow System Style")
                toolbarStyleButton("icons", title: "Icons Only")
                toolbarStyleButton("text", title: "Text Only")
                toolbarStyleButton("beside", title: "Text Alongside Icons")
                toolbarStyleButton("below", title: "Text Under Icons")
            }
            Divider()
            Toggle("Show Speed in Menu Bar", isOn: $showSpeedInMenuBar)
            Toggle("Show Speed in Dock", isOn: $showSpeedInDock)
            Divider()
            Button("Execution Log…") { showsExecutionLog = true }
            Button("Statistics…") { showsStatistics = true }
        } label: { toolbarLabel("View", image: "rectangle.split.3x1") }
    }

    @ViewBuilder private func toolbarStyleButton(_ style: String, title: String) -> some View {
        Button {
            toolbarStyle = style
        } label: {
            if toolbarStyle == style { Label(title, systemImage: "checkmark") }
            else { Text(LocalizedStringKey(title)) }
        }
    }

    private var settingsToolbarMenu: some View {
        Menu {
            Button("qBitX Preferences…") { showsAppPreferences = true }
            Button("qBittorrent Server Preferences…") { showsBackendPreferences = true }
            Button("File Associations…") { showsFileAssociations = true }
            Button("Categories and Tags…") { openOrganization() }
            Button("Connection…") { showsConnectionSettings = true }
            Divider()
            Button("Create Torrent…") { showsTorrentCreator = true }.disabled(!store.usesBundledBackend)
            Button("Cookies…") { showsCookies = true }
            Button("Statistics…") { showsStatistics = true }
            Button("Execution Log…") { showsExecutionLog = true }
            Menu("Power Management") {
                Toggle("Keep This Mac Awake While Downloading", isOn: $preventSleepWhenDownloading)
                Toggle("Keep This Mac Awake While Seeding", isOn: $preventSleepWhenSeeding)
            }
            Divider()
            Button(interfaceLocked ? "Unlock Interface…" : "Lock Interface") {
                if interfaceLocked { unlockInterface() }
                else { interfaceLocked = true }
            }
        } label: { toolbarLabel("Settings", image: "gearshape") }
            .help("qBittorrent preferences and connection")
    }

    private var helpToolbarMenu: some View {
        Menu {
            Button("qBittorrent Documentation") { openURL("https://www.qbittorrent.org/documentation") }
            Button("Check for Updates…") { Task { await programUpdateChecker.check(manual: true) } }
            Button("Donate to qBittorrent") { openURL("https://www.qbittorrent.org/donate") }
            Divider()
            Button("About qBitX…") { showsAbout = true }
        } label: { toolbarLabel("Help", image: "questionmark.circle") }
    }

    private var filterSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sidebarSection("STATUS") {
                    ForEach(TorrentFilter.allCases) { item in
                        let count = torrents.filter(item.includes).count
                        if !hideZeroStatusFilters || count > 0 || item == .all {
                        sidebarRow(item.rawValue, symbol: item.symbol, count: count, selected: isSelected(item)) {
                            statusFilter = item
                            trackerStatusFilter = nil
                            categoryFilter = nil
                            tagFilter = nil
                            trackerFilter = nil
                        }
                        .contextMenu { torrentFilterActions(hashes: torrents.filter(item.includes).map(\.id)) }
                        }
                    }
                }
                if showTrackerStatusFilter && separateTrackerStatusFilter {
                    sidebarSection("TRACKER STATUS") {
                        ForEach(TrackerStatusFilter.allCases) { item in
                            let count = torrents.filter(item.includes).count
                            if !hideZeroStatusFilters || count > 0 || item == .all {
                                sidebarRow(item.rawValue, symbol: item.symbol, count: count, selected: isSelected(item)) {
                                    selectTrackerStatus(item)
                                }
                                .contextMenu { torrentFilterActions(hashes: torrents.filter(item.includes).map(\.id)) }
                            }
                        }
                    }
                }
                sidebarSection("CATEGORIES") {
                    ForEach(allFilterCategories, id: \.self) { category in
                        sidebarRow(category.isEmpty ? "Uncategorized" : category.split(separator: "/").last.map(String.init) ?? category,
                                   symbol: "folder", count: torrents.filter { $0.category == category || $0.category.hasPrefix(category + "/") }.count,
                                   selected: categoryFilter == category, indent: CGFloat(category.filter { $0 == "/" }.count) * 12) {
                            categoryFilter = category
                            statusFilter = .all
                            trackerStatusFilter = nil
                            tagFilter = nil
                            trackerFilter = nil
                        }
                        .contextMenu {
                            Button("New Category…") { openOrganization() }
                            Button("New Subcategory…") { openOrganization(initialCategory: category.isEmpty ? nil : category + "/") }
                            Button("Manage Categories and Tags…") { openOrganization() }
                            Button("Remove Unused Categories", role: .destructive) { Task { await removeUnusedCategories() } }
                            Divider()
                            torrentFilterActions(hashes: torrents.filter { $0.category == category || $0.category.hasPrefix(category + "/") }.map(\.id))
                        }
                    }
                }
                sidebarSection("TAGS") {
                    sidebarRow("All", symbol: "tag", count: torrents.count, selected: tagFilter == nil && categoryFilter == nil && trackerFilter == nil && trackerStatusFilter == nil && statusFilter == .all) {
                        categoryFilter = nil
                        statusFilter = .all
                        trackerStatusFilter = nil
                        tagFilter = nil
                        trackerFilter = nil
                    }
                    ForEach(allFilterTags, id: \.self) { tag in
                        sidebarRow(tag, symbol: "tag", count: torrents.filter { $0.tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(tag) }.count, selected: tagFilter == tag) {
                            tagFilter = tag
                            statusFilter = .all
                            trackerStatusFilter = nil
                            categoryFilter = nil
                            trackerFilter = nil
                        }
                        .contextMenu {
                            Button("Categories and Tags…") { openOrganization() }
                            Button("Remove Unused Tags", role: .destructive) { Task { await removeUnusedTags() } }
                            Divider()
                            torrentFilterActions(hashes: torrents.filter { $0.tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(tag) }.map(\.id))
                        }
                    }
                }
                sidebarSection("TRACKERS") {
                    sidebarRow("All Trackers", symbol: "network", count: torrents.count, selected: trackerFilter == nil && trackerStatusFilter == nil && categoryFilter == nil && tagFilter == nil && statusFilter == .all) {
                        trackerFilter = nil
                        trackerStatusFilter = nil
                        statusFilter = .all
                        categoryFilter = nil
                        tagFilter = nil
                    }
                    .contextMenu { torrentFilterActions(hashes: torrents.map(\.id)) }
                    sidebarRow("Trackerless", symbol: "network.slash", count: torrents.filter { $0.trackerHosts.isEmpty }.count, selected: trackerFilter == "" && trackerStatusFilter == nil) {
                        trackerFilter = ""
                        trackerStatusFilter = nil
                        statusFilter = .all
                        categoryFilter = nil
                        tagFilter = nil
                    }
                    .contextMenu { torrentFilterActions(hashes: torrents.filter { $0.trackerHosts.isEmpty }.map(\.id)) }
                    if showTrackerStatusFilter && !separateTrackerStatusFilter {
                        ForEach(TrackerStatusFilter.allCases.filter { $0 != .all }) { item in
                            let count = torrents.filter(item.includes).count
                            if !hideZeroStatusFilters || count > 0 {
                                sidebarRow(item.rawValue, symbol: item.symbol, count: count, selected: isSelected(item)) {
                                    selectTrackerStatus(item)
                                }
                                .contextMenu { torrentFilterActions(hashes: torrents.filter(item.includes).map(\.id)) }
                            }
                        }
                    }
                    ForEach(allFilterTrackerHosts, id: \.self) { trackerHost in
                        sidebarRow(trackerHost, symbol: "network", count: torrents.filter { $0.trackerHosts.contains(trackerHost) }.count, selected: trackerFilter == trackerHost && trackerStatusFilter == nil) {
                            trackerFilter = trackerHost
                            trackerStatusFilter = nil
                            statusFilter = .all
                            categoryFilter = nil
                            tagFilter = nil
                        }
                        .contextMenu {
                            Button("Remove Tracker from All Torrents", role: .destructive) {
                                requestTrackerHostRemoval(trackerHost)
                            }
                            Divider()
                            torrentFilterActions(hashes: torrents.filter { $0.trackerHosts.contains(trackerHost) }.map(\.id))
                        }
                    }
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 7) {
                Circle().fill(store.isConnected ? .green : .orange).frame(width: 7, height: 7)
                Text(store.isConnected ? "\(store.connectionName) · qB \(store.serverVersion) · API \(store.serverAPIVersion)" : "Disconnected")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .help(store.isConnected ? "\(store.connectionName) · qBittorrent \(store.serverVersion) · Web API \(store.serverAPIVersion)" : "Disconnected")
                if let compatibilityMessage = store.webAPICompatibilityMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(compatibilityMessage)
                        .accessibilityLabel("Web API compatibility warning")
                        .accessibilityHint(compatibilityMessage)
                }
                Spacer()
            }
            .padding(14)
        }
    }

    private func selectTrackerStatus(_ filter: TrackerStatusFilter) {
        trackerStatusFilter = filter == .all ? nil : filter
        statusFilter = .all
        categoryFilter = nil
        tagFilter = nil
        trackerFilter = nil
    }

    private func openOrganization(initialCategory: String? = nil) {
        organizationInitialCategory = initialCategory
        showsOrganization = true
    }

    private func torrentFilterActions(hashes: [String]) -> some View {
        Group {
            Button("Start Torrents") {
                runBulkAction(hashes: hashes) { try await store.command(.start, hashes: $0) }
            }
            .disabled(hashes.isEmpty)
            Button("Force Start Torrents") {
                runBulkAction(hashes: hashes) { try await store.setForceStart(true, hashes: $0) }
            }
            .disabled(hashes.isEmpty)
            Button("Stop Torrents") {
                runBulkAction(hashes: hashes) { try await store.command(.stop, hashes: $0) }
            }
            .disabled(hashes.isEmpty)
            Button("Remove Torrents…", role: .destructive) {
                requestRemoval(hashes: hashes)
            }
            .disabled(hashes.isEmpty)
        }
    }

    private func loadFilterCatalogs() async {
        guard store.isConnected else { return }
        do {
            let data = try await store.categoriesData()
            if let values = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                categoryCatalog = Set(values.keys)
            }
        } catch { categoryCatalog = [] }
        do {
            let data = try await store.tagsData()
            tagCatalog = Set((try JSONSerialization.jsonObject(with: data) as? [String]) ?? [])
        } catch { tagCatalog = [] }
    }

    private func removeUnusedCategories() async {
        let unused = categoryCatalog.filter { category in
            !torrents.contains { $0.category == category || $0.category.hasPrefix(category + "/") }
        }.sorted()
        do {
            for category in unused { try await store.removeCategory(category) }
            await loadFilterCatalogs()
        } catch { actionError = error.localizedDescription }
    }

    private func removeUnusedTags() async {
        let assigned = Set(torrents.flatMap { $0.tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } })
        let unused = tagCatalog.subtracting(assigned)
        do {
            for tag in unused.sorted() { try await store.removeTag(tag) }
            await loadFilterCatalogs()
        } catch { actionError = error.localizedDescription }
    }

    private func sidebarSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 18)
                .padding(.bottom, 4)
            content()
        }
    }

    private func sidebarRow(_ title: String, symbol: String, count: Int, selected: Bool, indent: CGFloat = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).frame(width: 17)
                Text(title).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(.leading, 10 + indent)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(selected ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private var mainTabs: some View {
        HStack(spacing: 6) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(MainTab.allCases) { tab in
                        Button { mainTab = tab } label: {
                            Group {
                                if tab == .transfers {
                                    HStack(spacing: 0) {
                                        Text("Transfers")
                                        Text(" (\(torrents.count))")
                                    }
                                } else {
                                    Text(LocalizedStringKey(tab.rawValue))
                                }
                            }
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .glassEffect(mainTab == tab ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer()
            if mainTab == .transfers {
                TextField("Filter torrents…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .focused($torrentFilterFocused)
                Menu {
                    ForEach(TorrentSort.allCases) { field in
                        Button(LocalizedStringKey(field.title)) { sortField = field }
                    }
                    Divider()
                    Toggle("Descending", isOn: $sortDescending)
                } label: {
                    HStack(spacing: 4) {
                        Text("Sort:")
                        Text(LocalizedStringKey(sortField.title))
                    }
                }
                .font(.caption)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var torrentTable: some View {
        Table(visibleTorrents, selection: $selectedTorrentIDs, columnCustomization: $columnCustomization) {
            primaryColumns
            extraColumnsOne
            extraColumnsTwo
            extraColumnsThree
        }
        .contextMenu(forSelectionType: String.self) { target in
            torrentContextMenu(for: target)
        }
        .alternatingRowBackgrounds(alternatingTransferRows ? .enabled : .disabled)
        .overlay {
            if !store.isConnected {
                VStack(spacing: 12) {
                    if let error = store.connectionError {
                        ContentUnavailableView("Backend Unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
                        Button("Try Again") { retryID += 1 }
                            .buttonStyle(.glass)
                        Button("Connection Settings") { showsConnectionSettings = true }
                    } else {
                        ProgressView("Starting qBittorrent…")
                    }
                }
            } else if visibleTorrents.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView("No Torrents", systemImage: "square.stack", description: Text("There are no torrents in this section."))
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    @TableColumnBuilder<Torrent, Never>
    private var primaryColumns: some TableColumnContent<Torrent, Never> {
        TableColumn("Name") { torrent in
            stateColored(Label(torrent.name, systemImage: torrent.state.symbol), for: torrent)
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { handleTorrentDoubleClick(torrent) }
        }
        .width(min: 200, ideal: 270).customizationID("name")
        TableColumn("Size") { torrent in
            stateColored(Text(displayValue(torrent.size, numericValue: Double(torrent.sizeBytes), key: "size", torrent: torrent)), for: torrent)
        }.width(80).customizationID("size")
        TableColumn("Progress") { torrent in
            stateColored(HStack(spacing: 6) {
                ProgressView(value: torrent.progress)
                    .tint(colorTransfersByState && progressBarFollowsStateColor ? stateColor(for: torrent) : (themeColor(for: "ProgressBar") ?? Color.accentColor))
                Text(torrent.progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.monospacedDigit())
                    .frame(width: 32, alignment: .trailing)
            }, for: torrent)
        }
        .width(min: 110, ideal: 140).customizationID("progress")
        TableColumn("Status") { torrent in stateColored(Text(torrent.state.rawValue), for: torrent) }.width(95).customizationID("status")
        TableColumn("Seeds") { torrent in
            let count = torrent.seeds == 0 && (torrent.totalSeeds ?? 0) <= 0 ? 0 : 1
            stateColored(Text(displayValue(torrent.seedCountText, numericValue: Double(count), key: "seeds", torrent: torrent)), for: torrent)
        }.width(min: 70, ideal: 86).customizationID("seeds")
        TableColumn("Peers") { torrent in
            let count = torrent.peers == 0 && (torrent.totalPeers ?? 0) <= 0 ? 0 : 1
            stateColored(Text(displayValue(torrent.peerCountText, numericValue: Double(count), key: "peers", torrent: torrent)), for: torrent)
        }.width(min: 70, ideal: 86).customizationID("peers")
        TableColumn("Down Speed") { stateColored(Text($0.downloadRate), for: $0) }.width(90).customizationID("down_speed")
        TableColumn("Up Speed") { stateColored(Text($0.uploadRate), for: $0) }.width(90).customizationID("up_speed")
        TableColumn("ETA") { stateColored(Text($0.eta), for: $0) }.width(70).customizationID("eta")
    }

    @TableColumnBuilder<Torrent, Never>
    private var extraColumnsOne: some TableColumnContent<Torrent, Never> {
        TableColumn("Queue") { stateColored(Text($0.column("priority")), for: $0) }.width(60).customizationID("queue").defaultVisibility(.hidden)
        TableColumn("Total Size") { stateColored(Text(displayColumn("total_size", torrent: $0)), for: $0) }.width(90).customizationID("total_size").defaultVisibility(.hidden)
        TableColumn("Ratio") { stateColored(Text(displayColumn("ratio", torrent: $0)), for: $0) }.width(70).customizationID("ratio").defaultVisibility(.hidden)
        TableColumn("Popularity") { stateColored(Text(displayColumn("popularity", torrent: $0)), for: $0) }.width(80).customizationID("popularity").defaultVisibility(.hidden)
        TableColumn("Category") { stateColored(Text($0.column("category")), for: $0) }.width(100).customizationID("category").defaultVisibility(.hidden)
        TableColumn("Tags") { stateColored(Text($0.column("tags")), for: $0) }.width(100).customizationID("tags").defaultVisibility(.hidden)
        TableColumn("Added On") { stateColored(Text($0.column("added_on")), for: $0) }.width(150).customizationID("added_on").defaultVisibility(.hidden)
        TableColumn("Seeding Since") { stateColored(Text($0.column("completion_on")), for: $0) }.width(150).customizationID("completion_on").defaultVisibility(.hidden)
        TableColumn("Tracker") { stateColored(Text($0.column("tracker")), for: $0) }.width(160).customizationID("tracker").defaultVisibility(.hidden)
        TableColumn("Down Limit") { stateColored(Text(displayColumn("dl_limit", torrent: $0)), for: $0) }.width(90).customizationID("dl_limit").defaultVisibility(.hidden)
    }

    @TableColumnBuilder<Torrent, Never>
    private var extraColumnsTwo: some TableColumnContent<Torrent, Never> {
        TableColumn("Up Limit") { stateColored(Text(displayColumn("up_limit", torrent: $0)), for: $0) }.width(90).customizationID("up_limit").defaultVisibility(.hidden)
        TableColumn("Downloaded") { stateColored(Text(displayColumn("downloaded", torrent: $0)), for: $0) }.width(90).customizationID("downloaded").defaultVisibility(.hidden)
        TableColumn("Uploaded") { stateColored(Text(displayColumn("uploaded", torrent: $0)), for: $0) }.width(90).customizationID("uploaded").defaultVisibility(.hidden)
        TableColumn("Session Downloaded") { stateColored(Text(displayColumn("downloaded_session", torrent: $0)), for: $0) }.width(110).customizationID("downloaded_session").defaultVisibility(.hidden)
        TableColumn("Session Uploaded") { stateColored(Text(displayColumn("uploaded_session", torrent: $0)), for: $0) }.width(110).customizationID("uploaded_session").defaultVisibility(.hidden)
        TableColumn("Amount Left") { stateColored(Text(displayColumn("amount_left", torrent: $0)), for: $0) }.width(90).customizationID("amount_left").defaultVisibility(.hidden)
        TableColumn("Active Time") { stateColored(Text(displayColumn("time_active", torrent: $0)), for: $0) }.width(90).customizationID("time_active").defaultVisibility(.hidden)
        TableColumn("Save Path") { stateColored(Text($0.column("save_path")), for: $0) }.width(220).customizationID("save_path").defaultVisibility(.hidden)
        TableColumn("Completed") { stateColored(Text(displayColumn("completed", torrent: $0)), for: $0) }.width(90).customizationID("completed").defaultVisibility(.hidden)
        TableColumn("Ratio Limit") { stateColored(Text(displayColumn("ratio_limit", torrent: $0)), for: $0) }.width(80).customizationID("ratio_limit").defaultVisibility(.hidden)
    }

    @TableColumnBuilder<Torrent, Never>
    private var extraColumnsThree: some TableColumnContent<Torrent, Never> {
        TableColumn("Last Seen Complete") { stateColored(Text($0.column("seen_complete")), for: $0) }.width(150).customizationID("seen_complete").defaultVisibility(.hidden)
        TableColumn("Last Activity") { stateColored(Text($0.column("last_activity")), for: $0) }.width(150).customizationID("last_activity").defaultVisibility(.hidden)
        TableColumn("Availability") { stateColored(Text(displayColumn("availability", torrent: $0)), for: $0) }.width(80).customizationID("availability").defaultVisibility(.hidden)
        TableColumn("Download Path") { stateColored(Text($0.column("download_path")), for: $0) }.width(220).customizationID("download_path").defaultVisibility(.hidden)
        TableColumn("Infohash v1") { stateColored(Text($0.column("infohash_v1")), for: $0) }.width(260).customizationID("infohash_v1").defaultVisibility(.hidden)
        TableColumn("Infohash v2") { stateColored(Text($0.column("infohash_v2")), for: $0) }.width(260).customizationID("infohash_v2").defaultVisibility(.hidden)
        TableColumn("Reannounce") { stateColored(Text(displayColumn("reannounce", torrent: $0)), for: $0) }.width(90).customizationID("reannounce").defaultVisibility(.hidden)
        TableColumn("Private") { stateColored(Text(displayColumn("private", torrent: $0)), for: $0) }.width(70).customizationID("private").defaultVisibility(.hidden)
        TableColumn("Created On") { stateColored(Text($0.column("creation_date")), for: $0) }.width(150).customizationID("creation_date").defaultVisibility(.hidden)
    }

    private var detailsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            GlassEffectContainer(spacing: 5) {
                HStack(spacing: 5) {
                    ForEach(DetailTab.allCases) { tab in
                        Button { detailTab = tab } label: {
                            Text(LocalizedStringKey(tab.rawValue))
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .glassEffect(detailTab == tab ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            Divider()
            Group {
                if let torrent = selectedTorrent {
                    if detailTab == .general {
                        generalDetails(for: torrent)
                    } else if detailTab == .trackers {
                        trackerDetails
                    } else if detailTab == .content {
                        fileDetails
                    } else if detailTab == .peers {
                        peerDetails
                    } else if detailTab == .httpSources {
                        webSeedDetails
                    } else if detailTab == .speed {
                        speedDetails
                    } else {
                        ContentUnavailableView(detailTab.rawValue, systemImage: "square.stack", description: Text("This detail view is not yet available."))
                    }
                } else {
                    ContentUnavailableView("No Torrent Selected", systemImage: "square.stack", description: Text("Select a torrent to view its details."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func generalDetails(for torrent: Torrent) -> some View {
        ScrollView([.horizontal, .vertical]) {
        VStack(alignment: .leading, spacing: 12) {
        if !pieceStates.isEmpty || !pieceAvailability.isEmpty {
            TorrentPieceBars(
                states: pieceStates,
                availability: pieceAvailability,
                pieceColor: themeColor(for: "PiecesBar.Piece"),
                partialPieceColor: themeColor(for: "PiecesBar.PartialPiece"),
                missingPieceColor: themeColor(for: "PiecesBar.MissingPiece"),
                borderColor: themeColor(for: "PiecesBar.Border")
            )
                .padding(.horizontal, 18)
                .padding(.top, 12)
        }
        HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 11) {
                detailLine("Name", torrent.name)
                detailLine("Status", torrent.state.rawValue)
                detailLine("Progress", (properties?.progress ?? torrent.progress).formatted(.percent.precision(.fractionLength(1))))
                if let properties {
                    detailLine("Availability", properties.availability.map { String(format: "%.3f", $0) } ?? "—")
                    detailLine("Pieces", piecesText(properties))
                    detailLine("Info Hash v1", display(properties.infohash_v1))
                    detailLine("Info Hash v2", display(properties.infohash_v2))
                }
                detailLine("Size", torrent.size)
                if let savePath = properties?.save_path {
                    detailLine("Save path", savePath)
                }
                if let downloadPath = properties?.download_path {
                    detailLine("Download path", downloadPath)
                }
                detailLine("Torrent ID", torrent.id)
                if let properties {
                    detailLine("Private", properties.is_private == true ? "Yes" : "No")
                    if let creator = properties.created_by, !creator.isEmpty { detailLine("Created by", creator) }
                    if let comment = properties.comment, !comment.isEmpty { detailLine("Comment", comment) }
                }
            }
            VStack(alignment: .leading, spacing: 11) {
                detailLine("Download speed", torrent.downloadRate)
                if let speed = properties?.dl_speed_avg { detailLine("Average download speed", rateText(speed)) }
                detailLine("Upload speed", torrent.uploadRate)
                if let properties {
                    if let speed = properties.up_speed_avg { detailLine("Average upload speed", rateText(speed)) }
                    detailLine("Peers", countWithTotal(properties.peers, total: properties.peers_total))
                    detailLine("Seeds", countWithTotal(properties.seeds, total: properties.seeds_total))
                    detailLine("Connections", countWithLimit(properties.nb_connections, limit: properties.nb_connections_limit))
                    detailLine("Time remaining", properties.eta.map(durationText) ?? torrent.eta)
                    detailLine("Download limit", limitText(properties.dl_limit))
                    detailLine("Upload limit", limitText(properties.up_limit))
                    detailLine("Downloaded", bytesText(properties.total_downloaded))
                    detailLine("Downloaded this session", bytesText(properties.total_downloaded_session))
                    detailLine("Uploaded", bytesText(properties.total_uploaded))
                    detailLine("Uploaded this session", bytesText(properties.total_uploaded_session))
                    detailLine("Wasted", bytesText(properties.total_wasted))
                    detailLine("Share ratio", ratioText(properties.share_ratio ?? torrent.ratio))
                    detailLine("Popularity", ratioText(properties.popularity))
                }
            }
            VStack(alignment: .leading, spacing: 11) {
                if let properties {
                    detailLine("Total size", bytesText(properties.total_size))
                    detailLine("Reannounce in", properties.reannounce.map(durationText) ?? "—")
                    detailLine("Added", dateText(properties.addition_date))
                    detailLine("Completed", dateText(properties.completion_date))
                    detailLine("Created", dateText(properties.creation_date))
                    detailLine("Last seen", dateText(properties.last_seen))
                    detailLine("Active time", durationText(properties.time_elapsed))
                    detailLine("Seeding time", durationText(properties.seeding_time))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        }
    }

    private func bytesText(_ bytes: Int64?) -> String {
        guard let bytes, bytes >= 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func rateText(_ bytesPerSecond: Int64) -> String {
        guard bytesPerSecond >= 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytesPerSecond, countStyle: .binary) + "/s"
    }

    private func limitText(_ bytesPerSecond: Int64?) -> String {
        guard let bytesPerSecond else { return "—" }
        return bytesPerSecond <= 0 ? "∞" : rateText(bytesPerSecond)
    }

    private func ratioText(_ ratio: Double?) -> String {
        guard let ratio, ratio.isFinite else { return "—" }
        return ratio < 0 ? "∞" : ratio.formatted(.number.precision(.fractionLength(2)))
    }

    private func display(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "—" }
        return value
    }

    private func countWithTotal(_ count: Int?, total: Int?) -> String {
        guard let count else { return "—" }
        guard let total, total >= 0 else { return "\(count)" }
        return "\(count) (\(total) total)"
    }

    private func countWithLimit(_ count: Int?, limit: Int?) -> String {
        guard let count else { return "—" }
        guard let limit, limit >= 0 else { return "\(count)" }
        return "\(count) (\(limit) max)"
    }

    private func piecesText(_ properties: TorrentProperties) -> String {
        guard let count = properties.pieces_num, let pieceSize = properties.piece_size else { return "—" }
        let have = properties.pieces_have.map(String.init) ?? "—"
        return "\(have) of \(count) × \(ByteCountFormatter.string(fromByteCount: pieceSize, countStyle: .file))"
    }

    private func dateText(_ timestamp: Int64?) -> String {
        guard let timestamp, timestamp > 0 else { return "—" }
        return Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(date: .abbreviated, time: .shortened)
    }

    private func durationText(_ seconds: Int64?) -> String {
        guard let seconds, seconds >= 0 else { return "—" }
        return Duration.seconds(seconds).formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated))
    }

    private func detailLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("\(title):")
                .foregroundStyle(.secondary)
                .frame(width: 106, alignment: .trailing)
            Text(value).lineLimit(1)
        }
        .font(.caption)
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            Label(store.isConnected ? "Connected" : "Disconnected", systemImage: "circle.fill")
                .foregroundStyle(store.isConnected ? .green : .orange)
            Spacer(minLength: 0)
            Text("\(torrents.count) torrents")
            Text("DHT: \(store.transferStatus.dhtNodes)")
            if showFreeDiskSpace {
                let freeSpace = store.serverStatistics?.free_space_on_disk.flatMap { bytes in
                    bytes >= 0 ? ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : nil
                } ?? "N/A"
                Text("Free space: \(freeSpace)")
            }
            if showExternalIP {
                Text(externalAddressText)
                    .textSelection(.enabled)
            }
            Label(store.transferStatus.downloadText, systemImage: "arrow.down")
            Label(store.transferStatus.uploadText, systemImage: "arrow.up")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
    }

    private var externalAddressText: String {
        let addresses = [store.transferStatus.lastExternalAddressV4, store.transferStatus.lastExternalAddressV6]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        guard !addresses.isEmpty else { return "External IP: N/A" }
        return addresses.count > 1 ? "External IPs: \(addresses.joined(separator: ", "))" : "External IP: \(addresses[0])"
    }

    private var trackerDetails: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Trackers").font(.caption.weight(.semibold))
                Spacer()
                Button { moveSelectedTrackers(by: -1) } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(.glass)
                    .disabled(selectedTrackerParents.isEmpty || selectedTrackerParents.allSatisfy { $0.tierSortValue == 0 })
                    .help("Move selected trackers up one tier")
                    .accessibilityLabel("Move selected trackers up one tier")
                Button { moveSelectedTrackers(by: 1) } label: { Image(systemName: "arrow.down") }
                    .buttonStyle(.glass)
                    .disabled(selectedTrackerParents.isEmpty)
                    .help("Move selected trackers down one tier")
                    .accessibilityLabel("Move selected trackers down one tier")
                Button { showDetailInput(.addTracker, title: "Add Tracker", hint: "Tracker URL") } label: { Image(systemName: "plus") }
                    .buttonStyle(.glass)
                    .help("Add tracker")
                    .accessibilityLabel("Add tracker")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            if trackerRows.isEmpty {
                ContentUnavailableView("No Trackers", systemImage: "antenna.radiowaves.left.and.right", description: Text("This torrent has no trackers or peer discovery endpoints."))
            } else {
                Table(trackerRows, children: \.children, selection: $selectedTrackerRowIDs, sortOrder: $trackerSortOrder, columnCustomization: $trackerColumnCustomization) {
                    trackerPrimaryColumns
                    trackerDetailColumns
                }
                .contextMenu(forSelectionType: String.self) { target in
                    trackerContextMenu(for: target)
                }
                .alternatingRowBackgrounds(alternatingTransferRows ? .enabled : .disabled)
                .background {
                    VStack(spacing: 0) {
                        Button("Edit Selected Tracker", action: editSelectedTracker)
                            .keyboardShortcut(KeyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF2FunctionKey)!)), modifiers: []))
                            .hidden()
                        Button("Remove Selected Trackers", action: removeSelectedTrackerRows)
                            .keyboardShortcut(.delete)
                            .hidden()
                        Button("Copy Selected Tracker URLs", action: copySelectedTrackerURLs)
                            .keyboardShortcut("c", modifiers: .command)
                            .hidden()
                    }
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                }
            }
        }
    }

    private var trackerRows: [TrackerTableRow] {
        trackers.map { tracker in
            TrackerTableRow(
                tracker: tracker,
                endpoint: nil,
                children: tracker.endpoints?.map { TrackerTableRow(tracker: tracker, endpoint: $0) }
            )
        }
    }
    private var allTrackerRows: [TrackerTableRow] { trackerRows.flatMap(\.flattened) }
    private var selectedTrackerRows: [TrackerTableRow] { allTrackerRows.filter { selectedTrackerRowIDs.contains($0.id) } }
    private var selectedTrackerParents: [TrackerTableRow] {
        selectedTrackerRows.filter { $0.endpoint == nil && $0.tierSortValue >= 0 }
    }

    private func editSelectedTracker() {
        guard selectedTrackerParents.count == 1, let row = selectedTrackerParents.first else { return }
        showDetailInput(.editTracker(row.tracker.url), title: "Edit Tracker", hint: "Tracker URL", initialValue: row.tracker.url)
    }

    private func moveSelectedTrackers(by offset: Int) {
        moveTrackers(selectedTrackerParents, by: offset)
    }

    private func moveTrackers(_ selected: [TrackerTableRow], by offset: Int) {
        guard !selected.isEmpty else { return }
        Task {
            await performDetailAction { hash in
                for row in selected {
                    let currentTier = row.tierSortValue
                    let tier = max(0, currentTier + offset)
                    guard tier != currentTier else { continue }
                    try await store.moveTracker(hash: hash, url: row.tracker.url, tier: tier)
                }
            }
        }
    }

    private func removeSelectedTrackerRows() {
        let urls = selectedTrackerParents.map { $0.tracker.url }
        guard !urls.isEmpty, let hash = selectedTorrentID else { return }
        Task {
            do {
                try await store.removeTrackers(hashes: [hash], urls: urls)
                await loadDetails()
            } catch { actionError = error.localizedDescription }
        }
    }

    private func copySelectedTrackerURLs() {
        let urls = selectedTrackerRows.map(\.urlSortValue).filter { !$0.isEmpty }
        guard !urls.isEmpty else { return }
        copyToPasteboard(urls.joined(separator: "\n"))
    }

    @TableColumnBuilder<TrackerTableRow, KeyPathComparator<TrackerTableRow>>
    private var trackerPrimaryColumns: some TableColumnContent<TrackerTableRow, KeyPathComparator<TrackerTableRow>> {
        TableColumn("URL/Announce Endpoint", value: \.urlSortValue) { row in
            HStack(spacing: 6) {
                if row.endpoint != nil { Text("↳").foregroundStyle(.tertiary) }
                Text(row.urlSortValue).lineLimit(1).help(row.urlSortValue)
            }
            .onTapGesture(count: 2) {
                guard row.endpoint == nil, row.tierSortValue >= 0 else { return }
                showDetailInput(.editTracker(row.tracker.url), title: "Edit Tracker", hint: "Tracker URL", initialValue: row.tracker.url)
            }
        }
        .width(min: 220, ideal: 320)
        .customizationID("tracker.url")
        TableColumn("Tier", value: \.tierSortValue) { row in
            Text(row.tierSortValue < 0 ? "—" : "\(row.tierSortValue + 1)")
        }
        .width(min: 45, ideal: 60)
        .customizationID("tracker.tier")
        TableColumn("BT Protocol", value: \.protocolSortValue) { row in
            Text(row.protocolSortValue < 0 ? "—" : "v\(row.protocolSortValue)")
        }
        .width(min: 70, ideal: 90)
        .customizationID("tracker.protocol")
        TableColumn("Status", value: \.statusSortValue) { row in
            Text(trackerStatusText(row.statusSortValue, updating: row.isUpdating))
        }
        .width(min: 100, ideal: 135)
        .customizationID("tracker.status")
        TableColumn("Peers", value: \.peersSortValue) { row in Text(countText(row.peersSortValue)) }
            .width(min: 50, ideal: 65).customizationID("tracker.peers")
        TableColumn("Seeds", value: \.seedsSortValue) { row in Text(countText(row.seedsSortValue)) }
            .width(min: 50, ideal: 65).customizationID("tracker.seeds")
        TableColumn("Leeches", value: \.leechesSortValue) { row in Text(countText(row.leechesSortValue)) }
            .width(min: 55, ideal: 70).customizationID("tracker.leeches")
    }

    @TableColumnBuilder<TrackerTableRow, KeyPathComparator<TrackerTableRow>>
    private var trackerDetailColumns: some TableColumnContent<TrackerTableRow, KeyPathComparator<TrackerTableRow>> {
        TableColumn("Times Downloaded", value: \.downloadedSortValue) { row in Text(countText(row.downloadedSortValue)) }
            .width(min: 95, ideal: 125).customizationID("tracker.downloaded")
        TableColumn("Message", value: \.messageSortValue) { row in Text(row.messageSortValue).lineLimit(1).help(row.messageSortValue) }
            .width(min: 160, ideal: 250).customizationID("tracker.message")
        TableColumn("Next Announce", value: \.nextAnnounceSortValue) { row in Text(announceText(row.nextAnnounceSortValue)) }
            .width(min: 90, ideal: 120).customizationID("tracker.nextAnnounce")
        TableColumn("Min Announce", value: \.minAnnounceSortValue) { row in Text(announceText(row.minAnnounceSortValue)) }
            .width(min: 90, ideal: 120).customizationID("tracker.minAnnounce")
    }

    @ViewBuilder
    private func trackerContextMenu(for target: Set<String>) -> some View {
        let rows = allTrackerRows.filter { target.contains($0.id) }
        let selectedTrackers = rows.filter { $0.endpoint == nil && $0.tierSortValue >= 0 }
        let urlsToCopy = rows.map(\.urlSortValue).filter { !$0.isEmpty }
        Button("Add Tracker…") {
            showDetailInput(.addTracker, title: "Add Tracker", hint: "Tracker URL")
        }
        Button("Edit URL…") {
            guard let tracker = selectedTrackers.first else { return }
            showDetailInput(.editTracker(tracker.tracker.url), title: "Edit Tracker", hint: "Tracker URL", initialValue: tracker.tracker.url)
        }
        .disabled(selectedTrackers.count != 1)
        if selectedTrackers.count == 1, let tracker = selectedTrackers.first {
            Menu("Move to Tier") {
                ForEach(availableTrackerTiers, id: \.self) { tier in
                    Button("Tier \(tier + 1)\(tier == (tracker.tracker.tier ?? 0) ? " ✓" : "")") {
                        Task { await performDetailAction { try await store.moveTracker(hash: $0, url: tracker.tracker.url, tier: tier) } }
                    }
                }
            }
        }
        if !selectedTrackers.isEmpty {
            Button("Move Up One Tier") { moveTrackers(selectedTrackers, by: -1) }
                .disabled(selectedTrackers.allSatisfy { $0.tierSortValue == 0 })
            Button("Move Down One Tier") { moveTrackers(selectedTrackers, by: 1) }
        }
        Button(selectedTrackers.count > 1 ? "Remove Trackers" : "Remove Tracker", role: .destructive) {
            guard let hash = selectedTorrentID else { return }
            Task {
                do {
                    try await store.removeTrackers(hashes: [hash], urls: selectedTrackers.map { $0.tracker.url })
                    await loadDetails()
                } catch { actionError = error.localizedDescription }
            }
        }
        .disabled(selectedTrackers.isEmpty)
        Button("Copy URL") { copyToPasteboard(urlsToCopy.joined(separator: "\n")) }
            .disabled(urlsToCopy.isEmpty)
        if !selectedTrackers.isEmpty, selectedTorrent?.state != .paused {
            Button("Force Reannounce to Selected") {
                Task { await performDetailAction { try await store.reannounceTrackers(hash: $0, urls: selectedTrackers.map { $0.tracker.url }) } }
            }
        }
        if selectedTorrent?.state != .paused {
            Button("Force Reannounce to All Trackers") {
                Task { await performDetailAction { try await store.command(.reannounce, hashes: [$0]) } }
            }
        }
    }

    private func countText(_ count: Int?) -> String {
        guard let count, count >= 0 else { return "—" }
        return "\(count)"
    }

    private func trackerStatusText(_ status: Int?, updating: Bool?) -> String {
        if updating == true { return "Updating…" }
        return switch status {
        case 0: "Disabled"
        case 1: "Not contacted yet"
        case 2: "Working"
        case 4: "Not working"
        case 5: "Tracker error"
        case 6: "Unreachable"
        default: "—"
        }
    }

    private func announceText(_ timestamp: Int64?) -> String {
        guard let timestamp, timestamp > 0 else { return "—" }
        return durationText(max(0, timestamp - Int64(Date().timeIntervalSince1970)))
    }

    private var availableTrackerTiers: [Int] {
        Array(0...max(1, trackers.compactMap(\.tier).filter { $0 >= 0 }.max() ?? 0))
    }

    private var fileDetails: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Content").font(.caption.weight(.semibold))
                Spacer()
                Button("Manage Content…") { openContentLayoutEditor(for: selectedTorrent) }
                    .disabled(selectedTorrent == nil || selectedTorrentIDs.count != 1)
                TextField("Filter files…", text: $contentFileFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 210)
                    .accessibilityLabel("Filter torrent files")
                Menu("Pattern Format") {
                    Button { contentFileFilterMode = "plainText" } label: {
                        patternFormatLabel("Plain text", mode: "plainText")
                    }
                    Button { contentFileFilterMode = "wildcards" } label: {
                        patternFormatLabel("Wildcards", mode: "wildcards")
                    }
                    Button { contentFileFilterMode = "regex" } label: {
                        patternFormatLabel("Regular expression", mode: "regex")
                    }
                }
                .help("Choose how the file filter is interpreted")
                Button("Select All", action: selectAllFilteredContentFiles)
                    .disabled(files.isEmpty)
                Button("Select None", action: deselectFilteredContent)
                    .disabled(selectedContentNodeIDs.isDisjoint(with: filteredContentNodeIDs))
                Menu("Priority") {
                    filePriorityActions(for: selectedFileIDs)
                    Divider()
                    Button("By Shown File Order") {
                        let selectedRows = sortedFilteredContentRows.flatMap(\.flattened).filter { selectedContentNodeIDs.contains($0.id) }
                        applyPriorityByShownOrder(to: selectedRows)
                    }
                }
                    .disabled(selectedFileIDs.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            if files.isEmpty {
                ContentUnavailableView("No Files", systemImage: "doc.text", description: Text("File information is unavailable until torrent metadata has loaded."))
            } else {
                Table(filteredContentRows, children: \.children, selection: $selectedContentNodeIDs, sortOrder: $contentSortOrder, columnCustomization: $contentColumnCustomization) {
                    contentFileColumns
                }
                .contextMenu(forSelectionType: String.self) { target in
                    contentFileContextMenu(for: target)
                }
                .alternatingRowBackgrounds(alternatingTransferRows ? .enabled : .disabled)
                .background {
                    VStack(spacing: 0) {
                        Button("Open Selected Content", action: openSelectedContentRow)
                            .keyboardShortcut(.return)
                            .hidden()
                        Button("Rename Selected Content", action: renameSelectedContent)
                            .keyboardShortcut(KeyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF2FunctionKey)!)), modifiers: []))
                            .hidden()
                    }
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                }
            }
        }
    }

    @TableColumnBuilder<TorrentContentRow, KeyPathComparator<TorrentContentRow>>
    private var contentFileColumns: some TableColumnContent<TorrentContentRow, KeyPathComparator<TorrentContentRow>> {
        TableColumn("Name", value: \.name) { row in contentFileNameCell(row) }
            .width(min: 250, ideal: 520).customizationID("content.name")
        TableColumn("Total Size", value: \.sizeSortValue) { row in
            Text(ByteCountFormatter.string(fromByteCount: row.sizeSortValue, countStyle: .file))
        }
        .width(min: 75, ideal: 100)
        .customizationID("content.size")
        TableColumn("Progress", value: \.progressSortValue) { row in
            Text(row.progressSortValue.formatted(.percent.precision(.fractionLength(1))))
        }
        .width(min: 70, ideal: 85)
        .customizationID("content.progress")
        TableColumn("Download Priority", value: \.prioritySortValue) { row in
            Menu {
                filePriorityActions(for: row.fileIDs)
            } label: {
                Text(row.prioritySortValue < 0 ? "Mixed" : filePriorityLabel(row.prioritySortValue))
                    .foregroundStyle(.secondary)
            }
            .disabled(row.fileIDs.isEmpty)
        }
        .width(min: 90, ideal: 110)
        .customizationID("content.priority")
        TableColumn("Remaining", value: \.remainingSortValue) { row in
            Text(ByteCountFormatter.string(fromByteCount: row.remainingSortValue, countStyle: .file))
        }
        .width(min: 75, ideal: 100)
        .customizationID("content.remaining")
        TableColumn("Availability", value: \.availabilitySortValue) { row in
            Text(row.availabilitySortValue >= 0 ? (row.availabilitySortValue * 100).formatted(.number.precision(.fractionLength(1))) + "%" : "N/A")
        }
        .width(min: 75, ideal: 100)
        .customizationID("content.availability")
    }

    @ViewBuilder
    private func contentFileNameCell(_ row: TorrentContentRow) -> some View {
        if row.isDirectory {
            Label(row.name, systemImage: "folder")
                .lineLimit(1)
                .help(row.path)
                .onTapGesture(count: 2) {
                    if let torrent = selectedTorrent { openTorrentContentRow(row, in: torrent) }
                }
        } else if let file = row.file, dragContentFiles,
           store.usesBundledBackend,
           let torrent = selectedTorrent,
           torrentFileExists(file, in: torrent) {
            Text(file.name)
                .lineLimit(1)
                .help(file.name)
                .onTapGesture(count: 2) { openTorrentContentRow(row, in: torrent) }
                .draggable(torrentFileURL(file, in: torrent))
        } else if let file = row.file {
            Text(file.name)
                .lineLimit(1)
                .help(file.name)
                .onTapGesture(count: 2) {
                    if let torrent = selectedTorrent { openTorrentContentRow(row, in: torrent) }
                }
        }
    }

    @ViewBuilder
    private func contentFileContextMenu(for target: Set<String>) -> some View {
        let selected = sortedFilteredContentRows.flatMap(\.flattened).filter { target.contains($0.id) }
        let selectedFileIDs = selected.reduce(into: Set<Int>()) { $0.formUnion($1.fileIDs) }
        if !selected.isEmpty, let torrent = selectedTorrent {
            if selected.count == 1, let row = selected.first {
                if store.usesBundledBackend {
                    Button("Open") { openTorrentContentRow(row, in: torrent) }
                        .disabled(!torrentContentExists(row, in: torrent))
                    Button("Open Containing Folder") { openTorrentContentContainingFolder(row, in: torrent) }
                        .disabled(!torrentContentExists(row, in: torrent))
                }
                Button("Copy Path") { copyToPasteboard(torrentContentPath(row.path, in: torrent)) }
                    .disabled(torrent.savePath.isEmpty)
                if let file = row.file, isPreviewable(file) {
                    Button("Preview File") { openTorrentFile(file, in: torrent) }
                        .disabled(!torrentFileExists(file, in: torrent))
                }
                if let file = row.file {
                    Button("Rename…") {
                        showDetailInput(.renameFile(file.name), title: "Rename File", hint: "File name", initialValue: (file.name as NSString).lastPathComponent)
                    }
                }
            }
            Button("Batch Rename…") { openContentLayoutEditor(for: torrent, fileIDs: selectedFileIDs) }
                .disabled(selectedFileIDs.isEmpty)
            Menu("Priority") {
                filePriorityActions(for: selectedFileIDs)
                Divider()
                Button("By Shown File Order") { applyPriorityByShownOrder(to: selected) }
            }
        }
    }

    private func openSelectedContentRow() {
        let selected = sortedFilteredContentRows.flatMap(\.flattened).filter { selectedContentNodeIDs.contains($0.id) }
        guard selected.count == 1, let row = selected.first, let torrent = selectedTorrent else { return }
        openTorrentContentRow(row, in: torrent)
    }

    private func renameSelectedContent() {
        let selected = sortedFilteredContentRows.flatMap(\.flattened).filter { selectedContentNodeIDs.contains($0.id) }
        guard !selected.isEmpty, let torrent = selectedTorrent else { return }
        let fileIDs = selected.reduce(into: Set<Int>()) { $0.formUnion($1.fileIDs) }
        if selected.count == 1, let file = selected.first?.file {
            showDetailInput(.renameFile(file.name), title: "Rename File", hint: "File name", initialValue: (file.name as NSString).lastPathComponent)
        } else {
            openContentLayoutEditor(for: torrent, fileIDs: fileIDs)
        }
    }

    private func applyPriorityByShownOrder(to rows: [TorrentContentRow]) {
        guard !rows.isEmpty else { return }
        let groupSize = max(rows.count / 3, 1)
        var prioritiesByFileID: [Int: Int] = [:]
        for (index, row) in rows.enumerated() {
            let priority = switch index / groupSize {
            case 0: 7
            case 1: 6
            default: 1
            }
            for fileID in row.fileIDs { prioritiesByFileID[fileID] = priority }
        }
        guard !prioritiesByFileID.isEmpty else { return }
        Task {
            await performDetailAction { hash in
                for priority in [7, 6, 1] {
                    let indices = prioritiesByFileID.compactMap { $0.value == priority ? $0.key : nil }.sorted()
                    guard !indices.isEmpty else { continue }
                    try await store.setFilePriority(hash: hash, indices: indices, priority: priority)
                }
            }
        }
    }

    @ViewBuilder
    private func patternFormatLabel(_ title: String, mode: String) -> some View {
        if contentFileFilterMode == mode {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    @ViewBuilder private func filePriorityActions(for selection: Set<Int>) -> some View {
        Button("Do Not Download") { setFilePriority(selection, to: 0) }
        Button("Normal") { setFilePriority(selection, to: 1) }
        Button("High") { setFilePriority(selection, to: 6) }
        Button("Maximum") { setFilePriority(selection, to: 7) }
    }

    private func filePriorityLabel(_ priority: Int) -> String {
        switch priority {
        case 0: "Do Not Download"
        case 6: "High"
        case 7: "Maximum"
        default: "Normal"
        }
    }

    private var peerDetails: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Peers").font(.caption.weight(.semibold))
                Spacer()
                Button { showDetailInput(.addPeer, title: "Add Peers", hint: "One peer per line: IPv4:port or [IPv6]:port") } label: { Image(systemName: "plus") }
                    .buttonStyle(.glass)
                    .disabled(peerAdditionDisabledReason != nil)
                    .help(peerAdditionDisabledReason ?? "Add peers")
                    .accessibilityLabel("Add peers")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            if peers.isEmpty {
                ContentUnavailableView("No Peers", systemImage: "person.2", description: Text("No peers are connected to this torrent."))
            } else {
                Table(peers, selection: $selectedPeerIDs, sortOrder: $peerSortOrder, columnCustomization: $peerColumnCustomization) {
                    peerPrimaryColumns
                    peerDetailColumns
                }
                .contextMenu(forSelectionType: String.self) { target in
                    peerContextMenu(for: target)
                }
                .alternatingRowBackgrounds(alternatingTransferRows ? .enabled : .disabled)
            }
        }
    }

    @TableColumnBuilder<TorrentPeer, KeyPathComparator<TorrentPeer>>
    private var peerPrimaryColumns: some TableColumnContent<TorrentPeer, KeyPathComparator<TorrentPeer>> {
        TableColumn("Country/Region", value: \.countryName) { peer in
            HStack(spacing: 5) {
                if let flag = peer.countryFlag { Text(flag) }
                else { Image(systemName: "globe").foregroundStyle(.tertiary) }
                Text(peer.countryName).lineLimit(1)
            }
            .help(peer.countryName)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Country or region: \(peer.countryName)")
        }
        .width(min: 110, ideal: 150)
        .customizationID("peer.country")
        TableColumn("IP/Address", value: \.ip) { peer in
            Text(peer.ip).lineLimit(1).help(peer.host_name ?? peer.ip)
        }
        .width(min: 100, ideal: 140)
        .customizationID("peer.ip")
        TableColumn("Port", value: \.portSortValue) { peer in Text("\(peer.port ?? 0)") }
            .width(min: 50, ideal: 65).customizationID("peer.port")
        TableColumn("Connection", value: \.connectionSortValue) { peer in Text(peer.connection ?? "—") }
            .width(min: 80, ideal: 115).customizationID("peer.connection")
        TableColumn("Flags", value: \.flagsSortValue) { peer in Text(peer.flags ?? "—").help(peer.flags_desc ?? "Peer flags") }
            .width(min: 55, ideal: 70).customizationID("peer.flags")
        TableColumn("Client", value: \.clientSortValue) { peer in Text(peer.client ?? "Unknown client") }
            .width(min: 100, ideal: 150).customizationID("peer.client")
        TableColumn("Peer ID Client", value: \.peerIDClientSortValue) { peer in Text(peer.peer_id_client ?? "—") }
            .width(min: 110, ideal: 150).customizationID("peer.peerIDClient").defaultVisibility(.hidden)
        TableColumn("Progress", value: \.progressSortValue) { peer in
            Text((peer.progress ?? 0).formatted(.percent.precision(.fractionLength(0))))
        }
        .width(min: 65, ideal: 85)
        .customizationID("peer.progress")
    }

    @TableColumnBuilder<TorrentPeer, KeyPathComparator<TorrentPeer>>
    private var peerDetailColumns: some TableColumnContent<TorrentPeer, KeyPathComparator<TorrentPeer>> {
        TableColumn("Down Speed", value: \.downloadSpeedSortValue) { peer in Text(TransferStatus.rateText(peer.dl_speed ?? 0)) }
            .width(min: 85, ideal: 110).customizationID("peer.downSpeed")
        TableColumn("Up Speed", value: \.uploadSpeedSortValue) { peer in Text(TransferStatus.rateText(peer.up_speed ?? 0)) }
            .width(min: 85, ideal: 110).customizationID("peer.upSpeed")
        TableColumn("Downloaded", value: \.downloadedSortValue) { peer in
            Text(ByteCountFormatter.string(fromByteCount: peer.downloaded ?? 0, countStyle: .file))
        }
        .width(min: 85, ideal: 110)
        .customizationID("peer.downloaded")
        TableColumn("Uploaded", value: \.uploadedSortValue) { peer in
            Text(ByteCountFormatter.string(fromByteCount: peer.uploaded ?? 0, countStyle: .file))
        }
        .width(min: 85, ideal: 110)
        .customizationID("peer.uploaded")
        TableColumn("Relevance", value: \.relevanceSortValue) { peer in
            Text("\(((peer.relevance ?? 0) * 100).formatted(.number.precision(.fractionLength(0))))%")
        }
        .width(min: 70, ideal: 90)
        .customizationID("peer.relevance")
        TableColumn("Contribution", value: \.contributionSortValue) { peer in
            Text("\(((peer.contribution ?? 0) * 100).formatted(.number.precision(.fractionLength(0))))%")
        }
        .width(min: 80, ideal: 100)
        .customizationID("peer.contribution")
        TableColumn("Files", value: \.filesSortValue) { peer in
            Text(peer.files?.replacingOccurrences(of: "\n", with: "; ") ?? "—").help(peer.files ?? "")
        }
        .width(min: 150, ideal: 260)
        .customizationID("peer.files")
    }

    @ViewBuilder
    private func peerContextMenu(for target: Set<String>) -> some View {
        let selectedPeers = peers.filter { target.contains($0.id) }
        Button("Add Peers…") {
            showDetailInput(.addPeer, title: "Add Peers", hint: "One peer per line: IPv4:port or [IPv6]:port")
        }
        .disabled(peerAdditionDisabledReason != nil)
        Button("Copy IP:port") {
            copyToPasteboard(selectedPeers.map(peerAddress).joined(separator: "\n"))
        }
        .disabled(selectedPeers.isEmpty)
        Button("Ban Peer Permanently", role: .destructive) {
            let addresses = selectedPeers.map(peerAddress)
            Task {
                do { try await store.banPeers(addresses: addresses) }
                catch { actionError = error.localizedDescription }
            }
        }
        .disabled(selectedPeers.isEmpty)
    }

    private func peerAddress(_ peer: TorrentPeer) -> String {
        let host = peer.ip.contains(":") ? "[\(peer.ip)]" : peer.ip
        return "\(host):\(peer.port ?? 0)"
    }

    private var webSeedDetails: some View {
        VStack(spacing: 0) {
            HStack {
                Text("HTTP Sources").font(.caption.weight(.semibold))
                Spacer()
                Button { showDetailInput(.addWebSeed, title: "Add HTTP Source", hint: "HTTP or HTTPS URL") } label: { Image(systemName: "plus") }
                    .buttonStyle(.glass)
                    .help("Add web seed")
                    .accessibilityLabel("Add HTTP source")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            List(webSeeds) { seed in
                Text(seed.url).font(.caption).textSelection(.enabled)
                    .contextMenu {
                        Button("Edit URL…") { showDetailInput(.editWebSeed(seed.url), title: "Edit HTTP Source", hint: "HTTP or HTTPS URL", initialValue: seed.url) }
                        Button("Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(seed.url, forType: .string) }
                        Button("Remove Source", role: .destructive) {
                            Task { await performDetailAction { try await store.removeWebSeed(hash: $0, url: seed.url) } }
                        }
                    }
            }
        }
    }

    private var speedDetails: some View {
        let cutoff = Date().addingTimeInterval(-TimeInterval(speedGraphPeriod))
        let recent = store.sessionSpeedHistory.filter { $0.date >= cutoff }
        let step = max(1, (recent.count + 899) / 900)
        var history = recent.enumerated().compactMap { $0.offset.isMultiple(of: step) ? $0.element : nil }
        if let last = recent.last, history.last?.id != last.id { history.append(last) }
        let enabledSeries = SpeedGraphSeries.allCases.filter(isGraphEnabled)
        let maximumRate = history.flatMap { sample in enabledSeries.map { sample.value(for: $0) } }.max() ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Label("Total Download \(TransferStatus.rateText(store.transferStatus.totalDownloadRate))", systemImage: "arrow.down")
                    .foregroundStyle(.blue)
                Label("Total Upload \(TransferStatus.rateText(store.transferStatus.totalUploadRate))", systemImage: "arrow.up")
                    .foregroundStyle(.green)
                Spacer()
                Picker("Period", selection: $speedGraphPeriod) {
                    Text("1 Minute").tag(60)
                    Text("5 Minutes").tag(300)
                    Text("30 Minutes").tag(1_800)
                    Text("3 Hours").tag(10_800)
                    Text("6 Hours").tag(21_600)
                    Text("12 Hours").tag(43_200)
                    Text("24 Hours").tag(86_400)
                }
                .frame(width: 130)
                Menu("Select Graphs") {
                    Toggle("Total Upload", isOn: $showTotalUploadGraph)
                    Toggle("Total Download", isOn: $showTotalDownloadGraph)
                    Toggle("Payload Upload", isOn: $showPayloadUploadGraph)
                    Toggle("Payload Download", isOn: $showPayloadDownloadGraph)
                    Toggle("Overhead Upload", isOn: $showOverheadUploadGraph)
                    Toggle("Overhead Download", isOn: $showOverheadDownloadGraph)
                    Toggle("DHT Upload", isOn: $showDHTUploadGraph)
                    Toggle("DHT Download", isOn: $showDHTDownloadGraph)
                    Toggle("Tracker Upload", isOn: $showTrackerUploadGraph)
                    Toggle("Tracker Download", isOn: $showTrackerDownloadGraph)
                }
            }
            .font(.caption)
            Chart {
                ForEach(enabledSeries) { series in
                    ForEach(history) { sample in
                        LineMark(
                            x: .value("Time", sample.date),
                            y: .value("Bytes/s", sample.value(for: series)),
                            series: .value("Graph", series.title)
                        )
                        .foregroundStyle(by: .value("Graph", series.title))
                    }
                }
            }
            .chartLegend(position: .bottom, spacing: 6)
            .chartXAxisLabel("Time")
            .chartYAxisLabel("Bytes per second")
            .chartForegroundStyleScale(domain: SpeedGraphSeries.allCases.map(\.title), range: [.blue, .green, .cyan, .mint, .orange, .yellow, .purple, .pink, .indigo, .teal])
            .chartYScale(domain: 0...max(1024, maximumRate))
        }
        .padding(18)
    }

    private func isGraphEnabled(_ series: SpeedGraphSeries) -> Bool {
        switch series {
        case .totalUpload: showTotalUploadGraph
        case .totalDownload: showTotalDownloadGraph
        case .payloadUpload: showPayloadUploadGraph
        case .payloadDownload: showPayloadDownloadGraph
        case .overheadUpload: showOverheadUploadGraph
        case .overheadDownload: showOverheadDownloadGraph
        case .dhtUpload: showDHTUploadGraph
        case .dhtDownload: showDHTDownloadGraph
        case .trackerUpload: showTrackerUploadGraph
        case .trackerDownload: showTrackerDownloadGraph
        }
    }

    private func loadDetails() async {
        properties = nil
        pieceStates = []
        pieceAvailability = []
        trackers = []
        files = []
        selectedContentNodeIDs = []
        peers = []
        webSeeds = []
        await refreshDetails()
    }

    private func refreshDetails(reportErrors: Bool = true) async {
        guard let torrentID = selectedTorrentID, store.isConnected else { return }
        let requestedTab = detailTab
        do {
            switch requestedTab {
            case .general:
                async let propertyRequest = store.properties(for: torrentID)
                async let statesRequest = try? store.pieceStates(for: torrentID)
                async let availabilityRequest = try? store.pieceAvailability(for: torrentID)
                let nextProperties = try await propertyRequest
                let nextPieceStates = (await statesRequest) ?? []
                let nextPieceAvailability = (await availabilityRequest) ?? []
                guard selectedTorrentID == torrentID, detailTab == requestedTab, store.isConnected else { return }
                properties = nextProperties
                pieceStates = nextPieceStates
                pieceAvailability = nextPieceAvailability
            case .trackers:
                let nextTrackers = try await store.trackers(for: torrentID)
                guard selectedTorrentID == torrentID, detailTab == requestedTab, store.isConnected else { return }
                trackers = nextTrackers
            case .content:
                let nextFiles = try await store.files(for: torrentID)
                guard selectedTorrentID == torrentID, detailTab == requestedTab, store.isConnected else { return }
                files = nextFiles
            case .peers:
                let nextPeers = try await store.peers(for: torrentID)
                guard selectedTorrentID == torrentID, detailTab == requestedTab, store.isConnected else { return }
                peers = nextPeers
            case .httpSources:
                let nextWebSeeds = try await store.webSeeds(for: torrentID)
                guard selectedTorrentID == torrentID, detailTab == requestedTab, store.isConnected else { return }
                webSeeds = nextWebSeeds
            default: break
            }
        } catch is CancellationError {
            return
        } catch {
            if reportErrors { actionError = error.localizedDescription }
        }
    }

    @ViewBuilder private func torrentContextMenu(for target: Set<String>) -> some View {
        let selectedTorrents = torrents.filter { target.contains($0.id) }
        let hashes = selectedTorrents.map(\.id)
        let targetTorrent = selectedTorrents.first
        let oneNotFinished = selectedTorrents.contains { $0.progress < 1 }
        let oneHasMetadata = selectedTorrents.contains { $0.hasMetadata }
        let needsStart = selectedTorrents.contains { $0.forceStart || [.paused, .checking, .error].contains($0.state) }
        let needsStop = selectedTorrents.contains { ![.paused, .error].contains($0.state) || $0.state == .checking }
        let needsForceStart = selectedTorrents.contains { !$0.forceStart || $0.state == .error || $0.rawState == "missingFiles" }
        let canReannounce = selectedTorrents.contains {
            ![.paused, .queued, .checking, .error].contains($0.state) && $0.rawState != "missingFiles"
        }
        let queueingEnabled = selectedTorrents.contains { ($0.sortNumbers["priority"] ?? -1) >= 0 }

        if needsStart {
            Button("Start") { runBulkAction(hashes: hashes) { try await store.command(.start, hashes: $0) } }
        }
        if needsStop {
            Button("Stop") { runBulkAction(hashes: hashes) { try await store.command(.stop, hashes: $0) } }
        }
        if needsForceStart {
            Button("Force Start") { runBulkAction(hashes: hashes) { try await store.setForceStart(true, hashes: $0) } }
        }
        Divider()
        if hashes.count == 1 {
            Button("Rename…") { beginTextAction(.rename, target: target) }
            Button("Manage Content…") { openContentLayoutEditor(for: targetTorrent) }
        }
        Button("Set Location…") { beginTextAction(.location, target: target) }
        Menu("Category") {
            Button("New Category…") { openOrganization() }
            Divider()
            Button("Uncategorized") { runBulkAction(hashes: hashes) { try await store.setCategory("", hashes: $0) } }
            ForEach(allFilterCategories.filter { !$0.isEmpty }, id: \.self) { category in
                Button(category) { runBulkAction(hashes: hashes) { try await store.setCategory(category, hashes: $0) } }
            }
        }
        Menu("Tags") {
            Button("Add or Edit Tags…") { beginTextAction(.tags, target: target) }
            Button("Remove All Tags…", role: .destructive) {
                requestRemoveAllTags(hashes: hashes)
            }
            Divider()
            ForEach(allFilterTags, id: \.self) { tag in
                let assignedCount = torrents.filter { target.contains($0.id) && torrentHasTag($0, tag) }.count
                let isAssignedToAll = !hashes.isEmpty && assignedCount == hashes.count
                let isPartiallyAssigned = assignedCount > 0 && !isAssignedToAll
                Button {
                    runBulkAction(hashes: hashes) { selected in
                        if isAssignedToAll { try await store.removeTorrentTags([tag], hashes: selected) }
                        else { try await store.addTags([tag], hashes: selected) }
                    }
                } label: {
                    Label(tag + (isPartiallyAssigned ? " (Mixed)" : ""), systemImage: isAssignedToAll ? "checkmark.circle.fill" : "circle")
                }
            }
        }
        Button("Edit Trackers…") { trackerBatchEditorTarget = TrackerBatchEditorTarget(hashes: hashes) }
        Button("Torrent Options…") { torrentOptionsTarget = TorrentOptionsTarget(hashes: hashes) }
        if oneHasMetadata {
            Button("Preview File…") {
                queuePreviews(for: selectedTorrents)
            }
        }
        Button("Open Destination Folder") {
            if let targetTorrent { openDestinationFolder(for: targetTorrent) }
        }
        .disabled(targetTorrent?.savePath.isEmpty ?? true)
        if queueingEnabled && oneNotFinished {
            Menu("Queue") {
                Button("Move to Top") { runBulkAction(hashes: hashes) { try await store.command(.topPrio, hashes: $0) } }
                Button("Move Up") { runBulkAction(hashes: hashes) { try await store.command(.increasePrio, hashes: $0) } }
                Button("Move Down") { runBulkAction(hashes: hashes) { try await store.command(.decreasePrio, hashes: $0) } }
                Button("Move to Bottom") { runBulkAction(hashes: hashes) { try await store.command(.bottomPrio, hashes: $0) } }
            }
        }
        Divider()
        if oneHasMetadata {
            Button("Force Recheck") { requestTorrentRecheck(hashes: hashes) }
        }
        Button("Force Reannounce") { runBulkAction(hashes: hashes) { try await store.command(.reannounce, hashes: $0) } }
            .disabled(!canReannounce)
            .help(canReannounce ? "Force reannounce the selected torrents" : "Cannot reannounce stopped, queued, errored, or checking torrents")
        Divider()
        if oneNotFinished {
            let sequentialMixed = Set(selectedTorrents.map(\.sequentialDownload)).count > 1
            let firstLastMixed = Set(selectedTorrents.map(\.firstLastPiecePriority)).count > 1
            Toggle(sequentialMixed ? "Sequential Download (Mixed)" : "Sequential Download", isOn: Binding(
                get: { selectedTorrents.allSatisfy(\.sequentialDownload) },
                set: { setSequentialDownload($0, torrents: selectedTorrents) }
            ))
            .help(sequentialMixed ? "Selected torrents have different sequential download settings" : "Download files in sequential order")
            Toggle(firstLastMixed ? "First and Last Pieces First (Mixed)" : "First and Last Pieces First", isOn: Binding(
                get: { selectedTorrents.allSatisfy(\.firstLastPiecePriority) },
                set: { setFirstLastPiecePriority($0, torrents: selectedTorrents) }
            ))
            .help(firstLastMixed ? "Selected torrents have different first and last piece settings" : "Prioritize the first and last pieces")
        }
        let autoManagementMixed = Set(selectedTorrents.map(\.automaticManagement)).count > 1
        Toggle(autoManagementMixed ? "Automatic Torrent Management (Mixed)" : "Automatic Torrent Management", isOn: Binding(
            get: { selectedTorrents.allSatisfy(\.automaticManagement) },
            set: { value in
                if value {
                    automaticManagementConfirmationHashes = hashes
                } else {
                    runBulkAction(hashes: hashes) { try await store.setAutomaticManagement(false, hashes: $0) }
                }
            }
        ))
        .help(autoManagementMixed ? "Selected torrents have different automatic management settings" : "Use category settings to choose torrent paths")
        if !oneNotFinished && oneHasMetadata {
            let superSeedingMixed = Set(selectedTorrents.map(\.superSeeding)).count > 1
            Toggle(superSeedingMixed ? "Super Seeding (Mixed)" : "Super Seeding", isOn: Binding(
                get: { selectedTorrents.allSatisfy(\.superSeeding) },
                set: { value in runBulkAction(hashes: hashes) { try await store.setSuperSeeding(value, hashes: $0) } }
            ))
            .help(superSeedingMixed ? "Selected torrents have different super seeding settings" : "Enable super seeding mode")
        }
        Menu("Copy") {
            Button("Names") { copySelectedTorrents(\.name, target: target) }
            Button("Torrent IDs") { copySelectedTorrents(\.id, target: target) }
            Button("Save Paths") { copySelectedTorrents(\.savePath, target: target) }
            Button("Content Paths") { copyContentPaths(target: target) }
            Button("Comments") { copyComments(target: target) }
            Button("Infohash v1") { copyColumn("infohash_v1", target: target) }
                .disabled(!selectedTorrents.contains { $0.column("infohash_v1") != "—" })
            Button("Infohash v2") { copyColumn("infohash_v2", target: target) }
                .disabled(!selectedTorrents.contains { $0.column("infohash_v2") != "—" })
            Button("Magnet Links") { copyMagnets(target: target) }
        }
        Button("Export .torrent Files…") { exportSelectedTorrents(hashes: hashes) }
        Divider()
        Button("Remove…", role: .destructive) { requestRemoval(hashes: Array(target)) }
    }

    private func runBulkAction(hashes: [String]? = nil, _ action: @escaping ([String]) async throws -> Void) {
        let hashes = hashes ?? selectedHashes
        guard !hashes.isEmpty else { return }
        Task {
            do { try await action(hashes) }
            catch { actionError = error.localizedDescription }
        }
    }

    private func setSequentialDownload(_ enabled: Bool, torrents: [Torrent]) {
        let hashes = torrents.filter { $0.sequentialDownload != enabled }.map(\.id)
        runBulkAction(hashes: hashes) { try await store.command(.toggleSequentialDownload, hashes: $0) }
    }

    private func setFirstLastPiecePriority(_ enabled: Bool, torrents: [Torrent]) {
        let hashes = torrents.filter { $0.firstLastPiecePriority != enabled }.map(\.id)
        runBulkAction(hashes: hashes) { try await store.command(.toggleFirstLastPiecePrio, hashes: $0) }
    }

    private func requestTorrentRecheck(hashes: [String]) {
        guard !hashes.isEmpty else { return }
        Task {
            do {
                if try await store.shouldConfirmTorrentRecheck() {
                    recheckConfirmationHashes = hashes
                } else {
                    try await store.command(.recheck, hashes: hashes)
                }
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func requestRemoveAllTags(hashes: [String]) {
        guard !hashes.isEmpty else { return }
        clearTagsHashes = hashes
        if confirmRemoveAllTags {
            showsClearTagsConfirmation = true
        } else {
            removeAllTags(from: hashes)
        }
    }

    private func removeAllTags(from hashes: [String]) {
        runBulkAction(hashes: hashes) { try await store.removeTorrentTags([], hashes: $0) }
    }

    private func requestTrackerHostRemoval(_ host: String) {
        guard !host.isEmpty else { return }
        if confirmRemoveTrackerFromAllTorrents {
            trackerHostRemovalConfirmation = host
        } else {
            removeTrackerHostFromAllTorrents(host)
        }
    }

    private func removePendingTrackerHost() {
        guard let host = trackerHostRemovalConfirmation else { return }
        trackerHostRemovalConfirmation = nil
        removeTrackerHostFromAllTorrents(host)
    }

    private func removeTrackerHostFromAllTorrents(_ host: String) {
        Task {
            do {
                try await store.removeTrackerHostFromAllTorrents(host)
                if trackerFilter == host { trackerFilter = nil }
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func beginTextAction(_ action: TorrentTextAction, target: Set<String>) {
        selectedTorrentIDs = target
        textAction = action
    }

    private func requestRemoval(hashes: [String]) {
        guard !hashes.isEmpty else { return }
        selectedTorrentIDs = Set(hashes)
        if confirmTorrentDeletion {
            showsRemoveConfirmation = true
        } else {
            removeTorrents(hashes, deleteFiles: false)
        }
    }

    private func removeSelectedTorrent(deleteFiles: Bool) {
        removeTorrents(selectedHashes, deleteFiles: deleteFiles)
    }

    private func removeTorrents(_ hashes: [String], deleteFiles: Bool) {
        guard !hashes.isEmpty else { return }
        Task {
            do {
                try await store.remove(hashes, deleteFiles: deleteFiles)
                selectedTorrentIDs.subtract(hashes)
            } catch { actionError = error.localizedDescription }
        }
    }

    private func initialValue(for action: TorrentTextAction) -> String {
        guard let selectedTorrent else { return "" }
        return switch action {
        case .rename: selectedTorrent.name
        case .location: selectedTorrent.savePath
        case .category: selectedTorrent.category
        case .tags: selectedTorrent.tags
        }
    }

    private func applyTextAction(_ action: TorrentTextAction, value: String) async throws {
        let hashes = selectedHashes
        guard !hashes.isEmpty else { return }
        switch action {
        case .rename:
            guard let hash = hashes.first else { return }
            try await store.rename(hash, to: value)
        case .location: try await store.setLocation(value, hashes: hashes)
        case .category: try await store.setCategory(value, hashes: hashes)
        case .tags: try await store.setTags(value, hashes: hashes)
        }
    }

    private func showDetailInput(_ operation: DetailInput.Operation, title: String, hint: String, initialValue: String = "") {
        guard let hash = selectedTorrentID else { return }
        detailInput = DetailInput(hash: hash, operation: operation, title: title, hint: hint, initialValue: initialValue)
    }

    private func openContentLayoutEditor(for torrent: Torrent?, fileIDs: Set<Int>? = nil) {
        guard let torrent else { return }
        selectedTorrentIDs = [torrent.id]
        showDetailPane = true
        detailTab = .content
        contentLayoutEditorTarget = ContentLayoutEditorTarget(hash: torrent.id, torrentName: torrent.name, initialFileIDs: fileIDs)
    }

    private func applyDetailInput(_ input: DetailInput, value: String) async throws {
        switch input.operation {
        case .addTracker: try await store.addTracker(hash: input.hash, url: value)
        case let .editTracker(oldURL): try await store.editTracker(hash: input.hash, url: oldURL, newURL: value)
        case .addWebSeed: try await store.addWebSeed(hash: input.hash, url: value)
        case let .editWebSeed(oldURL): try await store.editWebSeed(hash: input.hash, url: oldURL, newURL: value)
        case .addPeer:
            let peers = value.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !peers.isEmpty else { throw PeerAddressInputError.noPeers }
            if let invalidPeer = peers.first(where: { !isValidPeerAddress($0) }) {
                throw PeerAddressInputError.invalidPeer(invalidPeer)
            }
            try await store.addPeer(hash: input.hash, address: peers.joined(separator: "|"))
        case let .renameFile(oldPath):
            let parent = (oldPath as NSString).deletingLastPathComponent
            let newPath = parent.isEmpty ? value : (parent as NSString).appendingPathComponent(value)
            try await store.renameFile(hash: input.hash, oldPath: oldPath, newPath: newPath)
        }
        if input.operation != .addPeer { await loadDetails() }
    }

    private var peerAdditionDisabledReason: String? {
        guard let selectedTorrent else { return "Select a torrent first" }
        if ["yes", "true", "1"].contains(selectedTorrent.column("private").lowercased()) {
            return "Cannot add peers to a private torrent"
        }
        if selectedTorrent.state == .checking { return "Cannot add peers while the torrent is checking" }
        if selectedTorrent.state == .queued { return "Cannot add peers while the torrent is queued" }
        return nil
    }

    private func isValidPeerAddress(_ source: String) -> Bool {
        let host: String
        let portText: Substring
        let isIPv6: Bool
        if source.first == "[", let closingBracket = source.firstIndex(of: "]"), source[closingBracket...].hasPrefix("]:") {
            host = String(source[source.index(after: source.startIndex)..<closingBracket])
            portText = source[source.index(closingBracket, offsetBy: 2)...]
            isIPv6 = true
        } else if let separator = source.lastIndex(of: ":"), !source[..<separator].contains(":") {
            host = String(source[..<separator])
            portText = source[source.index(after: separator)...]
            isIPv6 = false
        } else {
            return false
        }
        guard let port = UInt16(portText), port > 0, !host.isEmpty else { return false }
        if isIPv6 {
            var address = in6_addr()
            return host.withCString { inet_pton(AF_INET6, $0, &address) == 1 }
        }
        var address = in_addr()
        return host.withCString { inet_pton(AF_INET, $0, &address) == 1 }
    }

    private func performDetailAction(_ action: (String) async throws -> Void) async {
        guard let hash = selectedTorrentID else { return }
        do {
            try await action(hash)
            await loadDetails()
        } catch { actionError = error.localizedDescription }
    }

    private func setFilePriority(_ fileIDs: Set<Int>, to priority: Int) {
        guard !fileIDs.isEmpty else { return }
        Task {
            await performDetailAction { try await store.setFilePriority(hash: $0, indices: fileIDs.sorted(), priority: priority) }
        }
    }

    private var downloadCompletionLabel: String {
        switch downloadCompletionAction {
        case "quit": "Quit qBitX"
        case "sleep": "Sleep System"
        case "restart": "Restart System"
        case "shutdown": "Shut Down System"
        default: "Do Nothing"
        }
    }

    @ViewBuilder private func completionActionButton(_ action: String, title: String) -> some View {
        Button {
            downloadCompletionAction = action
        } label: {
            if downloadCompletionAction == action {
                Label(LocalizedStringKey(title), systemImage: "checkmark")
            } else {
                Text(LocalizedStringKey(title))
            }
        }
    }

    private func observeTorrentCompletions(from previous: TorrentCompletionSnapshot, to current: TorrentCompletionSnapshot) {
        guard hasObservedTorrentCompletionSnapshot else {
            hasObservedTorrentCompletionSnapshot = true
            return
        }

        let newlyAddedIDs = Set(current.stateByID.keys).subtracting(previous.stateByID.keys)
        let newlyCompletedIDs = Set(current.stateByID.compactMap { entry in
            previous.stateByID[entry.key]?.isComplete == false && entry.value.isComplete ? entry.key : nil
        })
        let errorStates: Set<String> = ["error", "missingFiles"]
        let newlyErroredIDs = Set(current.stateByID.compactMap { entry in
            let isNowErrored = errorStates.contains(entry.value.rawState)
            let wasErrored = previous.stateByID[entry.key].map { errorStates.contains($0.rawState) } ?? false
            return isNowErrored && !wasErrored ? entry.key : nil
        })
        let previousIncompleteIDs = Set(previous.stateByID.compactMap { entry in
            entry.value.isComplete ? nil : entry.key
        })
        let currentIncompleteIDs = Set(current.stateByID.compactMap { entry in
            entry.value.isComplete ? nil : entry.key
        })

        if systemNotificationsEnabled {
            for torrent in torrents where newlyAddedIDs.contains(torrent.id) && notifyOnTorrentAdded {
                MacOSNotifications.post(title: "Torrent added", body: "‘\(torrent.name)’ was added.")
            }
            for torrent in torrents where newlyCompletedIDs.contains(torrent.id) && notifyOnDownloadComplete {
                MacOSNotifications.post(title: "Download completed", body: "‘\(torrent.name)’ has finished downloading.")
            }
            for torrent in torrents where newlyErroredIDs.contains(torrent.id) && notifyOnTorrentError {
                let issue = torrent.rawState == "missingFiles" ? "has missing files" : "has an error"
                MacOSNotifications.post(title: "Torrent problem", body: "‘\(torrent.name)’ \(issue). Check its status in qBitX.")
            }
        }

        if recursiveDownloadEnabled, store.usesBundledBackend, !newlyCompletedIDs.isEmpty {
            inspectForRecursiveTorrents(torrents.filter { newlyCompletedIDs.contains($0.id) })
        }

        guard !previousIncompleteIDs.isEmpty,
              currentIncompleteIDs.isEmpty,
              previousIncompleteIDs.allSatisfy({ current.stateByID[$0]?.isComplete == true }),
              downloadCompletionAction != "none" else { return }

        if confirmAutoCompletionAction {
            showsDownloadCompletionAction = true
        } else {
            performDownloadCompletionAction()
        }
    }

    private var recursiveTorrentConfirmationMessage: String {
        var seenNames = Set<String>()
        let sourceNames = recursiveTorrentSourceNames.filter { seenNames.insert($0).inserted }
        let sourceSummary: String
        if sourceNames.count <= 3 {
            sourceSummary = "\(sourceNames.map { "‘\($0)’" }.joined(separator: ", "))"
        } else {
            sourceSummary = "\(sourceNames.prefix(3).map { "‘\($0)’" }.joined(separator: ", ")) and \(sourceNames.count - 3) more"
        }
        let fileNoun = recursiveTorrentCandidates.count == 1 ? ".torrent file" : ".torrent files"
        let addQuestion = recursiveTorrentCandidates.count == 1 ? "Add it now?" : "Add them now?"
        return "The completed torrent\(sourceNames.count == 1 ? "" : "s") \(sourceSummary) contain\(sourceNames.count == 1 ? "s" : "") \(recursiveTorrentCandidates.count) \(fileNoun). \(addQuestion)"
    }

    private func inspectForRecursiveTorrents(_ completedTorrents: [Torrent]) {
        let unseenTorrents = completedTorrents.filter { inspectedRecursiveTorrentIDs.insert($0.id).inserted }
        guard !unseenTorrents.isEmpty else { return }

        Task {
            var discoveredCandidates: [RecursiveTorrentCandidate] = []
            var discoveredSourceNames: [String] = []
            var knownCandidates = Set(recursiveTorrentCandidates.map(\.id))

            for torrent in unseenTorrents {
                do {
                    let torrentFiles = try await store.files(for: torrent.id)
                    var foundTorrentFile = false
                    for file in torrentFiles where URL(fileURLWithPath: file.name).pathExtension.lowercased() == "torrent" {
                        guard localTorrentFileURL(relativePath: file.name, savePath: torrent.savePath) != nil else { continue }
                        let candidate = RecursiveTorrentCandidate(relativePath: file.name, savePath: torrent.savePath)
                        if knownCandidates.insert(candidate.id).inserted {
                            discoveredCandidates.append(candidate)
                            foundTorrentFile = true
                        }
                    }
                    if foundTorrentFile { discoveredSourceNames.append(torrent.name) }
                } catch {
                    actionError = "Could not inspect the completed torrent ‘\(torrent.name)’ for .torrent files: \(error.localizedDescription)"
                }
            }

            guard recursiveDownloadEnabled, store.usesBundledBackend, !discoveredCandidates.isEmpty else { return }
            recursiveTorrentCandidates.append(contentsOf: discoveredCandidates)
            recursiveTorrentSourceNames.append(contentsOf: discoveredSourceNames)
            showsRecursiveTorrentConfirmation = true
        }
    }

    private func localTorrentFileURL(relativePath: String, savePath: String) -> URL? {
        let pathComponents = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !savePath.isEmpty,
              !pathComponents.isEmpty,
              pathComponents.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              pathComponents.last.map({ URL(fileURLWithPath: String($0)).pathExtension.lowercased() == "torrent" }) == true else { return nil }

        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: savePath, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        let candidateURL = pathComponents.reduce(rootURL) { partialURL, component in
            partialURL.appendingPathComponent(String(component), isDirectory: false)
        }.resolvingSymlinksInPath().standardizedFileURL
        let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard candidateURL.path.hasPrefix(rootPrefix),
              let attributes = try? fileManager.attributesOfItem(atPath: candidateURL.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              fileManager.isReadableFile(atPath: candidateURL.path) else { return nil }
        return candidateURL
    }

    private func addRecursiveTorrentCandidates() {
        let candidates = recursiveTorrentCandidates
        discardRecursiveTorrentCandidates()
        guard !candidates.isEmpty else { return }
        guard store.usesBundledBackend else {
            actionError = "Nested torrents can only be added from files available in the local qBitX library."
            return
        }

        Task {
            var failures: [String] = []
            for candidate in candidates {
                guard store.usesBundledBackend else {
                    failures.append("\(candidate.filename): qBitX switched to a remote server")
                    continue
                }
                guard let url = localTorrentFileURL(relativePath: candidate.relativePath, savePath: candidate.savePath) else {
                    failures.append("\(candidate.filename): the file is no longer available inside its download folder")
                    continue
                }
                do {
                    let data = try Data(contentsOf: url)
                    var options = TorrentAddOptions()
                    options.savePath = candidate.savePath
                    options.automaticManagement = false
                    let addedTorrentID = try await store.add(
                        file: data,
                        filename: candidate.filename,
                        options: options,
                        verifyNewTorrent: autoDeleteTorrentFileMode > 0
                    )
                    if addedTorrentID != nil && autoDeleteTorrentFileMode > 0 {
                        try removeLocalTorrentSource(PendingTorrentFile(name: candidate.filename, data: data, sourceURL: url))
                    }
                } catch {
                    failures.append("\(candidate.filename): \(error.localizedDescription)")
                }
            }
            if !failures.isEmpty {
                actionError = "Some nested torrents could not be added. " + failures.joined(separator: "\n")
            }
        }
    }

    private func discardRecursiveTorrentCandidates() {
        showsRecursiveTorrentConfirmation = false
        recursiveTorrentCandidates = []
        recursiveTorrentSourceNames = []
    }

    private func performDownloadCompletionAction() {
        switch downloadCompletionAction {
        case "quit": NSApp.terminate(nil)
        case "sleep": runSystemEvent("tell application \"System Events\" to sleep")
        case "restart": runSystemEvent("tell application \"System Events\" to restart")
        case "shutdown": runSystemEvent("tell application \"System Events\" to shut down")
        default: break
        }
    }

    private func runSystemEvent(_ source: String) {
        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            actionError = errorInfo[NSAppleScript.errorMessage] as? String ?? "macOS could not perform the selected power action."
        }
    }

    private func setSessionPaused(_ paused: Bool) {
        Task {
            do { try await store.setSessionPaused(paused) }
            catch { actionError = error.localizedDescription }
        }
    }

    private func toggleSpeedLimitsMode() {
        Task {
            do { try await store.toggleSpeedLimitsMode() }
            catch { actionError = error.localizedDescription }
        }
    }

    private func copySelectedTorrents(_ keyPath: KeyPath<Torrent, String>, target: Set<String>) {
        let value = torrents.filter { target.contains($0.id) }.map { $0[keyPath: keyPath] }.joined(separator: "\n")
        copyToPasteboard(value)
    }

    private func copyColumn(_ key: String, target: Set<String>) {
        copyToPasteboard(torrents.filter { target.contains($0.id) }.map { $0.column(key) }.joined(separator: "\n"))
    }

    private func copyContentPaths(target: Set<String>) {
        copyToPasteboard(torrents.filter { target.contains($0.id) }.map { torrent in
            let apiPath = torrent.column("content_path")
            return apiPath == "—" ? URL(fileURLWithPath: torrent.savePath, isDirectory: true).appending(path: torrent.name).path : apiPath
        }.joined(separator: "\n"))
    }

    private func copyComments(target: Set<String>) {
        let selected = torrents.filter { target.contains($0.id) }
        Task {
            do {
                let comments = try await withThrowingTaskGroup(of: (String, String).self) { group in
                    for torrent in selected {
                        group.addTask {
                            let details = try await store.properties(for: torrent.id)
                            return (torrent.id, details.comment ?? "")
                        }
                    }
                    var values: [String: String] = [:]
                    for try await (hash, comment) in group { values[hash] = comment }
                    return values
                }
                copyToPasteboard(selected.map { comments[$0.id] ?? "" }.joined(separator: "\n"))
            } catch { actionError = error.localizedDescription }
        }
    }

    private func copyMagnets(target: Set<String>) {
        let links = torrents.filter { target.contains($0.id) }.map { torrent -> String in
            var components = URLComponents()
            components.scheme = "magnet"
            var items = [URLQueryItem(name: "dn", value: torrent.name)]
            let v1 = torrent.column("infohash_v1")
            if v1 != "—" { items.append(URLQueryItem(name: "xt", value: "urn:btih:\(v1)")) }
            else if torrent.id.count == 40 { items.append(URLQueryItem(name: "xt", value: "urn:btih:\(torrent.id)")) }
            let v2 = torrent.column("infohash_v2")
            if v2 != "—" {
                let hash = v2.replacingOccurrences(of: "^1220", with: "", options: .regularExpression)
                items.append(URLQueryItem(name: "xt", value: "urn:btmh:1220\(hash)"))
            }
            components.queryItems = items
            return components.string ?? "magnet:?"
        }
        copyToPasteboard(links.joined(separator: "\n"))
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func isPreviewable(_ file: TorrentFile) -> Bool {
        TorrentFilePreview.isPreviewable(file.name)
    }

    private func handleTorrentDoubleClick(_ torrent: Torrent) {
        guard selectedTorrentIDs.count == 1, selectedTorrentIDs.contains(torrent.id) else { return }
        let actionValue = torrent.progress >= 1 ? completedDoubleClickAction : downloadingDoubleClickAction
        let action = TorrentDoubleClickAction(rawValue: actionValue) ?? (torrent.progress >= 1 ? .openDestination : .toggleStop)
        switch action {
        case .toggleStop:
            let command: TorrentCommand = ["stoppedUP", "stoppedDL"].contains(torrent.rawState) ? .start : .stop
            runBulkAction(hashes: [torrent.id]) { try await store.command(command, hashes: $0) }
        case .openDestination:
            openDestinationFolder(for: torrent)
        case .previewFile:
            openPreviewOrDestination(for: torrent)
        case .openOptions:
            torrentOptionsTarget = TorrentOptionsTarget(hashes: [torrent.id])
        case .none:
            break
        }
    }

    private func openDestinationFolder(for torrent: Torrent) {
        guard store.usesBundledBackend else {
            actionError = "The destination folder belongs to the remote server and cannot be opened in Finder."
            return
        }
        guard !torrent.savePath.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: torrent.savePath, isDirectory: true))
    }

    private func openPreviewOrDestination(for torrent: Torrent) {
        guard store.usesBundledBackend else {
            actionError = "Files belong to the remote server and cannot be opened in Mac apps."
            return
        }
        Task {
            do {
                let torrentFiles = try await store.files(for: torrent.id)
                if torrentFiles.contains(where: isPreviewable) {
                    previewTorrent = torrent
                } else {
                    openDestinationFolder(for: torrent)
                }
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func queuePreviews(for selectedTorrents: [Torrent]) {
        guard store.usesBundledBackend else {
            actionError = "Files belong to the remote server and cannot be opened in Mac apps."
            return
        }
        Task {
            var previewableTorrents: [Torrent] = []
            var unavailableNames: [String] = []
            for torrent in selectedTorrents {
                guard torrent.hasMetadata else {
                    unavailableNames.append(torrent.name)
                    continue
                }
                do {
                    let torrentFiles = try await store.files(for: torrent.id)
                    if torrentFiles.contains(where: isPreviewable) {
                        previewableTorrents.append(torrent)
                    } else {
                        unavailableNames.append(torrent.name)
                    }
                } catch {
                    unavailableNames.append("\(torrent.name): \(error.localizedDescription)")
                }
            }
            guard let first = previewableTorrents.first else {
                actionError = "No selected torrent contains a previewable file.\n\(unavailableNames.joined(separator: "\n"))"
                return
            }
            previewTorrentQueue = Array(previewableTorrents.dropFirst())
            previewTorrent = first
        }
    }

    private func presentNextPreview() {
        guard let next = previewTorrentQueue.first else { return }
        previewTorrentQueue.removeFirst()
        previewTorrent = next
    }

    private func torrentFileURL(_ file: TorrentFile, in torrent: Torrent) -> URL {
        URL(fileURLWithPath: torrent.savePath, isDirectory: true).appending(path: file.name)
    }

    private func torrentContentURL(_ row: TorrentContentRow, in torrent: Torrent) -> URL {
        URL(fileURLWithPath: torrent.savePath, isDirectory: true).appending(path: row.path)
    }

    private func torrentContentPath(_ relativePath: String, in torrent: Torrent) -> String {
        let root = torrent.savePath
        guard !root.isEmpty else { return relativePath }
        let separator = root.contains("\\") && !root.contains("/") ? "\\" : "/"
        let childPath = relativePath.replacingOccurrences(of: "/", with: separator)
        if root.hasSuffix("/") || root.hasSuffix("\\") { return root + childPath }
        return root + separator + childPath
    }

    private func torrentContentExists(_ row: TorrentContentRow, in torrent: Torrent) -> Bool {
        FileManager.default.fileExists(atPath: torrentContentURL(row, in: torrent).path)
    }

    private func openTorrentContentRow(_ row: TorrentContentRow, in torrent: Torrent) {
        guard store.usesBundledBackend else {
            actionError = "Files belong to the remote server and cannot be opened in Mac apps."
            return
        }
        let url = torrentContentURL(row, in: torrent)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openTorrentContentContainingFolder(_ row: TorrentContentRow, in torrent: Torrent) {
        guard store.usesBundledBackend else { return }
        let url = torrentContentURL(row, in: torrent)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func torrentFileExists(_ file: TorrentFile, in torrent: Torrent) -> Bool {
        FileManager.default.fileExists(atPath: torrentFileURL(file, in: torrent).path)
    }

    private func openTorrentFile(_ file: TorrentFile, in torrent: Torrent) {
        guard store.usesBundledBackend else {
            actionError = "Files belong to the remote server and cannot be opened in Mac apps."
            return
        }
        let url = torrentFileURL(file, in: torrent)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.open(url)
    }

    private func exportSelectedTorrents(hashes: [String]) {
        let selected = hashes.compactMap { hash in torrents.first(where: { $0.id == hash }) }
        guard !selected.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let directory = panel.url else { return }
            Task {
                var failures: [String] = []
                var reservedNames = Set<String>()
                for torrent in selected {
                    do {
                        let data = try await store.exportTorrent(torrent.id)
                        let invalidFilenameCharacters = CharacterSet(charactersIn: "/\\:?*|\"<>").union(.controlCharacters)
                        var sanitizedScalars = String.UnicodeScalarView()
                        for scalar in torrent.name.unicodeScalars {
                            sanitizedScalars.append(invalidFilenameCharacters.contains(scalar) ? "_" : scalar)
                        }
                        let baseName = String(sanitizedScalars).trimmingCharacters(in: .whitespacesAndNewlines)
                        let stem = baseName.isEmpty ? torrent.id : baseName
                        var filename = "\(stem).torrent"
                        var counter = 0
                        while reservedNames.contains(filename.lowercased()) || FileManager.default.fileExists(atPath: directory.appendingPathComponent(filename).path) {
                            counter += 1
                            filename = "\(stem) (\(counter)).torrent"
                        }
                        reservedNames.insert(filename.lowercased())
                        try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
                    } catch {
                        failures.append("\(torrent.name): \(error.localizedDescription)")
                    }
                }
                if !failures.isEmpty {
                    actionError = "Some torrent files could not be exported:\n\(failures.joined(separator: "\n"))"
                }
            }
        }
    }
}

private struct DetailInput: Identifiable {
    enum Operation: Equatable {
        case addTracker, editTracker(String), addWebSeed, editWebSeed(String), addPeer, renameFile(String)
    }
    let id = UUID()
    let hash: String
    let operation: Operation
    let title: String
    let hint: String
    let initialValue: String
}

private enum PeerAddressInputError: LocalizedError {
    case noPeers
    case invalidPeer(String)

    var errorDescription: String? {
        switch self {
        case .noPeers: "Please enter at least one peer."
        case let .invalidPeer(peer): "The peer ‘\(peer)’ is invalid. Use IPv4:port or [IPv6]:port."
        }
    }
}

private struct TrackerBatchEditorTarget: Identifiable {
    let id = UUID()
    let hashes: [String]
}

private struct TrackerBatchEntry: Identifiable {
    let id = UUID()
    var url: String
    var tier: Int
}

private struct TrackerBatchEditor: View {
    @Environment(\.dismiss) private var dismiss
    let store: TorrentStore
    let hashes: [String]
    @State private var entries: [TrackerBatchEntry] = []
    @State private var isLoading = true
    @State private var hasLoadedTrackers = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var validEntries: [TrackerBatchEntry] {
        var seenURLs = Set<String>()
        return entries.compactMap { entry in
            let url = entry.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty, seenURLs.insert(url).inserted else { return nil }
            return TrackerBatchEntry(url: url, tier: entry.tier)
        }
    }

    private var hasInvalidEntries: Bool {
        entries.contains { entry in
            let value = entry.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return false }
            guard let components = URLComponents(string: value) else { return true }
            return components.scheme == nil || components.host == nil || (0...255).contains(entry.tier) == false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Trackers common to the selected torrents are shown here. Saving replaces each selected torrent’s tracker list with this list.")
                .font(.subheadline).foregroundStyle(.secondary)

            if isLoading {
                ProgressView("Loading trackers…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    Section("Tracker URLs") {
                        if entries.isEmpty {
                            Text("No trackers are common to every selected torrent.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach($entries) { $entry in
                            HStack(spacing: 10) {
                                TextField("https://tracker.example/announce", text: $entry.url)
                                Stepper("Tier \(entry.tier + 1)", value: $entry.tier, in: 0...255)
                                    .frame(width: 130)
                                Button(role: .destructive) {
                                    entries.removeAll { $0.id == entry.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .help("Remove tracker")
                                .accessibilityLabel("Remove tracker")
                            }
                        }
                        Button("Add Tracker") { entries.append(TrackerBatchEntry(url: "", tier: 0)) }
                    }
                }
                .formStyle(.grouped)
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { Task { await save() } }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isLoading || !hasLoadedTrackers || isSaving || hasInvalidEntries)
            }
        }
        .padding(22)
        .frame(minWidth: 660, idealWidth: 760, minHeight: 430, idealHeight: 520)
        .task { await loadCommonTrackers() }
    }

    private func loadCommonTrackers() async {
        do {
            var trackersByTorrent: [[TorrentTracker]] = []
            for hash in hashes {
                trackersByTorrent.append(try await store.trackers(for: hash).filter { ($0.tier ?? -1) >= 0 })
            }
            guard let first = trackersByTorrent.first else {
                entries = []
                isLoading = false
                return
            }
            var seenURLs = Set<String>()
            entries = first.compactMap { tracker in
                guard seenURLs.insert(tracker.url).inserted,
                      trackersByTorrent.dropFirst().allSatisfy({ list in list.contains { $0.url == tracker.url } }) else { return nil }
                return TrackerBatchEntry(url: tracker.url, tier: max(0, tracker.tier ?? 0))
            }
            hasLoadedTrackers = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            var existingURLs = Set<String>()
            for hash in hashes {
                let trackers = try await store.trackers(for: hash)
                existingURLs.formUnion(trackers.filter { ($0.tier ?? -1) >= 0 }.map(\.url))
            }
            try await store.removeTrackers(hashes: hashes, urls: Array(existingURLs))

            let trackers = validEntries
            if !trackers.isEmpty {
                let maximumTier = trackers.map(\.tier).max() ?? 0
                var lines: [String] = []
                for tier in 0...maximumTier {
                    if tier > 0 { lines.append("") }
                    lines.append(contentsOf: trackers.filter { $0.tier == tier }.map(\.url))
                }
                try await store.addTrackers(hashes: hashes, entries: lines.joined(separator: "\n"))
            }
            dismiss()
        } catch {
            errorMessage = "Tracker changes could not be fully applied: \(error.localizedDescription)"
            isSaving = false
        }
    }
}

private enum TorrentTextAction: String, Identifiable {
    case rename, location, category, tags
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rename: "Rename Torrent"
        case .location: "Set Torrent Location"
        case .category: "Set Category"
        case .tags: "Set Tags"
        }
    }
    var hint: String {
        switch self {
        case .rename: "Torrent name"
        case .location: "Destination folder path"
        case .category: "Existing category name, or leave blank to clear"
        case .tags: "Comma-separated tags, or leave blank to clear"
        }
    }
}

private struct ValueSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let hint: String
    let allowsEmpty: Bool
    let allowsMultiline: Bool
    let pathStore: TorrentStore?
    let onApply: (String) async throws -> Void
    @State private var value: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(title: String, hint: String, initialValue: String, allowsEmpty: Bool = false, allowsMultiline: Bool = false, pathStore: TorrentStore? = nil, onApply: @escaping (String) async throws -> Void) {
        self.title = title
        self.hint = hint
        self.allowsEmpty = allowsEmpty
        self.allowsMultiline = allowsMultiline
        self.pathStore = pathStore
        self.onApply = onApply
        _value = State(initialValue: initialValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizedStringKey(title)).font(.title2.weight(.semibold))
            if allowsMultiline {
                TextEditor(text: $value)
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(5)
                    .frame(minHeight: 140)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
                Text("Enter one peer per line. IPv6 addresses must use brackets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    TextField(hint, text: $value).textFieldStyle(.roundedBorder)
                    if let pathStore {
                        ServerPathBrowserButton(store: pathStore, path: $value, kind: .directory)
                    }
                }
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") {
                    isSaving = true
                    Task {
                        do {
                            try await onApply(value.trimmingCharacters(in: .whitespacesAndNewlines))
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                            isSaving = false
                        }
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(isSaving || (!allowsEmpty && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: allowsMultiline ? 520 : 480)
    }
}

struct PendingTorrentFile: Identifiable {
    let id = UUID()
    let name: String
    let data: Data
    let sourceURL: URL?
}

private func filePathMatches(_ path: String, pattern: String, mode: String) -> Bool {
    switch mode {
    case "regex":
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        return regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
    case "wildcards":
        let expression = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        guard let regex = try? NSRegularExpression(pattern: expression, options: [.caseInsensitive]) else { return false }
        return regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
    default:
        return path.localizedCaseInsensitiveContains(pattern)
    }
}

private func removeLocalTorrentSource(_ file: PendingTorrentFile) throws {
    guard let url = file.sourceURL else { return }
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    try TorrentSourceFileSupport.removeIfUnchanged(at: url, matching: file.data)
}

private struct AddTorrentPathProfile: Codable {
    var lastSavePath = ""
    var savePathHistory: [String] = []
    var incompletePathHistory: [String] = []
}

private struct ToolbarLabelStyle: LabelStyle {
    let style: String

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        switch style {
        case "icons": configuration.icon
        case "text": configuration.title
        case "below": VStack(spacing: 3) { configuration.icon; configuration.title }
        default: HStack(spacing: 5) { configuration.icon; configuration.title }
        }
    }
}

private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    let serverVersion: String
    private var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Preview" }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 42)).foregroundStyle(.tint)
            Text("qBitX").font(.largeTitle.weight(.semibold))
            Text("Native macOS interface for qBittorrent")
                .foregroundStyle(.secondary)
            Text("qBitX \(appVersion) · qBittorrent \(serverVersion)")
                .font(.caption).foregroundStyle(.secondary)
            Link("qBitX on GitHub", destination: URL(string: "https://github.com/AndreaCodinLife/qBittorrent")!)
            Button("Done") { dismiss() }.buttonStyle(.glass).keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 380)
    }
}

struct AddTorrentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("qBitX.addTorrentDefaultCategory") private var defaultCategory = ""
    @AppStorage("qBitX.addTorrent.rememberLastSavePath") private var rememberLastSavePath = false
    @AppStorage("qBitX.addTorrent.pathProfiles") private var pathProfilesJSON = "{}"
    @AppStorage("qBitX.addTorrent.fileFilterMode") private var fileFilterMode = "wildcards"
    @AppStorage("qBitX.autoDeleteTorrentFileMode") private var autoDeleteTorrentFileMode = 0
    @AppStorage("qBitX.confirmMergeTrackers") private var confirmMergeTrackers = true
    let file: PendingTorrentFile?
    let store: TorrentStore
    let showOptions: Bool
    let initialURL: String
    let initialDownloader: String?
    let onAdd: (String, String?, TorrentAddOptions) async throws -> Bool
    @State private var url = ""
    @State private var savePath = ""
    @State private var downloadPathEnabled = false
    @State private var downloadPath = ""
    @State private var category = ""
    @State private var rename = ""
    @State private var setDefaultCategory = false
    @State private var tags = ""
    @State private var stopped = false
    @State private var sequential = false
    @State private var firstLastPiece = false
    @State private var automaticManagement = false
    @State private var addToQueueTop = false
    @State private var seedMode = false
    @State private var stopCondition = "None"
    @State private var contentLayout = "Original"
    @State private var downloadLimit = 0
    @State private var uploadLimit = 0
    @State private var metadata: TorrentMetadata?
    @State private var metadataSource: String?
    @State private var filePriorities: [Int] = []
    @State private var renamedFilePaths: [String: String] = [:]
    @State private var fileFilter = ""
    @State private var isLoadingMetadata = false
    @State private var errorMessage: String?
    @State private var isAdding = false
    @State private var isLoadingDefaults = true
    @State private var serverDefaultAddOptions = TorrentAddOptions()
    @State private var serverFreeSpace: Int64?
    @State private var didAddTorrent = false
    @State private var keepTorrentSourceFile = false
    @State private var pendingDuplicateTorrent: PendingDuplicateTorrent?
    @State private var isMergingDuplicate = false

    init(file: PendingTorrentFile?, store: TorrentStore, initialURL: String = "", initialDownloader: String? = nil, showOptions: Bool = true, onAdd: @escaping (String, String?, TorrentAddOptions) async throws -> Bool) {
        self.file = file
        self.store = store
        self.showOptions = showOptions
        self.initialURL = initialURL
        self.initialDownloader = initialDownloader
        self.onAdd = onAdd
        _url = State(initialValue: initialURL)
    }

    private var files: [TorrentMetadataFile] { metadata?.info?.files ?? [] }
    private var currentMetadata: TorrentMetadata? {
        guard let metadata else { return nil }
        guard file != nil || metadataSource == url.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return metadata
    }
    private var filteredFileIndices: [Int] {
        files.indices.filter { fileFilter.isEmpty || matchesFileFilter(files[$0].path, pattern: fileFilter) }
    }
    private var selectedFilesSize: Int64 {
        files.indices.reduce(into: Int64(0)) { total, index in
            if filePriorities.indices.contains(index), filePriorities[index] > 0 {
                total += files[index].length
            }
        }
    }
    private var hasInvalidRenamedFilePaths: Bool {
        renamedFilePaths.values.contains { path in
            path.isEmpty || path.hasPrefix("/") || path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
        }
    }
    private var savePathHistory: [String] {
        currentPathProfile.savePathHistory
    }
    private var currentFreeSpace: Int64? {
        store.usesBundledBackend ? availableDiskSpace(for: savePath) : serverFreeSpace
    }
    private var incompletePathHistory: [String] {
        currentPathProfile.incompletePathHistory
    }
    private var currentPathProfile: AddTorrentPathProfile {
        pathProfiles[pathProfileKey] ?? AddTorrentPathProfile()
    }
    private var pathProfiles: [String: AddTorrentPathProfile] {
        guard let data = pathProfilesJSON.data(using: .utf8),
              let profiles = try? JSONDecoder().decode([String: AddTorrentPathProfile].self, from: data) else { return [:] }
        return profiles
    }
    private var pathProfileKey: String {
        guard let saved = SavedRemoteConnection.load() else { return "local-library" }
        guard var components = URLComponents(string: saved.address) else { return "remote:\(saved.address)" }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        return components.string ?? "remote:\(saved.address)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(file == nil ? "Add Torrent URL" : "Add Torrent File")
                        .font(.title2.weight(.semibold))
                    Text(file?.name ?? "Enter a magnet link or a URL to a .torrent file.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if file == nil && showOptions {
                    Button("Load Content") { Task { await loadMetadata() } }
                        .buttonStyle(.glass)
                        .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingMetadata)
                }
            }
            if file == nil {
                TextField("magnet:?xt=… or https://…", text: $url)
                    .textFieldStyle(.roundedBorder)
            }
            if showOptions {
                HStack(alignment: .top, spacing: 14) {
                Form {
                    Section("Location and organization") {
                        HStack {
                            TextField("Save location", text: $savePath, prompt: Text("Backend default"))
                                .disabled(automaticManagement)
                            if !savePathHistory.isEmpty {
                                Menu {
                                    ForEach(savePathHistory, id: \.self) { path in
                                        Button(path) { savePath = path }
                                    }
                                } label: {
                                    Image(systemName: "clock.arrow.circlepath")
                                }
                                .help("Recent save locations")
                            }
                            ServerPathBrowserButton(store: store, path: $savePath, kind: .directory)
                                .disabled(automaticManagement)
                        }
                        Toggle("Use another path for incomplete torrents", isOn: $downloadPathEnabled)
                            .disabled(automaticManagement)
                        if downloadPathEnabled {
                            HStack {
                                TextField("Incomplete save path", text: $downloadPath)
                                    .disabled(automaticManagement)
                                if !incompletePathHistory.isEmpty {
                                    Menu {
                                        ForEach(incompletePathHistory, id: \.self) { path in
                                            Button(path) { downloadPath = path }
                                        }
                                    } label: {
                                        Image(systemName: "clock.arrow.circlepath")
                                    }
                                    .help("Recent incomplete save locations")
                                }
                                ServerPathBrowserButton(store: store, path: $downloadPath, kind: .directory)
                                    .disabled(automaticManagement)
                            }
                        }
                        Toggle("Remember last used save location", isOn: $rememberLastSavePath)
                            .disabled(automaticManagement)
                        TextField("Rename torrent", text: $rename, prompt: Text("Keep original name"))
                        TextField("Category", text: $category)
                        Toggle("Set as default category", isOn: $setDefaultCategory)
                        TextField("Tags (comma separated)", text: $tags)
                    }
                    Section("Download behavior") {
                        Toggle("Add stopped", isOn: $stopped)
                        Toggle("Automatic torrent management", isOn: $automaticManagement)
                        Toggle("Add to top of queue", isOn: $addToQueueTop)
                        Toggle("Seed mode", isOn: $seedMode)
                        Toggle("Download in sequential order", isOn: $sequential)
                        Toggle("Prioritize first and last pieces", isOn: $firstLastPiece)
                        if file?.sourceURL != nil && autoDeleteTorrentFileMode > 0 {
                            Toggle("Keep source .torrent file", isOn: $keepTorrentSourceFile)
                                .help("Keep this file even when qBitX is set to delete .torrent sources after adding.")
                        }
                        Picker("Stop condition", selection: $stopCondition) {
                            Text("None").tag("None")
                            Text("Metadata received").tag("MetadataReceived")
                            Text("Files checked").tag("FilesChecked")
                        }
                        Picker("Content layout", selection: $contentLayout) {
                            Text("Original").tag("Original")
                            Text("Create subfolder").tag("Subfolder")
                            Text("Don’t create subfolder").tag("NoSubfolder")
                        }
                    }
                    Section("Transfer limits") {
                        TextField("Download limit (KiB/s; 0 = unlimited)", value: $downloadLimit, format: .number)
                        TextField("Upload limit (KiB/s; 0 = unlimited)", value: $uploadLimit, format: .number)
                    }
                }
                .formStyle(.grouped)
                .frame(width: 440)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Files").font(.headline)
                        Spacer()
                        if !files.isEmpty { Text("\(files.count) files").font(.caption).foregroundStyle(.secondary) }
                    }
                    if let metadata {
                        VStack(alignment: .leading, spacing: 3) {
                            if let totalSize = metadata.info?.length {
                                Text("Torrent size: \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))")
                                    .font(.caption)
                            }
                            Text("Selected size: \(ByteCountFormatter.string(fromByteCount: selectedFilesSize, countStyle: .file))")
                                .font(.caption.weight(.medium))
                            if let freeSpace = currentFreeSpace {
                                Text("Free space: \(ByteCountFormatter.string(fromByteCount: freeSpace, countStyle: .file))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text("Created: \(metadata.creation_date.map { Date(timeIntervalSince1970: TimeInterval($0)).formatted(date: .numeric, time: .shortened) } ?? "Not available")")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Info hash v1: \(metadata.infohash_v1 ?? "Not available")")
                                .font(.caption2.monospaced()).textSelection(.enabled).lineLimit(1)
                            Text("Info hash v2: \(metadata.infohash_v2 ?? "Not available")")
                                .font(.caption2.monospaced()).textSelection(.enabled).lineLimit(1)
                            if let comment = metadata.comment, !comment.isEmpty {
                                Text("Comment: \(comment)")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    if !files.isEmpty {
                        HStack {
                            TextField("Filter files…", text: $fileFilter)
                                .textFieldStyle(.roundedBorder)
                            Menu {
                                Picker("Match", selection: $fileFilterMode) {
                                    Text("Plain text").tag("plain")
                                    Text("Wildcards").tag("wildcards")
                                    Text("Regular expression").tag("regex")
                                }
                            } label: {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                            }
                            .help("Choose file filter pattern")
                        }
                        HStack(spacing: 10) {
                            Button("Select All") { filePriorities = Array(repeating: 1, count: files.count) }
                            Button("Select None") { filePriorities = Array(repeating: 0, count: files.count) }
                            Spacer()
                        }
                        List {
                            ForEach(filteredFileIndices, id: \.self) { index in
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        TextField(files[index].path, text: Binding(
                                            get: { renamedFilePaths[files[index].path] ?? files[index].path },
                                            set: { renamedFilePaths[files[index].path] = $0 }
                                        ))
                                        .textFieldStyle(.plain)
                                        .lineLimit(1)
                                        Text(ByteCountFormatter.string(fromByteCount: files[index].length, countStyle: .file))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 6)
                                    Picker("Priority", selection: Binding(
                                        get: { filePriorities.indices.contains(index) ? filePriorities[index] : 1 },
                                        set: { if filePriorities.indices.contains(index) { filePriorities[index] = $0 } }
                                    )) {
                                        Text("Skip").tag(0)
                                        Text("Normal").tag(1)
                                        Text("High").tag(6)
                                        Text("Maximum").tag(7)
                                    }
                                    .labelsHidden()
                                    .frame(width: 100)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                        .listStyle(.inset)
                    } else if isLoadingMetadata {
                        ContentUnavailableView {
                            ProgressView("Loading torrent metadata…")
                        }
                    } else {
                        ContentUnavailableView("No File List", systemImage: "doc.text.magnifyingglass", description: Text(file == nil ? "Load metadata to preview files and set priorities before adding." : "Torrent metadata could not be loaded."))
                    }
                    if hasInvalidRenamedFilePaths {
                        Text("File names must stay inside the torrent’s folder.")
                            .font(.caption).foregroundStyle(.red)
                    }
                    if let metadata {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(metadata.info?.name ?? "Torrent metadata").font(.caption.weight(.semibold)).lineLimit(1)
                            Text("\(metadata.infohash_v1 ?? metadata.infohash_v2 ?? metadata.id ?? "") · \(files.count) files")
                                .font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                            Button("Save as .torrent…") { saveMetadata() }
                                .buttonStyle(.link)
                        }
                    }
                }
                .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(height: 505)
                .disabled(isLoadingDefaults)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.tint)
                    Text("This torrent will use the server’s default download settings.")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text("You can change the default download folder and behavior in qBittorrent Preferences.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 190)
            }
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
            HStack {
                Spacer()
                Button("Cancel", action: cancelAdd).keyboardShortcut(.cancelAction).disabled(isAdding)
                Button(didAddTorrent ? "Done" : "Add Torrent") {
                    if didAddTorrent { dismiss(); return }
                    isAdding = true
                    Task {
                        do {
                            var options = showOptions ? serverDefaultAddOptions : try await store.defaultTorrentAddOptions()
                            if showOptions {
                                options.savePath = savePath.trimmingCharacters(in: .whitespacesAndNewlines)
                                options.downloadPathEnabled = downloadPathEnabled && !automaticManagement
                                options.downloadPath = downloadPath.trimmingCharacters(in: .whitespacesAndNewlines)
                                options.category = category.trimmingCharacters(in: .whitespacesAndNewlines)
                                options.rename = rename.trimmingCharacters(in: .whitespacesAndNewlines)
                                options.tags = tags.trimmingCharacters(in: .whitespacesAndNewlines)
                                options.stopped = stopped
                                options.automaticManagement = automaticManagement
                                options.addToQueueTop = addToQueueTop
                                options.seedMode = seedMode
                                options.sequential = sequential
                                options.firstLastPiece = firstLastPiece
                                options.stopCondition = stopCondition
                                options.contentLayout = contentLayout
                                options.downloadLimitKiB = max(0, downloadLimit)
                                options.uploadLimitKiB = max(0, uploadLimit)
                                options.filePriorities = files.isEmpty ? nil : filePriorities
                            } else if options.category.isEmpty {
                                options.category = defaultCategory
                            }
                            let source = file == nil ? url.trimmingCharacters(in: .whitespacesAndNewlines) : (currentMetadata?.magnetURI ?? "")
                            var duplicateMetadata = currentMetadata ?? TorrentMetadata.fromMagnetURI(source)
                            if showOptions, confirmMergeTrackers, file == nil, duplicateMetadata == nil, !source.isEmpty {
                                do {
                                    let fetched = try await store.fetchTorrentMetadata(source: source, downloader: initialDownloader)
                                    guard source == url.trimmingCharacters(in: .whitespacesAndNewlines) else {
                                        isAdding = false
                                        return
                                    }
                                    metadata = fetched
                                    metadataSource = source
                                    filePriorities = (fetched.info?.files ?? []).map { $0.priority ?? 1 }
                                    duplicateMetadata = fetched
                                } catch {
                                    // Metadata preview is optional for adding; let the server handle sources it cannot parse here.
                                }
                            }
                            if showOptions, confirmMergeTrackers,
                               let metadata = duplicateMetadata,
                               let duplicate = matchingTorrent(for: metadata) {
                                let duplicateIsPrivate = metadata.info?.privateTorrent == true
                                    || ["yes", "true", "1"].contains(duplicate.column("private").lowercased())
                                pendingDuplicateTorrent = PendingDuplicateTorrent(
                                    id: duplicate.id,
                                    name: duplicate.name,
                                    isPrivate: duplicateIsPrivate,
                                    mergeByDefault: serverDefaultAddOptions.mergeTrackersByDefault,
                                    trackers: metadata.trackers ?? [],
                                    webSeeds: metadata.webseeds ?? []
                                )
                                keepTorrentSourceFile = true
                                isAdding = false
                                return
                            }
                            let torrentWasAdded = try await onAdd(source, initialDownloader, options)
                            if setDefaultCategory { defaultCategory = options.category }
                            didAddTorrent = true
                            if torrentWasAdded, autoDeleteTorrentFileMode > 0, !keepTorrentSourceFile, let file {
                                do { try removeLocalTorrentSource(file) }
                                catch {
                                    errorMessage = "The torrent was added, but qBitX could not delete its source file: \(error.localizedDescription)"
                                    isAdding = false
                                    return
                                }
                            }
                            if let hash = metadata?.id ?? metadata?.infohash_v1 ?? metadata?.infohash_v2 {
                                do {
                                    for item in files {
                                        guard let newPath = renamedFilePaths[item.path], newPath != item.path else { continue }
                                        try await store.renameFile(hash: hash, oldPath: item.path, newPath: newPath)
                                    }
                                } catch {
                                    errorMessage = "The torrent was added, but a file could not be renamed: \(error.localizedDescription)"
                                    isAdding = false
                                    return
                                }
                            }
                            rememberSaveLocationIfNeeded()
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                            isAdding = false
                        }
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(!didAddTorrent && !isReadyToAdd)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(25)
        .frame(minWidth: showOptions ? 900 : 460, idealWidth: showOptions ? 980 : 520, minHeight: showOptions ? 690 : 370, idealHeight: showOptions ? 760 : 430)
        .confirmationDialog("Torrent is Already Present", isPresented: Binding(
            get: { pendingDuplicateTorrent.map { !$0.isPrivate } ?? false },
            set: { isPresented in
                if !isPresented, pendingDuplicateTorrent != nil, !isMergingDuplicate {
                    finishDuplicateWithoutMerging()
                }
            }
        ), titleVisibility: .visible) {
            if pendingDuplicateTorrent?.mergeByDefault == true {
                Button("Merge Trackers and Web Seeds") { mergeDuplicateSource() }
                    .keyboardShortcut(.defaultAction)
                Button("Don't Merge", role: .cancel) { finishDuplicateWithoutMerging() }
            } else {
                Button("Merge Trackers and Web Seeds") { mergeDuplicateSource() }
                Button("Don't Merge", role: .cancel) { finishDuplicateWithoutMerging() }
                    .keyboardShortcut(.defaultAction)
            }
        } message: {
            Text("‘\(pendingDuplicateTorrent?.name ?? "This torrent")’ is already in the transfer list. Merge trackers and web seeds from the new source?")
        }
        .alert("Torrent is Already Present", isPresented: Binding(
            get: { pendingDuplicateTorrent?.isPrivate == true },
            set: { isPresented in
                if !isPresented, pendingDuplicateTorrent?.isPrivate == true {
                    finishDuplicateWithoutMerging()
                }
            }
        )) {
            Button("OK", role: .cancel) { finishDuplicateWithoutMerging() }
        } message: {
            Text("Trackers cannot be merged because ‘\(pendingDuplicateTorrent?.name ?? "this torrent")’ is private.")
        }
        .onChange(of: url) { _, newValue in
            guard file == nil, metadataSource != newValue.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            metadata = nil
            metadataSource = nil
            filePriorities = []
            renamedFilePaths = [:]
        }
        .task {
            await loadServerDefaults()
            if showOptions && (file != nil || !initialURL.isEmpty) { await loadMetadata() }
        }
        .task(id: savePath) { await refreshServerFreeSpace(at: savePath) }
        .onDisappear {
            if !didAddTorrent, autoDeleteTorrentFileMode == 2, !keepTorrentSourceFile, let file {
                try? removeLocalTorrentSource(file)
            }
        }
    }

    private func matchingTorrent(for metadata: TorrentMetadata) -> Torrent? {
        let incomingHashes = [metadata.id, metadata.infohash_v1, metadata.infohash_v2]
            .compactMap { $0?.lowercased() }
            .filter { !$0.isEmpty }
        guard !incomingHashes.isEmpty else { return nil }
        return store.torrents.first { torrent in
            let existingHashes = [torrent.id, torrent.column("infohash_v1"), torrent.column("infohash_v2")]
                .map { $0.lowercased() }
                .filter { !$0.isEmpty && $0 != "—" }
            return existingHashes.contains { incomingHashes.contains($0) }
        }
    }

    private func finishDuplicateWithoutMerging() {
        keepTorrentSourceFile = true
        pendingDuplicateTorrent = nil
        isAdding = false
        isMergingDuplicate = false
        dismiss()
    }

    private func mergeDuplicateSource() {
        guard let duplicate = pendingDuplicateTorrent else { return }
        isMergingDuplicate = true
        isAdding = true
        Task {
            do {
                let existingTrackers = Set(try await store.trackers(for: duplicate.id).map(\.url))
                var trackersByTier: [Int: [String]] = [:]
                for tracker in duplicate.trackers where !existingTrackers.contains(tracker.url) {
                    trackersByTier[tracker.tier ?? 0, default: []].append(tracker.url)
                }
                let trackerEntries: String
                if let lastTier = trackersByTier.keys.max() {
                    var lines: [String] = []
                    for tier in 0...lastTier {
                        if tier > 0 { lines.append("") }
                        lines.append(contentsOf: trackersByTier[tier] ?? [])
                    }
                    trackerEntries = lines.joined(separator: "\n")
                } else {
                    trackerEntries = ""
                }
                if !trackerEntries.isEmpty {
                    try await store.addTrackers(hashes: [duplicate.id], entries: trackerEntries)
                }

                let existingWebSeeds = Set(try await store.webSeeds(for: duplicate.id).map(\.url))
                for url in Set(duplicate.webSeeds).subtracting(existingWebSeeds).sorted() {
                    try await store.addWebSeed(hash: duplicate.id, url: url)
                }
                await store.refresh()
                pendingDuplicateTorrent = nil
                isAdding = false
                isMergingDuplicate = false
                dismiss()
            } catch {
                pendingDuplicateTorrent = nil
                isAdding = false
                isMergingDuplicate = false
                errorMessage = "Could not merge trackers and web seeds: \(error.localizedDescription)"
            }
        }
    }

    private var isReadyToAdd: Bool {
        !isLoadingDefaults
            && !(showOptions && confirmMergeTrackers && file != nil && isLoadingMetadata)
            && !(file == nil && url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && !isAdding
            && !hasInvalidRenamedFilePaths
            && (!showOptions || ((0...1_000_000).contains(downloadLimit) && (0...1_000_000).contains(uploadLimit)))
    }

    private func cancelAdd() {
        if autoDeleteTorrentFileMode == 2, !keepTorrentSourceFile, let file {
            do { try removeLocalTorrentSource(file) }
            catch {
                errorMessage = "qBitX could not delete the cancelled torrent source: \(error.localizedDescription)"
                return
            }
        }
        dismiss()
    }

    private func loadServerDefaults() async {
        do {
            let options = try await store.defaultTorrentAddOptions()
            serverDefaultAddOptions = options
            if showOptions {
                savePath = options.savePath
                downloadPathEnabled = options.downloadPathEnabled
                downloadPath = options.downloadPath
                category = defaultCategory.isEmpty ? options.category : defaultCategory
                stopped = options.stopped
                automaticManagement = options.automaticManagement
                addToQueueTop = options.addToQueueTop
                stopCondition = options.stopCondition
                contentLayout = options.contentLayout
                if rememberLastSavePath, !currentPathProfile.lastSavePath.isEmpty { savePath = currentPathProfile.lastSavePath }
                if rememberLastSavePath, let recentIncompletePath = incompletePathHistory.first {
                    downloadPath = recentIncompletePath
                }
            }
        } catch {
            errorMessage = "Could not load the server’s default torrent settings: \(error.localizedDescription)"
            if showOptions, category.isEmpty { category = defaultCategory }
        }
        isLoadingDefaults = false
    }

    private func matchesFileFilter(_ path: String, pattern: String) -> Bool {
        filePathMatches(path, pattern: pattern, mode: fileFilterMode)
    }

    private func availableDiskSpace(for path: String) -> Int64? {
        guard store.usesBundledBackend, !path.isEmpty else { return nil }
        var current = URL(fileURLWithPath: path, isDirectory: true)
        while true {
            if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: current.path),
               let freeSpace = attributes[.systemFreeSize] as? NSNumber {
                return freeSpace.int64Value
            }
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { return nil }
            current = parent
        }
    }

    private func refreshServerFreeSpace(at path: String) async {
        guard !store.usesBundledBackend, !path.isEmpty else {
            serverFreeSpace = nil
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(350))
            serverFreeSpace = try await store.freeSpace(at: path)
        } catch is CancellationError {
        } catch {
            serverFreeSpace = nil
        }
    }

    private func rememberSaveLocationIfNeeded() {
        guard showOptions, !automaticManagement else { return }
        let path = savePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        var profile = currentPathProfile
        if rememberLastSavePath { profile.lastSavePath = path }
        profile.savePathHistory = updatedPathHistory(savePath, priorHistory: profile.savePathHistory)
        if downloadPathEnabled {
            profile.incompletePathHistory = updatedPathHistory(downloadPath, priorHistory: profile.incompletePathHistory)
        }
        var profiles = pathProfiles
        profiles[pathProfileKey] = profile
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        pathProfilesJSON = String(decoding: data, as: UTF8.self)
    }

    private func updatedPathHistory(_ path: String, priorHistory: [String]) -> [String] {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return priorHistory }
        var history = priorHistory.filter { $0 != trimmedPath }
        history.insert(trimmedPath, at: 0)
        if history.count > 20 { history.removeLast(history.count - 20) }
        return history
    }

    private func loadMetadata() async {
        guard !isLoadingMetadata else { return }
        let requestedSource = url.trimmingCharacters(in: .whitespacesAndNewlines)
        isLoadingMetadata = true
        errorMessage = nil
        defer { isLoadingMetadata = false }
        do {
            let fetched: TorrentMetadata
            if let file {
                fetched = try await store.parseTorrentMetadata(file: file.data, filename: file.name)
            } else {
                fetched = try await store.fetchTorrentMetadata(source: requestedSource, downloader: initialDownloader)
                guard requestedSource == url.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            }
            metadata = fetched
            metadataSource = file == nil ? requestedSource : nil
            filePriorities = (fetched.info?.files ?? []).map { $0.priority ?? 1 }
        } catch { errorMessage = error.localizedDescription }
    }

    private func saveMetadata() {
        guard let metadata = currentMetadata else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "torrent") ?? .data]
        panel.nameFieldStringValue = (metadata.info?.name ?? "torrent") + ".torrent"
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            let source = file == nil ? url.trimmingCharacters(in: .whitespacesAndNewlines) : (metadata.magnetURI ?? "")
            Task {
                do { try await store.saveTorrentMetadata(source: source).write(to: destination, options: .atomic) }
                catch { errorMessage = error.localizedDescription }
            }
        }
    }
}
