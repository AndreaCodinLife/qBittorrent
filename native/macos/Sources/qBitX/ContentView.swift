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

struct ContentView: View {
    @State private var store = TorrentStore()
    @State private var selectedTorrentID: String?
    @State private var statusFilter: TorrentFilter = .all
    @State private var categoryFilter: String?
    @State private var tagFilter: String?
    @State private var trackerFilter: String?
    @State private var searchText = ""
    @State private var mainTab: MainTab = .transfers
    @State private var detailTab: DetailTab = .general
    @State private var showsURLSheet = false
    @State private var showsFileImporter = false
    @State private var showsRemoveConfirmation = false
    @State private var showsConnectionSettings = false
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
        }
    }

    private var selectedTorrent: Torrent? {
        torrents.first { $0.id == selectedTorrentID }
    }

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
            if selectedTorrentID == nil { selectedTorrentID = ids.first }
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

                Button { runAction { try await store.start($0) } } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .disabled(selectedTorrent == nil)

                Button { runAction { try await store.stop($0) } } label: {
                    Label("Stop", systemImage: "pause.fill")
                }
                .disabled(selectedTorrent == nil)

                Button {
                    if let path = selectedTorrent?.savePath, !path.isEmpty {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                } label: {
                    Label("Open Destination", systemImage: "folder")
                }
                .disabled(selectedTorrent?.savePath.isEmpty ?? true)

                Button { showsConnectionSettings = true } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Choose a qBittorrent library")
            }
        }
        .sheet(isPresented: $showsURLSheet) {
            AddURLSheet { url in
                try await store.add(url: url)
            }
        }
        .sheet(isPresented: $showsConnectionSettings) {
            ConnectionSettingsView(store: store) { retryID += 1 }
        }
        .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [UTType(filenameExtension: "torrent") ?? .data]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                Task {
                    do { try await store.add(file: data, filename: url.lastPathComponent) }
                    catch { actionError = error.localizedDescription }
                }
            } catch { actionError = error.localizedDescription }
        }
        .confirmationDialog("Remove this torrent?", isPresented: $showsRemoveConfirmation) {
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
                Text("Filter by:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Name")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var torrentTable: some View {
        Table(visibleTorrents, selection: $selectedTorrentID) {
            TableColumn("Name") { torrent in
                Label(torrent.name, systemImage: "doc.zipper").lineLimit(1)
            }
            .width(min: 200, ideal: 270)
            TableColumn("Size", value: \.size).width(80)
            TableColumn("Progress") { torrent in
                HStack(spacing: 6) {
                    ProgressView(value: torrent.progress)
                    Text(torrent.progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit())
                        .frame(width: 32, alignment: .trailing)
                }
            }
            .width(min: 110, ideal: 140)
            TableColumn("Status") { torrent in Text(torrent.state.rawValue) }.width(95)
            TableColumn("Seeds") { torrent in Text("\(torrent.seeds)") }.width(55)
            TableColumn("Peers") { torrent in Text("\(torrent.peers)") }.width(55)
            TableColumn("Down Speed", value: \.downloadRate).width(90)
            TableColumn("Up Speed", value: \.uploadRate).width(90)
            TableColumn("ETA", value: \.eta).width(70)
        }
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
        HStack(alignment: .top, spacing: 42) {
            VStack(alignment: .leading, spacing: 11) {
                detailLine("Name", torrent.name)
                detailLine("Status", torrent.state.rawValue)
                detailLine("Progress", torrent.progress.formatted(.percent.precision(.fractionLength(0))))
                detailLine("Size", torrent.size)
                if let savePath = properties?.save_path {
                    detailLine("Save path", savePath)
                }
            }
            VStack(alignment: .leading, spacing: 11) {
                detailLine("Download speed", torrent.downloadRate)
                detailLine("Upload speed", torrent.uploadRate)
                detailLine("Peers", "\(torrent.peers)")
                detailLine("Time remaining", torrent.eta)
                detailLine("Ratio", torrent.ratio.formatted(.number.precision(.fractionLength(2))))
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        List(trackers) { tracker in
            HStack {
                Text(tracker.url).lineLimit(1)
                Spacer()
                Text("Seeds: \(tracker.num_seeds ?? 0)")
                Text("Peers: \(tracker.num_peers ?? 0)")
            }
            .font(.caption)
        }
    }

    private var fileDetails: some View {
        List(files) { file in
            HStack {
                Text(file.name).lineLimit(1)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                Text(file.progress.formatted(.percent.precision(.fractionLength(0))))
            }
            .font(.caption)
        }
    }

    private var peerDetails: some View {
        List(peers) { peer in
            HStack(spacing: 16) {
                Text("\(peer.ip):\(peer.port ?? 0)").frame(minWidth: 150, alignment: .leading)
                Text(peer.client ?? "Unknown client").frame(minWidth: 120, alignment: .leading)
                Text((peer.progress ?? 0).formatted(.percent.precision(.fractionLength(0))))
                Spacer()
                Text("↓ \(TransferStatus.rateText(peer.dl_speed ?? 0))")
                Text("↑ \(TransferStatus.rateText(peer.up_speed ?? 0))")
            }
            .font(.caption)
        }
        .overlay {
            if peers.isEmpty { ContentUnavailableView("No Peers", systemImage: "person.2", description: Text("This torrent has no connected peers.")) }
        }
    }

    private var webSeedDetails: some View {
        List(webSeeds) { seed in Text(seed.url).font(.caption).textSelection(.enabled) }
            .overlay {
                if webSeeds.isEmpty { ContentUnavailableView("No HTTP Sources", systemImage: "network", description: Text("This torrent has no web seeds.")) }
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
            case .peers: peers = try await store.peers(for: selectedTorrentID)
            case .httpSources: webSeeds = try await store.webSeeds(for: selectedTorrentID)
            default: break
            }
        } catch is CancellationError {
            return
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func runAction(_ action: @escaping (String) async throws -> Void) {
        guard let selectedTorrentID else { return }
        Task {
            do { try await action(selectedTorrentID) }
            catch { actionError = error.localizedDescription }
        }
    }

    private func removeSelectedTorrent(deleteFiles: Bool) {
        guard let selectedTorrentID else { return }
        Task {
            do {
                try await store.remove(selectedTorrentID, deleteFiles: deleteFiles)
                self.selectedTorrentID = nil
            } catch { actionError = error.localizedDescription }
        }
    }
}

private struct AddURLSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var errorMessage: String?
    @State private var isAdding = false
    let onAdd: (String) async throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Add Torrent URL").font(.title2.weight(.semibold))
                Text("Enter a magnet link or a URL to a .torrent file.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            TextField("magnet:?xt=… or https://…", text: $url)
                .textFieldStyle(.roundedBorder)
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
                            try await onAdd(url.trimmingCharacters(in: .whitespacesAndNewlines))
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                            isAdding = false
                        }
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAdding)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(25)
        .frame(width: 420)
    }
}
