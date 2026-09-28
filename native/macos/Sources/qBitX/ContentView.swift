import SwiftUI
import Charts
import UniformTypeIdentifiers
import LocalAuthentication

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

struct ContentView: View {
    @Bindable var store: TorrentStore
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
    @AppStorage("qBitX.doubleClick.downloading") private var downloadingDoubleClickAction = TorrentDoubleClickAction.toggleStop.rawValue
    @AppStorage("qBitX.doubleClick.completed") private var completedDoubleClickAction = TorrentDoubleClickAction.openDestination.rawValue
    @AppStorage("qBitX.hideZeroValues") private var hideZeroValues = false
    @AppStorage("qBitX.hideZeroValuesMode") private var hideZeroValuesMode = "always"
    @AppStorage("qBitX.confirmTorrentDeletion") private var confirmTorrentDeletion = true
    @AppStorage("qBitX.startMinimized") private var startMinimized = false
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
    @State private var selectedTorrentIDs: Set<String> = []
    @SceneStorage("qBitX.transferColumns") private var columnCustomization = TableColumnCustomization<Torrent>()
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
    @State private var showsFileImporter = false
    @State private var pendingTorrentFile: PendingTorrentFile?
    @State private var showsRemoveConfirmation = false
    @State private var showsClearTagsConfirmation = false
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
    @State private var showsOrganization = false
    @State private var organizationInitialCategory: String?
    @State private var showsAbout = false
    @State private var showsFileAssociations = false
    @State private var previewTorrent: Torrent?
    @State private var authenticationError: String?
    @State private var incompleteDownloadIDs: Set<String> = []
    @State private var showsDownloadCompletionAction = false
    @State private var actionError: String?
    @State private var retryID = 0
    @State private var properties: TorrentProperties?
    @State private var pieceStates: [Int] = []
    @State private var pieceAvailability: [Int] = []
    @State private var trackers: [TorrentTracker] = []
    @State private var categoryCatalog: Set<String> = []
    @State private var tagCatalog: Set<String> = []
    @State private var files: [TorrentFile] = []
    @State private var peers: [TorrentPeer] = []
    @State private var webSeeds: [TorrentWebSeed] = []
    @State private var selectedFileIDs: Set<Int> = []

