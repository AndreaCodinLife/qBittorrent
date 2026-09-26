import SwiftUI
import Charts
import UniformTypeIdentifiers

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

private enum TorrentSort: String, CaseIterable, Identifiable {
    case name = "Name", size = "Size", progress = "Progress", status = "Status"
    case seeds = "Seeds", peers = "Peers", downSpeed = "Down Speed", upSpeed = "Up Speed"
    case eta = "ETA", ratio = "Ratio", category = "Category"
    var id: String { rawValue }
}

struct ContentView: View {
    @State private var store = TorrentStore()
    @State private var selectedTorrentIDs: Set<String> = []
    @SceneStorage("qBitX.transferColumns") private var columnCustomization = TableColumnCustomization<Torrent>()
    @State private var textAction: TorrentTextAction?
    @State private var detailInput: DetailInput?
    @State private var statusFilter: TorrentFilter = .all
    @State private var categoryFilter: String?
    @State private var tagFilter: String?
    @State private var trackerFilter: String?
    @State private var searchText = ""
    @State private var sortField: TorrentSort = .name
    @State private var sortDescending = false
    @State private var mainTab: MainTab = .transfers
    @State private var detailTab: DetailTab = .general
    @State private var showsURLSheet = false
    @State private var showsFileImporter = false
    @State private var pendingTorrentFile: PendingTorrentFile?
    @State private var showsRemoveConfirmation = false
    @State private var showsConnectionSettings = false
    @State private var showsBackendPreferences = false
    @State private var showsSpeedLimits = false
    @State private var showsStatistics = false
    @State private var showsExecutionLog = false
    @State private var showsTorrentCreator = false
    @State private var showsCookies = false
    @State private var actionError: String?
    @State private var retryID = 0
    @State private var properties: TorrentProperties?
    @State private var trackers: [TorrentTracker] = []
    @State private var files: [TorrentFile] = []
    @State private var peers: [TorrentPeer] = []
    @State private var webSeeds: [TorrentWebSeed] = []

    private var torrents: [Torrent] { store.torrents }

    private var visibleTorrents: [Torrent] {
        torrents.filter { torrent in
            statusFilter.includes(torrent)
                && (categoryFilter == nil || torrent.category == categoryFilter)
                && (tagFilter.map { tag in torrent.tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(tag) } ?? true)
                && (trackerFilter == nil || torrent.tracker == trackerFilter)
                && (searchText.isEmpty || torrent.name.localizedCaseInsensitiveContains(searchText))
        }.sorted { left, right in
            let result: ComparisonResult
            switch sortField {
            case .name: result = left.name.localizedStandardCompare(right.name)
            case .status: result = left.state.rawValue.localizedStandardCompare(right.state.rawValue)
            case .category: result = left.category.localizedStandardCompare(right.category)
            case .size: result = compare(left.sizeBytes, right.sizeBytes)
            case .progress: result = compare(left.progress, right.progress)
            case .seeds: result = compare(left.seeds, right.seeds)
            case .peers: result = compare(left.peers, right.peers)
            case .downSpeed: result = compare(left.downloadRateBytes, right.downloadRateBytes)
            case .upSpeed: result = compare(left.uploadRateBytes, right.uploadRateBytes)
            case .eta: result = compare(left.etaSeconds, right.etaSeconds)
            case .ratio: result = compare(left.ratio, right.ratio)
            }
            return sortDescending ? result == .orderedDescending : result == .orderedAscending
        }
    }

    private func compare<T: Comparable>(_ left: T, _ right: T) -> ComparisonResult {
        if left < right { return .orderedAscending }
        if left > right { return .orderedDescending }
        return .orderedSame
    }

    private var selectedTorrent: Torrent? {
        torrents.first { $0.id == selectedTorrentID }
    }

    private var selectedTorrentID: String? {
        visibleTorrents.first { selectedTorrentIDs.contains($0.id) }?.id ?? selectedTorrentIDs.first
    }

    private var selectedHashes: [String] { selectedTorrentIDs.sorted() }