    private var torrents: [Torrent] { store.torrents }

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
        case "uploading", "forcedUP": .green
        case "stalledUP", "stalledDL": .orange
        case "stoppedUP", "stoppedDL", "queuedUP", "queuedDL": .gray
        case "checkingUP", "checkingDL", "checkingResumeData", "moving": .purple
        case "error", "missingFiles": .red
        default: .blue
        }
    }

    private var selectedTorrent: Torrent? {
        torrents.first { $0.id == selectedTorrentID }
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
                switch mainTab {
                case .transfers:
                    if showDetailPane {
                        VSplitView {
                            torrentTable.frame(minHeight: 240)
                            detailsPane.frame(minHeight: 170)
                        }
                    } else {
                        torrentTable
                    }
                case .search:
                    SearchPane(store: store)
                case .rss:
                    RSSPane(store: store)
                }
                if showStatusBar {
                    Divider()
                    statusBar
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .onOpenURL(perform: handleOpenURL)
        .task(id: retryID) { store.start(retrying: retryID > 0) }
        .task(id: store.isConnected) { if store.isConnected { await loadFilterCatalogs() } }
        .task(id: "\(selectedTorrentID ?? "")|\(detailTab.rawValue)|\(store.isConnected)") { await loadDetails() }
        .onChange(of: torrents.map(\.id)) { _, ids in
            selectedTorrentIDs.formIntersection(ids)
            if selectedTorrentIDs.isEmpty, let first = ids.first { selectedTorrentIDs = [first] }
        }
        .onChange(of: torrents.map(\.progress)) { _, _ in checkDownloadCompletion() }
        .onChange(of: showsOrganization) { wasPresented, isPresented in
            if wasPresented && !isPresented { Task { await loadFilterCatalogs() } }
        }
        .onChange(of: store.isConnected) { _, isConnected in
            if isConnected { presentNextExternalURLIfReady() }
        }
        .onAppear {
            sidebarVisibility = showFiltersSidebar ? .all : .detailOnly
            syncWindowTitle()
            MacOSStatusPresentation.updateDockSpeed(store.transferStatus, enabled: showSpeedInDock)
            store.updateSleepInhibition()
            if startMinimized {
                DispatchQueue.main.async { NSApp.keyWindow?.miniaturize(nil) }
            }
        }
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
        .toolbar { toolbarContent }
        .toolbarVisibility(showToolbar ? .visible : .hidden, for: .windowToolbar)
        .focusedSceneValue(\.qBitXCommandActions, QBitXCommandActions(
            addTorrentFile: { showsFileImporter = true },
            addTorrentURL: { showsURLSheet = true },
            pasteTorrentLinks: pasteTorrentLinks,
            createTorrent: { showsTorrentCreator = true },
            removeSelected: { requestRemoval(hashes: selectedHashes) },
            startSelected: { runBulkAction { try await store.command(.start, hashes: $0) } },
            stopSelected: { runBulkAction { try await store.command(.stop, hashes: $0) } },
            forceStartSelected: { runBulkAction { try await store.setForceStart(true, hashes: $0) } },
            recheckSelected: { runBulkAction { try await store.command(.recheck, hashes: $0) } },
            moveSelectedToTop: { runBulkAction { try await store.command(.topPrio, hashes: $0) } },
            moveSelectedUp: { runBulkAction { try await store.command(.increasePrio, hashes: $0) } },
            moveSelectedDown: { runBulkAction { try await store.command(.decreasePrio, hashes: $0) } },
            moveSelectedToBottom: { runBulkAction { try await store.command(.bottomPrio, hashes: $0) } },
            pauseSession: { setSessionPaused(true) },
            resumeSession: { setSessionPaused(false) },
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
            checkForUpdates: { openURL("https://github.com/AndreaCodinLife/qBittorrent/releases") },
            donate: { openURL("https://www.qbittorrent.org/donate") },
            showAbout: { showsAbout = true }
        ))
        .sheet(isPresented: $showsURLSheet, onDismiss: {
            incomingTorrentURL = nil
            presentNextExternalURLIfReady()
        }) {
            AddTorrentSheet(file: nil, store: store, initialURL: incomingTorrentURL ?? "") { url, downloader, options in
                try await store.add(url: url, downloader: downloader, options: options)
            }
        }
        .sheet(item: $pendingTorrentFile, onDismiss: presentNextExternalURLIfReady) { file in
            AddTorrentSheet(file: file, store: store) { source, _, options in
                if source.hasPrefix("magnet:") {
                    try await store.add(url: source, options: options)
                } else {
                    var uploadOptions = options
                    uploadOptions.filePriorities = nil
                    try await store.add(file: file.data, filename: file.name, options: uploadOptions)
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
        .sheet(item: $previewTorrent) { torrent in
            TorrentPreviewView(torrent: torrent, store: store) { url in NSWorkspace.shared.open(url) }
        }
        .sheet(isPresented: $showsOrganization) { OrganizationView(store: store, initialCategoryName: organizationInitialCategory) }
        .sheet(isPresented: $showsAbout) { AboutView(serverVersion: store.serverVersion) }
        .sheet(isPresented: $showsFileAssociations) { FileAssociationView() }
        .sheet(item: $textAction) { action in
            ValueSheet(title: action.title, hint: action.hint, initialValue: initialValue(for: action), allowsEmpty: action == .category || action == .tags) { value in
                try await applyTextAction(action, value: value)
            }
        }
        .sheet(item: $detailInput) { input in
            ValueSheet(title: input.title, hint: input.hint, initialValue: input.initialValue) { value in
                try await applyDetailInput(input, value: value)
            }
        }
        .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [UTType(filenameExtension: "torrent") ?? .data]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                pendingTorrentFile = PendingTorrentFile(name: url.lastPathComponent, data: data)
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
                runBulkAction(hashes: clearTagsHashes) { try await store.removeTorrentTags([], hashes: $0) }
            }
            Button("Cancel", role: .cancel) {}
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
        Label(title, systemImage: image).labelStyle(ToolbarLabelStyle(style: toolbarStyle))
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

    private func presentNextExternalURLIfReady() {
        guard store.isConnected, pendingTorrentFile == nil, !showsURLSheet else { return }
        while !pendingExternalURLs.isEmpty {
            let url = pendingExternalURLs.removeFirst()
            if url.isFileURL {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    pendingTorrentFile = PendingTorrentFile(name: url.lastPathComponent, data: try Data(contentsOf: url))
                    return
                } catch {
                    actionError = error.localizedDescription
                    continue
                }
            }

            incomingTorrentURL = url.absoluteString
            showsURLSheet = true
            return
        }
    }

    private func pasteTorrentLinks() {
        guard let clipboard = NSPasteboard.general.string(forType: .string) else { return }
        let links = clipboard.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && (isTorrentLink($0) || localTorrentURL($0) != nil) }
        guard !links.isEmpty else { return }
        Task {
            for link in links {
                do {
                    if let fileURL = localTorrentURL(link) {
                        let access = fileURL.startAccessingSecurityScopedResource()
                        defer { if access { fileURL.stopAccessingSecurityScopedResource() } }
                        try await store.add(file: Data(contentsOf: fileURL), filename: fileURL.lastPathComponent)
                    } else {
                        try await store.add(url: link)
                    }
                }
                catch { actionError = error.localizedDescription; return }
            }
        }
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
            else { Text(title) }
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
            Button("Check for Updates…") { openURL("https://github.com/AndreaCodinLife/qBittorrent/releases") }
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
                        .contextMenu { torrentFilterActions(hashes: torrents.filter { $0.trackerHosts.contains(trackerHost) }.map(\.id)) }
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
                            Text(tab == .transfers ? "Transfers (\(torrents.count))" : tab.rawValue)
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
                        Button(field.title) { sortField = field }
                    }
                    Divider()
                    Toggle("Descending", isOn: $sortDescending)
                } label: {
                    Text("Sort: \(sortField.title)")
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
                    .tint(colorTransfersByState && progressBarFollowsStateColor ? stateColor(for: torrent) : Color.accentColor)
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
                            Text(tab.rawValue)
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
            TorrentPieceBars(states: pieceStates, availability: pieceAvailability)
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
                let freeSpace = store.serverStatistics?.free_space_on_disk.map {
                    ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
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
                Button { showDetailInput(.addTracker, title: "Add Tracker", hint: "Tracker URL") } label: { Image(systemName: "plus") }
                    .buttonStyle(.glass)
                    .help("Add tracker")
                    .accessibilityLabel("Add tracker")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        trackerHeader("Tier", width: 46)
                        trackerHeader("URL / Endpoint", width: 260)
                        trackerHeader("Status", width: 120)
                        trackerHeader("Peers", width: 55)
                        trackerHeader("Seeds", width: 55)
                        trackerHeader("Leeches", width: 60)
                        trackerHeader("Downloaded", width: 80)
                        trackerHeader("Next Announce", width: 105)
                        trackerHeader("Min Announce", width: 105)
                        trackerHeader("Message", width: 260)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    Divider()
                    ForEach(trackers) { tracker in
                        trackerRow(tracker)
                        ForEach(tracker.endpoints ?? []) { endpoint in
                            HStack(spacing: 10) {
                                Text("↳").frame(width: 46, alignment: .leading)
                                    .foregroundStyle(.tertiary)
                                trackerCell(endpoint.name, width: 260)
                                trackerCell(trackerStatusText(endpoint.status, updating: endpoint.updating), width: 120)
                                trackerCell(countText(endpoint.num_peers), width: 55)
                                trackerCell(countText(endpoint.num_seeds), width: 55)
                                trackerCell(countText(endpoint.num_leeches), width: 60)
                                trackerCell(countText(endpoint.num_downloaded), width: 80)
                                trackerCell(announceText(endpoint.next_announce), width: 105)
                                trackerCell(announceText(endpoint.min_announce), width: 105)
                                trackerCell(endpoint.msg ?? "", width: 260)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.secondary.opacity(0.04))
                        }
                    }
                }
            }
        }
    }

    private func trackerRow(_ tracker: TorrentTracker) -> some View {
        HStack(spacing: 10) {
            trackerCell(tracker.tier.map { $0 < 0 ? "—" : "\($0 + 1)" } ?? "—", width: 46)
            trackerCell(tracker.url, width: 260)
            trackerCell(trackerStatusText(tracker.status, updating: tracker.updating), width: 120)
            trackerCell(countText(tracker.num_peers), width: 55)
            trackerCell(countText(tracker.num_seeds), width: 55)
            trackerCell(countText(tracker.num_leeches), width: 60)
            trackerCell(countText(tracker.num_downloaded), width: 80)
            trackerCell(announceText(tracker.next_announce), width: 105)
            trackerCell(announceText(tracker.min_announce), width: 105)
            trackerCell(tracker.msg ?? "", width: 260)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            if (tracker.tier ?? -1) >= 0 {
                Button("Edit URL…") { showDetailInput(.editTracker(tracker.url), title: "Edit Tracker", hint: "Tracker URL", initialValue: tracker.url) }
                Menu("Move to Tier") {
                    ForEach(availableTrackerTiers, id: \.self) { tier in
                        Button("Tier \(tier + 1)\(tier == (tracker.tier ?? 0) ? " ✓" : "")") {
                            Task { await performDetailAction { try await store.moveTracker(hash: $0, url: tracker.url, tier: tier) } }
                        }
                    }
                }
                Button("Remove Tracker", role: .destructive) {
                    Task { await performDetailAction { try await store.removeTracker(hash: $0, url: tracker.url) } }
                }
            }
            if !(tracker.url.hasPrefix("** [")) {
                Button("Copy URL") { copyToPasteboard(tracker.url) }
            }
            if (tracker.tier ?? -1) >= 0, selectedTorrent?.state != .paused {
                Button("Force Reannounce to This Tracker") {
                    Task { await performDetailAction { try await store.reannounceTrackers(hash: $0, urls: [tracker.url]) } }
                }
            }
            if selectedTorrent?.state != .paused {
                Button("Force Reannounce to All Trackers") {
                    Task { await performDetailAction { try await store.command(.reannounce, hashes: [$0]) } }
                }
            }
        }
        .font(.caption)
    }

    private func trackerHeader(_ text: String, width: CGFloat) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
    }

    private func trackerCell(_ text: String, width: CGFloat) -> some View {
        Text(text.isEmpty ? "—" : text).lineLimit(1).help(text)
            .frame(width: width, alignment: .leading)
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
                Button("Select All") { selectedFileIDs = Set(files.map(\.id)) }
                    .disabled(files.isEmpty)
                Button("Select None") { selectedFileIDs = [] }
                    .disabled(selectedFileIDs.isEmpty)
                Menu("Priority") { filePriorityActions(for: selectedFileIDs) }
                    .disabled(selectedFileIDs.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            if files.isEmpty {
                ContentUnavailableView("No Files", systemImage: "doc.text", description: Text("File information is unavailable until torrent metadata has loaded."))
            } else {
                VStack(spacing: 0) {
                    HStack {
                        peerColumnHeader("Name", width: 520)
                        peerColumnHeader("Size", width: 100)
                        peerColumnHeader("Availability", width: 100)
                        peerColumnHeader("Progress", width: 80)
                        peerColumnHeader("Priority", width: 110)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    Divider()
                    List(files, selection: $selectedFileIDs) { file in
                        let row = HStack(spacing: 12) {
                            Text(file.name).lineLimit(1).frame(width: 520, alignment: .leading)
                            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                .frame(width: 100, alignment: .leading)
                            Text(file.availability.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "—")
                                .frame(width: 100, alignment: .leading)
                            Text(file.progress.formatted(.percent.precision(.fractionLength(0))))
                                .frame(width: 80, alignment: .leading)
                            Text(filePriorityLabel(file.priority))
                                .foregroundStyle(.secondary)
                                .frame(width: 110, alignment: .leading)
                        }
                        .font(.caption)
                        .tag(file.id)
                        .onTapGesture(count: 2) {
                            if let torrent = selectedTorrent { openTorrentFile(file, in: torrent) }
                        }
                        .contextMenu {
                            if let torrent = selectedTorrent, isPreviewable(file) {
                                Button("Preview File") { openTorrentFile(file, in: torrent) }
                                    .disabled(!torrentFileExists(file, in: torrent))
                            }
                            filePriorityActions(for: selectedFileIDs.contains(file.id) ? selectedFileIDs : [file.id])
                            Button("Rename…") { showDetailInput(.renameFile(file.name), title: "Rename File", hint: "File name", initialValue: (file.name as NSString).lastPathComponent) }
                        }
                        if dragContentFiles,
                           store.usesBundledBackend,
                           let torrent = selectedTorrent,
                           torrentFileExists(file, in: torrent) {
                            row.draggable(torrentFileURL(file, in: torrent))
                        } else {
                            row
                        }
                    }
                    .listStyle(.inset)
                }
            }
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
                Button { showDetailInput(.addPeer, title: "Add Peer", hint: "IP address:port") } label: { Image(systemName: "plus") }
                    .buttonStyle(.glass)
                    .help("Add peer")
                    .accessibilityLabel("Add peer")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            if peers.isEmpty {
                ContentUnavailableView("No Peers", systemImage: "person.2", description: Text("No peers are connected to this torrent."))
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) {
                            peerColumnHeader("Country/Region", width: 150)
                            peerColumnHeader("IP/Address", width: 120)
                            peerColumnHeader("Port", width: 55)
                            peerColumnHeader("Connection", width: 100)
                            peerColumnHeader("Flags", width: 60)
                            peerColumnHeader("Client", width: 140)
                            peerColumnHeader("Peer ID Client", width: 140)
                            peerColumnHeader("Progress", width: 75)
                            peerColumnHeader("Down Speed", width: 100)
                            peerColumnHeader("Up Speed", width: 100)
                            peerColumnHeader("Downloaded", width: 105)
                            peerColumnHeader("Uploaded", width: 105)
                            peerColumnHeader("Relevance", width: 80)
                            peerColumnHeader("Contribution", width: 90)
                            peerColumnHeader("Files", width: 220)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        Divider()
                        ForEach(peers) { peer in
                            HStack(spacing: 12) {
                                HStack(spacing: 5) {
                                    if let flag = peer.countryFlag { Text(flag) }
                                    else { Image(systemName: "globe").foregroundStyle(.tertiary) }
                                    Text(peer.countryName).lineLimit(1)
                                }
                                .frame(width: 150, alignment: .leading)
                                .help(peer.countryName)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Country or region: \(peer.countryName)")
                                peerValue(peer.ip, width: 120, tooltip: peer.host_name ?? peer.ip)
                                peerValue("\(peer.port ?? 0)", width: 55)
                                peerValue(peer.connection ?? "—", width: 100)
                                peerValue(peer.flags ?? "—", width: 60, tooltip: peer.flags_desc ?? "Peer flags")
                                peerValue(peer.client ?? "Unknown client", width: 140)
                                peerValue(peer.peer_id_client ?? "—", width: 140)
                                peerValue((peer.progress ?? 0).formatted(.percent.precision(.fractionLength(0))), width: 75)
                                peerValue(TransferStatus.rateText(peer.dl_speed ?? 0), width: 100)
                                peerValue(TransferStatus.rateText(peer.up_speed ?? 0), width: 100)
                                peerValue(ByteCountFormatter.string(fromByteCount: peer.downloaded ?? 0, countStyle: .file), width: 105)
                                peerValue(ByteCountFormatter.string(fromByteCount: peer.uploaded ?? 0, countStyle: .file), width: 105)
                                peerValue("\(((peer.relevance ?? 0) * 100).formatted(.number.precision(.fractionLength(0))))%", width: 80)
                                peerValue("\(((peer.contribution ?? 0) * 100).formatted(.number.precision(.fractionLength(0))))%", width: 90)
                                peerValue(peer.files?.replacingOccurrences(of: "\n", with: "; ") ?? "—", width: 220, tooltip: peer.files ?? "")
                                Spacer(minLength: 0)
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button("Copy IP:port") { copyToPasteboard("\(peer.ip):\(peer.port ?? 0)") }
                                Button("Ban Peer Permanently", role: .destructive) {
                                    Task {
                                        do { try await store.banPeer(address: "\(peer.ip):\(peer.port ?? 0)") }
                                        catch { actionError = error.localizedDescription }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func peerColumnHeader(_ title: String, width: CGFloat) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
    }

    private func peerValue(_ value: String, width: CGFloat, tooltip: String? = nil) -> some View {
        Text(value).lineLimit(1).frame(width: width, alignment: .leading).help(tooltip ?? value)
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
        selectedFileIDs = []
        peers = []
        webSeeds = []
        guard let selectedTorrentID, store.isConnected else { return }
        do {
            switch detailTab {
            case .general:
                async let propertyRequest = store.properties(for: selectedTorrentID)
                async let statesRequest = try? store.pieceStates(for: selectedTorrentID)
                async let availabilityRequest = try? store.pieceAvailability(for: selectedTorrentID)
                properties = try await propertyRequest
                pieceStates = (await statesRequest) ?? []
                pieceAvailability = (await availabilityRequest) ?? []
            case .trackers: trackers = try await store.trackers(for: selectedTorrentID)
            case .content: files = try await store.files(for: selectedTorrentID)
            case .peers:
                while !Task.isCancelled {
                    peers = try await store.peers(for: selectedTorrentID)
                    try await Task.sleep(for: .seconds(2))
                }
            case .httpSources: webSeeds = try await store.webSeeds(for: selectedTorrentID)
            default: break
            }
        } catch is CancellationError {
            return
        } catch {
            actionError = error.localizedDescription
        }
    }

    @ViewBuilder private func torrentContextMenu(for target: Set<String>) -> some View {
        let hashes = target.sorted()
        let targetTorrent = torrents.first { target.contains($0.id) }
        Button("Start") { runBulkAction(hashes: hashes) { try await store.command(.start, hashes: $0) } }
        Button("Stop") { runBulkAction(hashes: hashes) { try await store.command(.stop, hashes: $0) } }
        Toggle("Force Start", isOn: Binding(
            get: { targetTorrent?.forceStart ?? false },
            set: { value in runBulkAction(hashes: hashes) { try await store.setForceStart(value, hashes: $0) } }
        ))
        Divider()
        Button("Rename…") { beginTextAction(.rename, target: target) }.disabled(hashes.count != 1)
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
                clearTagsHashes = hashes
                showsClearTagsConfirmation = true
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
        Button("Manage Trackers") { detailTab = .trackers }.disabled(hashes.count != 1)
        Button("Torrent Options…") { torrentOptionsTarget = TorrentOptionsTarget(hashes: hashes) }
        Button("Preview File…") {
            if let targetTorrent { openPreviewOrDestination(for: targetTorrent) }
        }
            .disabled(hashes.count != 1)
        Button("Open Destination Folder") {
            if let targetTorrent { openDestinationFolder(for: targetTorrent) }
        }
        .disabled(targetTorrent?.savePath.isEmpty ?? true)
        Menu("Queue") {
            Button("Move to Top") { runBulkAction(hashes: hashes) { try await store.command(.topPrio, hashes: $0) } }
            Button("Move Up") { runBulkAction(hashes: hashes) { try await store.command(.increasePrio, hashes: $0) } }
            Button("Move Down") { runBulkAction(hashes: hashes) { try await store.command(.decreasePrio, hashes: $0) } }
            Button("Move to Bottom") { runBulkAction(hashes: hashes) { try await store.command(.bottomPrio, hashes: $0) } }
        }
        Divider()
        Button("Force Recheck") { runBulkAction(hashes: hashes) { try await store.command(.recheck, hashes: $0) } }
        Button("Force Reannounce") { runBulkAction(hashes: hashes) { try await store.command(.reannounce, hashes: $0) } }
        Divider()
        Toggle("Sequential Download", isOn: Binding(
            get: { targetTorrent?.sequentialDownload ?? false },
            set: { _ in runBulkAction(hashes: hashes) { try await store.command(.toggleSequentialDownload, hashes: $0) } }
        ))
        Toggle("First and Last Pieces First", isOn: Binding(
            get: { targetTorrent?.firstLastPiecePriority ?? false },
            set: { _ in runBulkAction(hashes: hashes) { try await store.command(.toggleFirstLastPiecePrio, hashes: $0) } }
        ))
        Toggle("Automatic Torrent Management", isOn: Binding(
            get: { targetTorrent?.automaticManagement ?? false },
            set: { value in runBulkAction(hashes: hashes) { try await store.setAutomaticManagement(value, hashes: $0) } }
        ))
        Toggle("Super Seeding", isOn: Binding(
            get: { targetTorrent?.superSeeding ?? false },
            set: { value in runBulkAction(hashes: hashes) { try await store.setSuperSeeding(value, hashes: $0) } }
        ))
        Menu("Copy") {
            Button("Names") { copySelectedTorrents(\.name, target: target) }
            Button("Torrent IDs") { copySelectedTorrents(\.id, target: target) }
            Button("Save Paths") { copySelectedTorrents(\.savePath, target: target) }
            Button("Content Paths") { copyContentPaths(target: target) }
            Button("Comments") { copyComments(target: target) }
            Button("Infohash v1") { copyColumn("infohash_v1", target: target) }
            Button("Infohash v2") { copyColumn("infohash_v2", target: target) }
            Button("Magnet Links") { copyMagnets(target: target) }
        }
        Button("Export .torrent…") { exportSelectedTorrent(hash: hashes.first) }.disabled(hashes.count != 1)
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

    private func applyDetailInput(_ input: DetailInput, value: String) async throws {
        switch input.operation {
        case .addTracker: try await store.addTracker(hash: input.hash, url: value)
        case let .editTracker(oldURL): try await store.editTracker(hash: input.hash, url: oldURL, newURL: value)
        case .addWebSeed: try await store.addWebSeed(hash: input.hash, url: value)
        case let .editWebSeed(oldURL): try await store.editWebSeed(hash: input.hash, url: oldURL, newURL: value)
        case .addPeer: try await store.addPeer(hash: input.hash, address: value)
        case let .renameFile(oldPath):
            let parent = (oldPath as NSString).deletingLastPathComponent
            let newPath = parent.isEmpty ? value : (parent as NSString).appendingPathComponent(value)
            try await store.renameFile(hash: input.hash, oldPath: oldPath, newPath: newPath)
        }
        if input.operation != .addPeer { await loadDetails() }
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
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func checkDownloadCompletion() {
        let currentTorrents = Set(torrents.map(\.id))
        let currentIncomplete = Set(torrents.filter { $0.progress < 1 }.map(\.id))
        guard !currentTorrents.isEmpty else {
            incompleteDownloadIDs = []
            return
        }
        if !currentIncomplete.isEmpty {
            incompleteDownloadIDs = currentIncomplete
        } else if !incompleteDownloadIDs.isEmpty {
            let completedExistingTorrents = incompleteDownloadIDs.isSubset(of: currentTorrents)
            incompleteDownloadIDs = []
            if completedExistingTorrents, downloadCompletionAction != "none" {
                if confirmAutoCompletionAction {
                    showsDownloadCompletionAction = true
                } else {
                    performDownloadCompletionAction()
                }
            }
        }
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

    private func torrentFileURL(_ file: TorrentFile, in torrent: Torrent) -> URL {
        URL(fileURLWithPath: torrent.savePath, isDirectory: true).appending(path: file.name)
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

    private func exportSelectedTorrent(hash: String?) {
        guard let torrent = torrents.first(where: { $0.id == hash }) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = torrent.name + ".torrent"
        panel.allowedContentTypes = [UTType(filenameExtension: "torrent") ?? .data]
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            Task {
                do {
                    let data = try await store.exportTorrent(torrent.id)
                    try data.write(to: destination, options: .atomic)
                } catch { actionError = error.localizedDescription }
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
    let onApply: (String) async throws -> Void
    @State private var value: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(title: String, hint: String, initialValue: String, allowsEmpty: Bool = false, onApply: @escaping (String) async throws -> Void) {
        self.title = title
        self.hint = hint
        self.allowsEmpty = allowsEmpty
        self.onApply = onApply
        _value = State(initialValue: initialValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.weight(.semibold))
            TextField(hint, text: $value).textFieldStyle(.roundedBorder)
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
        .frame(width: 480)
    }
}

struct PendingTorrentFile: Identifiable {
    let id = UUID()
    let name: String
    let data: Data
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
    let file: PendingTorrentFile?
    let store: TorrentStore
    let initialURL: String
    let initialDownloader: String?
    let onAdd: (String, String?, TorrentAddOptions) async throws -> Void
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
    @State private var filePriorities: [Int] = []
    @State private var fileFilter = ""
    @State private var isLoadingMetadata = false
    @State private var errorMessage: String?
    @State private var isAdding = false

    init(file: PendingTorrentFile?, store: TorrentStore, initialURL: String = "", initialDownloader: String? = nil, onAdd: @escaping (String, String?, TorrentAddOptions) async throws -> Void) {
        self.file = file
        self.store = store
        self.initialURL = initialURL
        self.initialDownloader = initialDownloader
        self.onAdd = onAdd
        _url = State(initialValue: initialURL)
    }

    private var files: [TorrentMetadataFile] { metadata?.info?.files ?? [] }
    private var filteredFileIndices: [Int] {
        files.indices.filter { fileFilter.isEmpty || files[$0].path.localizedCaseInsensitiveContains(fileFilter) }
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
                if file == nil {
                    Button("Load Content") { Task { await loadMetadata() } }
                        .buttonStyle(.glass)
                        .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingMetadata)
                }
            }
            if file == nil {
                TextField("magnet:?xt=… or https://…", text: $url)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(alignment: .top, spacing: 14) {
                Form {
                    Section("Location and organization") {
                        TextField("Save location", text: $savePath, prompt: Text("Backend default"))
                            .disabled(automaticManagement)
                        Toggle("Use another path for incomplete torrents", isOn: $downloadPathEnabled)
                            .disabled(automaticManagement)
                        if downloadPathEnabled {
                            TextField("Incomplete save path", text: $downloadPath)
                                .disabled(automaticManagement)
                        }
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
                    if !files.isEmpty {
                        TextField("Filter files…", text: $fileFilter)
                            .textFieldStyle(.roundedBorder)
                        List {
                            ForEach(filteredFileIndices, id: \.self) { index in
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(files[index].path).lineLimit(1)
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
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add Torrent") {
                    isAdding = true
                    Task {
                        do {
                            var options = TorrentAddOptions()
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
                            let source = file == nil ? url.trimmingCharacters(in: .whitespacesAndNewlines) : (metadata?.magnetURI ?? "")
                            if setDefaultCategory { defaultCategory = options.category }
                            try await onAdd(source, initialDownloader, options)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                            isAdding = false
                        }
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled((file == nil && url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || isAdding || !(0...1_000_000).contains(downloadLimit) || !(0...1_000_000).contains(uploadLimit))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(25)
        .frame(minWidth: 900, idealWidth: 980, minHeight: 690, idealHeight: 760)
        .task {
            if category.isEmpty { category = defaultCategory }
            if file != nil || !initialURL.isEmpty { await loadMetadata() }
        }
    }

    private func loadMetadata() async {
        guard !isLoadingMetadata else { return }
        isLoadingMetadata = true
        errorMessage = nil
        defer { isLoadingMetadata = false }
        do {
            let fetched: TorrentMetadata
            if let file {
                fetched = try await store.parseTorrentMetadata(file: file.data, filename: file.name)
            } else {
                fetched = try await store.fetchTorrentMetadata(source: url.trimmingCharacters(in: .whitespacesAndNewlines), downloader: initialDownloader)
            }
            metadata = fetched
            filePriorities = (fetched.info?.files ?? []).map { $0.priority ?? 1 }
        } catch { errorMessage = error.localizedDescription }
    }

    private func saveMetadata() {
        guard metadata != nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "torrent") ?? .data]
        panel.nameFieldStringValue = (metadata?.info?.name ?? "torrent") + ".torrent"
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            let source = file == nil ? url.trimmingCharacters(in: .whitespacesAndNewlines) : (metadata?.magnetURI ?? "")
            Task {
                do { try await store.saveTorrentMetadata(source: source).write(to: destination, options: .atomic) }
                catch { errorMessage = error.localizedDescription }
            }
        }
    }
}