    var body: some View {
        NavigationSplitView {
            filterSidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        } detail: {
            VStack(spacing: 0) {
                mainTabs
                Divider()
                switch mainTab {
                case .transfers:
                    VSplitView {
                        torrentTable.frame(minHeight: 240)
                        detailsPane.frame(minHeight: 170)
                    }
                case .search:
                    SearchPane(store: store)
                case .rss:
                    RSSPane(store: store)
                }
                Divider()
                statusBar
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .task(id: retryID) { await store.run() }
        .task(id: "\(selectedTorrentID ?? "")|\(detailTab.rawValue)|\(store.isConnected)") { await loadDetails() }
        .onChange(of: torrents.map(\.id)) { _, ids in
            selectedTorrentIDs.formIntersection(ids)
            if selectedTorrentIDs.isEmpty, let first = ids.first { selectedTorrentIDs = [first] }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showsFileImporter = true } label: {
                    Label("Add Torrent", systemImage: "plus")
                }
                .help("Open a .torrent file")

                Button { showsURLSheet = true } label: {
                    Label("Add URL", systemImage: "link.badge.plus")
                }
                .help("Add a magnet link or torrent URL")

                Button(role: .destructive) { showsRemoveConfirmation = true } label: {
                    Label("Remove", systemImage: "trash")
                }
                .disabled(selectedTorrent == nil)

                Button { runBulkAction { try await store.command(.start, hashes: $0) } } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .disabled(selectedTorrent == nil)

                Button { runBulkAction { try await store.command(.stop, hashes: $0) } } label: {
                    Label("Stop", systemImage: "pause.fill")
                }
                .disabled(selectedTorrent == nil)

                Menu {
                    Button("Pause Session") { setSessionPaused(true) }
                    Button("Resume Session") { setSessionPaused(false) }
                    Divider()
                    Button("Speed Limits…") { showsSpeedLimits = true }
                } label: {
                    Label("Session", systemImage: "pause.circle")
                }

                Button {
                    if let path = selectedTorrent?.savePath, !path.isEmpty {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                } label: {
                    Label("Open Destination", systemImage: "folder")
                }
                .disabled(selectedTorrent?.savePath.isEmpty ?? true)

                Menu {
                    Button("qBittorrent Preferences…") { showsBackendPreferences = true }
                    Button("Connection…") { showsConnectionSettings = true }
                    Divider()
                    Button("Create Torrent…") { showsTorrentCreator = true }
                        .disabled(!store.usesBundledBackend)
                    Button("Cookies…") { showsCookies = true }
                    Button("Statistics…") { showsStatistics = true }
                    Button("Execution Log…") { showsExecutionLog = true }
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("qBittorrent preferences and connection")
            }
        }
        .sheet(isPresented: $showsURLSheet) {
            AddTorrentSheet(file: nil) { url, options in
                try await store.add(url: url, options: options)
            }
        }
        .sheet(item: $pendingTorrentFile) { file in
            AddTorrentSheet(file: file) { _, options in
                try await store.add(file: file.data, filename: file.name, options: options)
            }
        }
        .sheet(isPresented: $showsConnectionSettings) {
            ConnectionSettingsView(store: store) { retryID += 1 }
        }
        .sheet(isPresented: $showsBackendPreferences) { BackendPreferencesView(store: store) }
        .sheet(isPresented: $showsSpeedLimits) { SpeedLimitsView(store: store) }
        .sheet(isPresented: $showsStatistics) { StatisticsView(store: store) }
        .sheet(isPresented: $showsExecutionLog) { ExecutionLogView(store: store) }
        .sheet(isPresented: $showsTorrentCreator) { TorrentCreatorView(store: store) }
        .sheet(isPresented: $showsCookies) { CookiesView(store: store) }
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
        .alert("Action failed", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private var filterSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sidebarSection("STATUS") {
                    ForEach(TorrentFilter.allCases) { item in
                        sidebarRow(item.rawValue, symbol: item.symbol, count: torrents.filter(item.includes).count, selected: statusFilter == item && categoryFilter == nil && tagFilter == nil && trackerFilter == nil) {
                            statusFilter = item
                            categoryFilter = nil
                            tagFilter = nil
                            trackerFilter = nil
                        }
                    }
                }
                sidebarSection("CATEGORIES") {
                    ForEach(Array(Set(torrents.map(\.category))).sorted(), id: \.self) { category in
                        sidebarRow(category.isEmpty ? "Uncategorized" : category, symbol: "folder", count: torrents.filter { $0.category == category }.count, selected: categoryFilter == category) {
                            categoryFilter = category
                            statusFilter = .all
                            tagFilter = nil
                            trackerFilter = nil
                        }
                    }
                }
                sidebarSection("TAGS") {
                    sidebarRow("All", symbol: "tag", count: torrents.count, selected: tagFilter == nil && categoryFilter == nil && trackerFilter == nil && statusFilter == .all) {
                        categoryFilter = nil
                        statusFilter = .all
                        tagFilter = nil
                        trackerFilter = nil
                    }
                    ForEach(Array(Set(torrents.flatMap { $0.tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }.filter { !$0.isEmpty })).sorted(), id: \.self) { tag in
                        sidebarRow(tag, symbol: "tag", count: torrents.filter { $0.tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(tag) }.count, selected: tagFilter == tag) {
                            tagFilter = tag
                            statusFilter = .all
                            categoryFilter = nil
                            trackerFilter = nil
                        }
                    }
                }
                sidebarSection("TRACKERS") {
                    ForEach(Array(Set(torrents.map(\.tracker).filter { !$0.isEmpty })).sorted(), id: \.self) { tracker in
                        sidebarRow(URL(string: tracker)?.host ?? tracker, symbol: "network", count: torrents.filter { $0.tracker == tracker }.count, selected: trackerFilter == tracker) {
                            trackerFilter = tracker
                            statusFilter = .all
                            categoryFilter = nil
                            tagFilter = nil
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
                Text(store.isConnected ? "\(store.connectionName) · \(store.serverVersion)" : "Disconnected")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(14)
        }
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

    private func sidebarRow(_ title: String, symbol: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
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
            .padding(.horizontal, 10)
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
                Menu {
                    ForEach(TorrentSort.allCases) { field in
                        Button(field.rawValue) { sortField = field }
                    }
                    Divider()
                    Toggle("Descending", isOn: $sortDescending)
                } label: {
                    Text("Sort: \(sortField.rawValue)")
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
        .contextMenu { torrentContextMenu }
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
            Label(torrent.name, systemImage: "doc.zipper").lineLimit(1)
        }
        .width(min: 200, ideal: 270).customizationID("name")
        TableColumn("Size", value: \.size).width(80).customizationID("size")
        TableColumn("Progress") { torrent in
            HStack(spacing: 6) {
                ProgressView(value: torrent.progress)
                Text(torrent.progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.monospacedDigit())
                    .frame(width: 32, alignment: .trailing)
            }
        }
        .width(min: 110, ideal: 140).customizationID("progress")
        TableColumn("Status") { torrent in Text(torrent.state.rawValue) }.width(95).customizationID("status")
        TableColumn("Seeds") { torrent in Text("\(torrent.seeds)") }.width(55).customizationID("seeds")
        TableColumn("Peers") { torrent in Text("\(torrent.peers)") }.width(55).customizationID("peers")
        TableColumn("Down Speed", value: \.downloadRate).width(90).customizationID("down_speed")
        TableColumn("Up Speed", value: \.uploadRate).width(90).customizationID("up_speed")
        TableColumn("ETA", value: \.eta).width(70).customizationID("eta")
    }

    @TableColumnBuilder<Torrent, Never>
    private var extraColumnsOne: some TableColumnContent<Torrent, Never> {
        TableColumn("Queue") { Text($0.column("priority")) }.width(60).customizationID("queue").defaultVisibility(.hidden)
        TableColumn("Total Size") { Text($0.column("total_size")) }.width(90).customizationID("total_size").defaultVisibility(.hidden)
        TableColumn("Ratio") { Text($0.column("ratio")) }.width(70).customizationID("ratio").defaultVisibility(.hidden)
        TableColumn("Popularity") { Text($0.column("popularity")) }.width(80).customizationID("popularity").defaultVisibility(.hidden)
        TableColumn("Category") { Text($0.column("category")) }.width(100).customizationID("category").defaultVisibility(.hidden)
        TableColumn("Tags") { Text($0.column("tags")) }.width(100).customizationID("tags").defaultVisibility(.hidden)
        TableColumn("Added On") { Text($0.column("added_on")) }.width(150).customizationID("added_on").defaultVisibility(.hidden)
        TableColumn("Seeding Since") { Text($0.column("completion_on")) }.width(150).customizationID("completion_on").defaultVisibility(.hidden)
        TableColumn("Tracker") { Text($0.column("tracker")) }.width(160).customizationID("tracker").defaultVisibility(.hidden)
        TableColumn("Down Limit") { Text($0.column("dl_limit")) }.width(90).customizationID("dl_limit").defaultVisibility(.hidden)
    }

    @TableColumnBuilder<Torrent, Never>
    private var extraColumnsTwo: some TableColumnContent<Torrent, Never> {
        TableColumn("Up Limit") { Text($0.column("up_limit")) }.width(90).customizationID("up_limit").defaultVisibility(.hidden)
        TableColumn("Downloaded") { Text($0.column("downloaded")) }.width(90).customizationID("downloaded").defaultVisibility(.hidden)
        TableColumn("Uploaded") { Text($0.column("uploaded")) }.width(90).customizationID("uploaded").defaultVisibility(.hidden)
        TableColumn("Session Downloaded") { Text($0.column("downloaded_session")) }.width(110).customizationID("downloaded_session").defaultVisibility(.hidden)
        TableColumn("Session Uploaded") { Text($0.column("uploaded_session")) }.width(110).customizationID("uploaded_session").defaultVisibility(.hidden)
        TableColumn("Amount Left") { Text($0.column("amount_left")) }.width(90).customizationID("amount_left").defaultVisibility(.hidden)
        TableColumn("Active Time") { Text($0.column("time_active")) }.width(90).customizationID("time_active").defaultVisibility(.hidden)
        TableColumn("Save Path") { Text($0.column("save_path")) }.width(220).customizationID("save_path").defaultVisibility(.hidden)
        TableColumn("Completed") { Text($0.column("completed")) }.width(90).customizationID("completed").defaultVisibility(.hidden)
        TableColumn("Ratio Limit") { Text($0.column("ratio_limit")) }.width(80).customizationID("ratio_limit").defaultVisibility(.hidden)
    }

    @TableColumnBuilder<Torrent, Never>
    private var extraColumnsThree: some TableColumnContent<Torrent, Never> {
        TableColumn("Last Seen Complete") { Text($0.column("seen_complete")) }.width(150).customizationID("seen_complete").defaultVisibility(.hidden)
        TableColumn("Last Activity") { Text($0.column("last_activity")) }.width(150).customizationID("last_activity").defaultVisibility(.hidden)
        TableColumn("Availability") { Text($0.column("availability")) }.width(80).customizationID("availability").defaultVisibility(.hidden)
        TableColumn("Download Path") { Text($0.column("download_path")) }.width(220).customizationID("download_path").defaultVisibility(.hidden)
        TableColumn("Infohash v1") { Text($0.column("infohash_v1")) }.width(260).customizationID("infohash_v1").defaultVisibility(.hidden)
        TableColumn("Infohash v2") { Text($0.column("infohash_v2")) }.width(260).customizationID("infohash_v2").defaultVisibility(.hidden)
        TableColumn("Reannounce") { Text($0.column("reannounce")) }.width(90).customizationID("reannounce").defaultVisibility(.hidden)
        TableColumn("Private") { Text($0.column("private")) }.width(70).customizationID("private").defaultVisibility(.hidden)
        TableColumn("Created On") { Text($0.column("creation_date")) }.width(150).customizationID("creation_date").defaultVisibility(.hidden)
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
        HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 11) {
                detailLine("Name", torrent.name)
                detailLine("Status", torrent.state.rawValue)
                detailLine("Progress", torrent.progress.formatted(.percent.precision(.fractionLength(0))))
                detailLine("Size", torrent.size)
                if let savePath = properties?.save_path {
                    detailLine("Save path", savePath)
                }
                detailLine("Torrent ID", torrent.id)
                if let comment = properties?.comment, !comment.isEmpty { detailLine("Comment", comment) }
            }
            VStack(alignment: .leading, spacing: 11) {
                detailLine("Download speed", torrent.downloadRate)
                detailLine("Upload speed", torrent.uploadRate)
                detailLine("Peers", "\(torrent.peers)")
                detailLine("Time remaining", torrent.eta)
                detailLine("Ratio", torrent.ratio.formatted(.number.precision(.fractionLength(2))))
                if let properties {
                    detailLine("Downloaded", bytesText(properties.total_downloaded))
                    detailLine("Uploaded", bytesText(properties.total_uploaded))
                    detailLine("Availability", properties.availability.map { String(format: "%.2f", $0) } ?? "—")
                    detailLine("Total seeds", "\(properties.seeds_total ?? 0)")
                    detailLine("Total peers", "\(properties.peers_total ?? 0)")
                }
            }
            VStack(alignment: .leading, spacing: 11) {
                if let properties {
                    detailLine("Added", dateText(properties.addition_date))
                    detailLine("Completed", dateText(properties.completion_date))
                    detailLine("Created", dateText(properties.creation_date))
                    detailLine("Last seen", dateText(properties.last_seen))
                    detailLine("Active time", durationText(properties.time_elapsed))
                    detailLine("Seeding time", durationText(properties.seeding_time))
                    detailLine("Private", properties.is_private == true ? "Yes" : "No")
                    if let creator = properties.created_by, !creator.isEmpty { detailLine("Created by", creator) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func bytesText(_ bytes: Int64?) -> String {
        guard let bytes, bytes >= 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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
            Label(store.transferStatus.downloadText, systemImage: "arrow.down")
            Label(store.transferStatus.uploadText, systemImage: "arrow.up")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
    }

    private var trackerDetails: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Trackers").font(.caption.weight(.semibold))
                Spacer()
                Button { showDetailInput(.addTracker, title: "Add Tracker", hint: "Tracker URL") } label: { Image(systemName: "plus") }
                    .buttonStyle(.glass)
                    .help("Add tracker")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            List(trackers) { tracker in
                HStack {
                    Text(tracker.url).lineLimit(1)
                    Spacer()
                    Text("Seeds: \(tracker.num_seeds ?? 0)")
                    Text("Peers: \(tracker.num_peers ?? 0)")
                }
                .font(.caption)
                .contextMenu {
                    Button("Edit URL…") { showDetailInput(.editTracker(tracker.url), title: "Edit Tracker", hint: "Tracker URL", initialValue: tracker.url) }
                    Button("Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(tracker.url, forType: .string) }
                    Button("Remove Tracker", role: .destructive) {
                        Task { await performDetailAction { try await store.removeTracker(hash: $0, url: tracker.url) } }
                    }
                }
            }
        }
    }

    private var fileDetails: some View {
        List(files) { file in
            HStack {
                Text(file.name).lineLimit(1)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                Text(file.progress.formatted(.percent.precision(.fractionLength(0))))
                Text(file.priority == 0 ? "Skip" : file.priority == 6 ? "High" : file.priority == 7 ? "Maximum" : "Normal")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .contextMenu {
                Menu("Download Priority") {
                    Button("Do Not Download") { setFilePriority(file, to: 0) }
                    Button("Normal") { setFilePriority(file, to: 1) }
                    Button("High") { setFilePriority(file, to: 6) }
                    Button("Maximum") { setFilePriority(file, to: 7) }
                }
                Button("Rename…") { showDetailInput(.renameFile(file.name), title: "Rename File", hint: "File name", initialValue: (file.name as NSString).lastPathComponent) }
            }
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            List(peers) { peer in
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    if let flag = peer.countryFlag {
                        Text(flag).font(.body)
                    } else {
                        Image(systemName: "globe").foregroundStyle(.tertiary)
                    }
                    Text(peer.countryName)
                        .lineLimit(1)
                }
                .frame(width: 150, alignment: .leading)
                .help(peer.countryName)
                Text("\(peer.ip):\(peer.port ?? 0)").frame(minWidth: 150, alignment: .leading)
                Text(peer.client ?? "Unknown client").frame(minWidth: 120, alignment: .leading)
                Text((peer.progress ?? 0).formatted(.percent.precision(.fractionLength(0))))
                Spacer()
                Text("↓ \(TransferStatus.rateText(peer.dl_speed ?? 0))")
                Text("↑ \(TransferStatus.rateText(peer.up_speed ?? 0))")
            }
            .font(.caption)
            .contextMenu {
                Button("Copy IP:port") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(peer.ip):\(peer.port ?? 0)", forType: .string)
                }
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

    private var webSeedDetails: some View {
        VStack(spacing: 0) {
            HStack {
                Text("HTTP Sources").font(.caption.weight(.semibold))
                Spacer()
                Button { showDetailInput(.addWebSeed, title: "Add HTTP Source", hint: "HTTP or HTTPS URL") } label: { Image(systemName: "plus") }
                    .buttonStyle(.glass)
                    .help("Add web seed")
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
        let history = store.speedHistory[selectedTorrentID ?? ""] ?? []
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 20) {
                Label("Download \(selectedTorrent?.downloadRate ?? "0 B/s")", systemImage: "arrow.down")
                Label("Upload \(selectedTorrent?.uploadRate ?? "0 B/s")", systemImage: "arrow.up")
            }
            .font(.caption)
            Chart {
                ForEach(history) { sample in
                    LineMark(x: .value("Time", sample.date), y: .value("Bytes/s", sample.download), series: .value("Direction", "Download"))
                        .foregroundStyle(.blue)
                    LineMark(x: .value("Time", sample.date), y: .value("Bytes/s", sample.upload), series: .value("Direction", "Upload"))
                        .foregroundStyle(.green)
                }
            }
            .chartYScale(domain: 0...max(1024, history.map { max($0.download, $0.upload) }.max() ?? 0))
        }
        .padding(18)
    }

    private func loadDetails() async {
        properties = nil
        trackers = []
        files = []
        peers = []
        webSeeds = []
        guard let selectedTorrentID, store.isConnected else { return }
        do {
            switch detailTab {
            case .general: properties = try await store.properties(for: selectedTorrentID)
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

    @ViewBuilder private var torrentContextMenu: some View {
        Button("Start") { runBulkAction { try await store.command(.start, hashes: $0) } }
        Button("Stop") { runBulkAction { try await store.command(.stop, hashes: $0) } }
        Toggle("Force Start", isOn: Binding(
            get: { selectedTorrent?.forceStart ?? false },
            set: { value in runBulkAction { try await store.setForceStart(value, hashes: $0) } }
        ))
        Divider()
        Button("Rename…") { textAction = .rename }.disabled(selectedTorrentIDs.count != 1)
        Button("Set Location…") { textAction = .location }
        Button("Set Category…") { textAction = .category }
        Button("Set Tags…") { textAction = .tags }
        Menu("Queue") {
            Button("Move to Top") { runBulkAction { try await store.command(.topPrio, hashes: $0) } }
            Button("Move Up") { runBulkAction { try await store.command(.increasePrio, hashes: $0) } }
            Button("Move Down") { runBulkAction { try await store.command(.decreasePrio, hashes: $0) } }
            Button("Move to Bottom") { runBulkAction { try await store.command(.bottomPrio, hashes: $0) } }
        }
        Divider()
        Button("Force Recheck") { runBulkAction { try await store.command(.recheck, hashes: $0) } }
        Button("Force Reannounce") { runBulkAction { try await store.command(.reannounce, hashes: $0) } }
        Divider()
        Toggle("Sequential Download", isOn: Binding(
            get: { selectedTorrent?.sequentialDownload ?? false },
            set: { _ in runBulkAction { try await store.command(.toggleSequentialDownload, hashes: $0) } }
        ))
        Toggle("First and Last Pieces First", isOn: Binding(
            get: { selectedTorrent?.firstLastPiecePriority ?? false },
            set: { _ in runBulkAction { try await store.command(.toggleFirstLastPiecePrio, hashes: $0) } }
        ))
        Toggle("Automatic Torrent Management", isOn: Binding(
            get: { selectedTorrent?.automaticManagement ?? false },
            set: { value in runBulkAction { try await store.setAutomaticManagement(value, hashes: $0) } }
        ))
        Toggle("Super Seeding", isOn: Binding(
            get: { selectedTorrent?.superSeeding ?? false },
            set: { value in runBulkAction { try await store.setSuperSeeding(value, hashes: $0) } }
        ))
        Menu("Copy") {
            Button("Names") { copySelectedTorrents(\.name) }
            Button("Torrent IDs") { copySelectedTorrents(\.id) }
            Button("Save Paths") { copySelectedTorrents(\.savePath) }
        }
        Button("Export .torrent…") { exportSelectedTorrent() }.disabled(selectedTorrentIDs.count != 1)
        Divider()
        Button("Remove…", role: .destructive) { showsRemoveConfirmation = true }
    }

    private func runBulkAction(_ action: @escaping ([String]) async throws -> Void) {
        let hashes = selectedHashes
        guard !hashes.isEmpty else { return }
        Task {
            do { try await action(hashes) }
            catch { actionError = error.localizedDescription }
        }
    }

    private func removeSelectedTorrent(deleteFiles: Bool) {
        let hashes = selectedHashes
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

    private func setFilePriority(_ file: TorrentFile, to priority: Int) {
        Task {
            await performDetailAction { try await store.setFilePriority(hash: $0, index: file.index, priority: priority) }
        }
    }

    private func setSessionPaused(_ paused: Bool) {
        Task {
            do { try await store.setSessionPaused(paused) }
            catch { actionError = error.localizedDescription }
        }
    }

    private func copySelectedTorrents(_ keyPath: KeyPath<Torrent, String>) {
        let value = torrents.filter { selectedTorrentIDs.contains($0.id) }.map { $0[keyPath: keyPath] }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func exportSelectedTorrent() {
        guard let torrent = selectedTorrent else { return }
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

private struct PendingTorrentFile: Identifiable {
    let id = UUID()
    let name: String
    let data: Data
}

private struct AddTorrentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let file: PendingTorrentFile?
    let onAdd: (String, TorrentAddOptions) async throws -> Void
    @State private var url = ""
    @State private var savePath = ""
    @State private var category = ""
    @State private var tags = ""
    @State private var stopped = false
    @State private var sequential = false
    @State private var firstLastPiece = false
    @State private var automaticManagement = false
    @State private var downloadLimit = 0
    @State private var uploadLimit = 0
    @State private var errorMessage: String?
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(file == nil ? "Add Torrent URL" : "Add Torrent File")
                    .font(.title2.weight(.semibold))
                Text(file?.name ?? "Enter a magnet link or a URL to a .torrent file.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if file == nil {
                TextField("magnet:?xt=… or https://…", text: $url)
                    .textFieldStyle(.roundedBorder)
            }
            Form {
                TextField("Save location", text: $savePath, prompt: Text("Backend default"))
                TextField("Category", text: $category)
                TextField("Tags (comma separated)", text: $tags)
                Toggle("Add stopped", isOn: $stopped)
                Toggle("Automatic torrent management", isOn: $automaticManagement)
                Toggle("Download in sequential order", isOn: $sequential)
                Toggle("Prioritize first and last pieces", isOn: $firstLastPiece)
                TextField("Download limit (KiB/s; 0 = unlimited)", value: $downloadLimit, format: .number)
                TextField("Upload limit (KiB/s; 0 = unlimited)", value: $uploadLimit, format: .number)
            }
            .formStyle(.grouped)
            .frame(height: 375)
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
                            options.category = category.trimmingCharacters(in: .whitespacesAndNewlines)
                            options.tags = tags.trimmingCharacters(in: .whitespacesAndNewlines)
                            options.stopped = stopped
                            options.automaticManagement = automaticManagement
                            options.sequential = sequential
                            options.firstLastPiece = firstLastPiece
                            options.downloadLimitKiB = max(0, downloadLimit)
                            options.uploadLimitKiB = max(0, uploadLimit)
                            try await onAdd(url.trimmingCharacters(in: .whitespacesAndNewlines), options)
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
        .frame(width: 540)
    }
}
