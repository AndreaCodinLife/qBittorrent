import AppKit
import SwiftUI

private struct SearchResultTab: Identifiable {
    let id: Int
    var query: String
    var category: String
    var plugin: String
    var results: [SearchResult]
    var status: String
    var total: Int
    var resultFilter = ""
    var minimumSeeders = ""
    var maximumSeeders = ""
    var minimumSize = ""
    var maximumSize = ""
    var minimumSizeUnit: SearchSizeUnit = .mebibytes
    var maximumSizeUnit: SearchSizeUnit = .gibibytes
}

private enum SearchSizeUnit: String, CaseIterable, Identifiable, Equatable {
    case bytes, kibibytes, mebibytes, gibibytes, tebibytes, pebibytes, exbibytes
    var id: String { rawValue }
    var label: String {
        switch self {
        case .bytes: "B"
        case .kibibytes: "KiB"
        case .mebibytes: "MiB"
        case .gibibytes: "GiB"
        case .tebibytes: "TiB"
        case .pebibytes: "PiB"
        case .exbibytes: "EiB"
        }
    }
    var multiplier: Double { pow(1024, Double(Self.allCases.firstIndex(of: self) ?? 0)) }
}

private enum SearchNameFilterMode: String, CaseIterable, Identifiable {
    case torrentNamesOnly, everywhere
    var id: String { rawValue }
    var label: String {
        switch self {
        case .torrentNamesOnly: "Torrent names only"
        case .everywhere: "Everywhere"
        }
    }
}

struct SearchPane: View {
    let store: TorrentStore
    @Binding var isSearchTabVisible: Bool
    @AppStorage("qBitX.showTorrentAdditionDialog") private var showTorrentAdditionDialog = true
    @AppStorage("qBitX.searchHistoryJSON") private var searchHistoryJSON = "[]"
    @AppStorage("qBitX.searchHistoryLength") private var searchHistoryLength = 50
    @AppStorage("qBitX.closeSearchTabWithMiddleClick") private var closeSearchTabWithMiddleClick = true
    @AppStorage("qBitX.systemNotificationsEnabled") private var systemNotificationsEnabled = true
    @AppStorage("qBitX.notifySearchComplete") private var notifyOnSearchComplete = true
    @State private var query = ""
    @State private var searchTabs: [SearchResultTab] = []
    @State private var selectedSearchTabID: Int?
    @State private var plugins: [SearchPlugin] = []
    @State private var selectedCategory = "all"
    @State private var selectedPlugin = "enabled"
    @State private var showsPlugins = false
    @State private var addOptionsSearchResult: SearchResult?
    @State private var pendingAddOptionsResults: [SearchResult] = []
    @State private var errorMessage: String?
    @State private var searchStartTasks: [UUID: Task<Void, Never>] = [:]
    @State private var searchTasks: [Int: Task<Void, Never>] = [:]
    @AppStorage("qBitX.searchFilterRegex") private var filterAsRegex = false
    @AppStorage("qBitX.searchNameFilterMode") private var nameFilterMode = SearchNameFilterMode.torrentNamesOnly
    @State private var selectedResultIDs: Set<String> = []
    @State private var searchSortOrder = [KeyPathComparator<SearchResult>(\.fileName)]
    @SceneStorage("qBitX.searchResultColumns") private var columnCustomization = TableColumnCustomization<SearchResult>()

    private var enabledPlugins: [SearchPlugin] { plugins.filter { $0.enabled == true } }
    private var selectedSearchTab: SearchResultTab? { searchTabs.first { $0.id == selectedSearchTabID } }
    private var searching: Bool { !searchStartTasks.isEmpty || !searchTasks.isEmpty }
    private var searchHistory: [String] {
        guard searchHistoryLength > 0 else { return [] }
        return Array(((try? JSONDecoder().decode([String].self, from: Data(searchHistoryJSON.utf8))) ?? []).prefix(searchHistoryLength))
    }
    private var categories: [SearchCategory] {
        let found = enabledPlugins.flatMap { $0.supportedCategories ?? [] }
        return Array(Dictionary(grouping: found, by: \.id).compactMapValues(\.first).values)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var filteredResults: [SearchResult] {
        guard let tab = selectedSearchTab else { return [] }
        let pattern = tab.resultFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let regex = filterAsRegex && !pattern.isEmpty ? try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) : nil
        let wildcardRegex = !filterAsRegex && !pattern.isEmpty
            ? try? NSRegularExpression(
                pattern: NSRegularExpression.escapedPattern(for: pattern)
                    .replacingOccurrences(of: "\\*", with: ".*")
                    .replacingOccurrences(of: "\\?", with: "."),
                options: [.caseInsensitive]
            )
            : nil
        let minimumSizeBytes = parsedSize(tab.minimumSize, unit: tab.minimumSizeUnit)
        let maximumSizeBytes = parsedSize(tab.maximumSize, unit: tab.maximumSizeUnit)
        let minimumSeeds = Int(tab.minimumSeeders).map { max(0, $0) }.flatMap { $0 > 0 ? $0 : nil }
        let maximumSeeds = Int(tab.maximumSeeders).map { max(0, $0) }.flatMap { $0 > 0 ? $0 : nil }
        let searchWords = tab.query.split(whereSeparator: \.isWhitespace)
        return tab.results.filter { result in
            let matchesSearchName = nameFilterMode == .everywhere || searchWords.allSatisfy {
                result.fileName.localizedCaseInsensitiveContains(String($0))
            }
            let searchableText = [
                result.fileName, ByteCountFormatter.string(fromByteCount: result.fileSize, countStyle: .file),
                "\(result.nbSeeders)", "\(result.nbLeechers)", result.engineName, result.siteUrl, result.descrLink,
                publicationDate(result.pubDate)
            ].joined(separator: " ")
            let matchesTextFilter: Bool
            if pattern.isEmpty { matchesTextFilter = true }
            else if filterAsRegex {
                if let regex {
                    let range = NSRange(searchableText.startIndex..., in: searchableText)
                    matchesTextFilter = regex.firstMatch(in: searchableText, range: range) != nil
                } else {
                    matchesTextFilter = false
                }
            } else {
                if let wildcardRegex {
                    let range = NSRange(searchableText.startIndex..., in: searchableText)
                    matchesTextFilter = wildcardRegex.firstMatch(in: searchableText, range: range) != nil
                } else {
                    matchesTextFilter = false
                }
            }
            return matchesSearchName && matchesTextFilter
                && (minimumSeeds.map { result.nbSeeders >= $0 } ?? true)
                && (maximumSeeds.map { result.nbSeeders <= $0 } ?? true)
                && (minimumSizeBytes.map { Double(result.fileSize) >= $0 } ?? true)
                && (maximumSizeBytes.map { Double(result.fileSize) <= $0 } ?? true)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Search torrents…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search torrents")
                    .onSubmit(search)
                Button("Search", action: search)
                    .buttonStyle(.glassProminent)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.isConnected)
                if let selectedSearchTab, selectedSearchTab.status == "Running" {
                    Button("Stop") { stopSearch(selectedSearchTab.id) }.buttonStyle(.glass)
                }
                Menu("History") {
                    if searchHistory.isEmpty {
                        Text("No recent searches")
                    } else {
                        ForEach(searchHistory, id: \.self) { item in
                            Button(item) { query = item; search() }
                        }
                        Divider()
                        Button("Clear Search History", role: .destructive) { searchHistoryJSON = "[]" }
                    }
                }
                .buttonStyle(.glass)
                Button("Plugins…") { showsPlugins = true }.buttonStyle(.glass)
                if searching { ProgressView().controlSize(.small) }
            }
            .padding(14)
            HStack(spacing: 12) {
                Picker("Category", selection: $selectedCategory) {
                    Text("All categories").tag("all")
                    ForEach(categories.filter { $0.id != "all" }, id: \.id) { category in Text(category.name).tag(category.id) }
                }
                Picker("Plugin", selection: $selectedPlugin) {
                    Text("All enabled plugins").tag("enabled")
                    ForEach(enabledPlugins) { plugin in Text(plugin.fullName ?? plugin.name).tag(plugin.name) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            Divider()
            if !searchTabs.isEmpty {
                ScrollView(.horizontal) {
                    GlassEffectContainer(spacing: 6) {
                        HStack(spacing: 6) {
                            ForEach(searchTabs) { tab in
                                HStack(spacing: 4) {
                                    Button {
                                        selectedSearchTabID = tab.id
                                        query = tab.query
                                        selectedResultIDs = []
                                        selectedCategory = tab.category
                                        selectedPlugin = tab.plugin
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text(tab.query).lineLimit(1)
                                            if tab.status == "Running" { ProgressView().controlSize(.mini) }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Search for \(tab.query)")
                                    .accessibilityValue(tab.status)
                                    .accessibilityAddTraits(selectedSearchTabID == tab.id ? .isSelected : [])

                                    Button { closeSearchTab(tab.id) } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption2.weight(.semibold))
                                            .frame(width: 18, height: 18)
                                            .contentShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Close search for \(tab.query)")
                                    .accessibilityHint(tab.status == "Running" ? "Stops this search and closes its tab." : "Closes this search tab.")
                                }
                                .font(.caption.weight(.medium))
                                .padding(.leading, 10)
                                .padding(.trailing, 4)
                                .padding(.vertical, 6)
                                .glassEffect(selectedSearchTabID == tab.id ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
                                .background {
                                    if closeSearchTabWithMiddleClick {
                                        SearchTabMiddleClickMonitor { closeSearchTab(tab.id) }
                                            .allowsHitTesting(false)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
                Divider()
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 8)
            }
            if enabledPlugins.isEmpty {
                ContentUnavailableView("No Search Plugins", systemImage: "puzzlepiece", description: Text("Use Plugins to install or enable a search engine."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedSearchTab?.results.isEmpty != false {
                ContentUnavailableView(selectedSearchTab == nil ? "Search Torrents" : selectedSearchTab?.status == "Running" ? "Searching…" : "No Results", systemImage: "magnifyingglass", description: Text(selectedSearchTab == nil ? "Search with the enabled qBittorrent plugins." : "Try a different search."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("Filter search results…", text: tabBinding(\.resultFilter, default: ""))
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Filter search results")
                            Picker("Search in", selection: $nameFilterMode) {
                                ForEach(SearchNameFilterMode.allCases) { mode in Text(LocalizedStringKey(mode.label)).tag(mode) }
                            }
                            .frame(width: 170)
                            .help("Choose whether the original search query filters torrent names.")
                            Menu {
                                Toggle("Use regular expressions", isOn: $filterAsRegex)
                                Divider()
                                Button("Clear Filters", action: clearFilters)
                            } label: {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                            }
                            .buttonStyle(.glass)
                            .help("Search result filter options")
                            .accessibilityLabel("Search result filter options")
                            .accessibilityHint("Change regex matching or clear all search result filters.")
                        }
                        HStack(spacing: 7) {
                            Text("Seeds")
                            TextField("Min", text: tabBinding(\.minimumSeeders, default: "")).frame(width: 70).textFieldStyle(.roundedBorder)
                            Text("to")
                            TextField("Max", text: tabBinding(\.maximumSeeders, default: "")).frame(width: 70).textFieldStyle(.roundedBorder)
                            Divider().frame(height: 22)
                            Text("Size")
                            TextField("Min", text: tabBinding(\.minimumSize, default: "")).frame(width: 70).textFieldStyle(.roundedBorder)
                            Picker("Minimum size unit", selection: tabBinding(\.minimumSizeUnit, default: .mebibytes)) {
                                ForEach(SearchSizeUnit.allCases) { unit in Text(unit.label).tag(unit) }
                            }
                            .labelsHidden().frame(width: 66)
                            Text("to")
                            TextField("Max", text: tabBinding(\.maximumSize, default: "")).frame(width: 70).textFieldStyle(.roundedBorder)
                            Picker("Maximum size unit", selection: tabBinding(\.maximumSizeUnit, default: .gibibytes)) {
                                ForEach(SearchSizeUnit.allCases) { unit in Text(unit.label).tag(unit) }
                            }
                            .labelsHidden().frame(width: 66)
                        }
                    }
                    .padding(12)
                    HStack {
                        Text("Showing \(filteredResults.count) of \(selectedSearchTab?.total ?? 0) results")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if !selectedResultIDs.isEmpty {
                            Button("Download Selected (\(selectedResultIDs.count))") {
                                let selected = (selectedSearchTab?.results ?? []).filter { selectedResultIDs.contains($0.id) }
                                downloadSearchResults(selected)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    Table(filteredResults, selection: $selectedResultIDs, sortOrder: $searchSortOrder, columnCustomization: $columnCustomization) {
                        TableColumn("Name", value: \.fileName) { result in Text(result.fileName).lineLimit(1).help(result.fileName) }.customizationID("name")
                        TableColumn("Size", value: \.fileSize) { result in Text(ByteCountFormatter.string(fromByteCount: result.fileSize, countStyle: .file)) }.width(85).customizationID("size")
                        TableColumn("Seeders", value: \.nbSeeders) { result in Text("\(result.nbSeeders)") }.width(65).customizationID("seeders")
                        TableColumn("Leechers", value: \.nbLeechers) { result in Text("\(result.nbLeechers)") }.width(65).customizationID("leechers")
                        TableColumn("Engine", value: \.engineName) { result in Text(result.engineName).lineLimit(1) }.width(100).customizationID("engine")
                        TableColumn("Engine URL", value: \.siteUrl) { result in Text(result.siteUrl).lineLimit(1).help(result.siteUrl) }.width(180).customizationID("engine-url")
                        TableColumn("Published On", value: \.pubDate) { result in Text(publicationDate(result.pubDate)) }.width(150).customizationID("published")
                        TableColumn("Download") { result in
                            Button("Download") { downloadSearchResults([result]) }
                                .buttonStyle(.glass)
                        }.width(90)
                    }
                    .contextMenu(forSelectionType: String.self) { selectedIDs in
                        let selected = (selectedSearchTab?.results ?? []).filter { selectedIDs.contains($0.id) }
                        Button("Download Selected") { downloadSearchResults(selected) }
                            .disabled(selected.isEmpty)
                        Button("Open Description Page") { openDescriptionPages(selected) }
                            .disabled(selected.allSatisfy { $0.descrLink.isEmpty })
                        Button("Open Download Window…") { openDownloadWindows(selected) }
                            .disabled(selected.isEmpty)
                        Menu("Copy") {
                            Button("Names") { copy(selected.map(\.fileName)) }
                            Button("Download Links") { copy(selected.map(\.fileUrl)) }
                            Button("Description Page URLs") { copy(selected.map(\.descrLink)) }
                        }
                        .disabled(selected.isEmpty)
                    }
                    .overlay {
                        if filteredResults.isEmpty {
                            ContentUnavailableView("No Matching Results", systemImage: "line.3.horizontal.decrease.circle", description: Text("Change or clear the search filters."))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: store.isConnected) {
            guard store.isConnected else { return }
            do { plugins = try await store.searchPlugins() }
            catch { errorMessage = error.localizedDescription }
            await restoreSearchJobs()
        }
        .sheet(isPresented: $showsPlugins, onDismiss: {
            Task { plugins = (try? await store.searchPlugins()) ?? plugins }
        }) { SearchPluginsView(store: store) }
        .sheet(item: $addOptionsSearchResult, onDismiss: presentNextAddOptions) { result in
            AddTorrentSheet(file: nil, store: store, initialURL: result.fileUrl, initialDownloader: result.engineName) { url, downloader, options in
                try await store.add(url: url, downloader: downloader, options: options)
                return false
            }
        }
        .onChange(of: searchHistoryLength) { _, length in
            let existing = (try? JSONDecoder().decode([String].self, from: Data(searchHistoryJSON.utf8))) ?? []
            let updated = length == 0 ? [] : Array(existing.prefix(length))
            if let data = try? JSONEncoder().encode(updated) { searchHistoryJSON = String(decoding: data, as: UTF8.self) }
        }
        .onDisappear { stopAllSearches() }
    }

    private func search() {
        let pattern = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }
        errorMessage = nil
        if searchHistoryLength > 0 {
            var history = searchHistory.filter { $0.localizedCaseInsensitiveCompare(pattern) != .orderedSame }
            history.insert(pattern, at: 0)
            if history.count > searchHistoryLength { history.removeLast(history.count - searchHistoryLength) }
            if let data = try? JSONEncoder().encode(history) { searchHistoryJSON = String(decoding: data, as: UTF8.self) }
        }
        let requestID = UUID()
        let task = Task {
            defer { searchStartTasks[requestID] = nil }
            do {
                let id = try await store.startSearch(pattern, category: selectedCategory, plugin: selectedPlugin)
                guard !Task.isCancelled else {
                    try? await store.stopSearch(id)
                    return
                }
                selectedSearchTabID = id
                selectedResultIDs = []
                searchTabs.append(SearchResultTab(id: id, query: pattern, category: selectedCategory, plugin: selectedPlugin, results: [], status: "Running", total: 0))
                let pollingTask = Task { await pollSearch(id) }
                searchTasks[id] = pollingTask
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        searchStartTasks[requestID] = task
    }

    private func pollSearch(_ id: Int) async {
        defer { searchTasks[id] = nil }
        do {
            while !Task.isCancelled {
                try Task.checkCancellation()
                let response = try await store.searchResults(id)
                updateSearchTab(id, response: response)
                if response.status != "Running" {
                    if response.status != "Stopped", !isSearchTabVisible, systemNotificationsEnabled, notifyOnSearchComplete {
                        let failed = response.status.localizedCaseInsensitiveContains("error")
                            || response.status.localizedCaseInsensitiveContains("fail")
                        MacOSNotifications.post(
                            title: "Search Engine",
                            body: failed ? "Search has failed." : "Search has finished."
                        )
                    }
                    return
                }
                try await Task.sleep(for: .seconds(1))
            }
        } catch is CancellationError {
            return
        } catch {
            if let index = searchTabs.firstIndex(where: { $0.id == id }) { searchTabs[index].status = "Error" }
            errorMessage = error.localizedDescription
            if !isSearchTabVisible, systemNotificationsEnabled, notifyOnSearchComplete {
                MacOSNotifications.post(title: "Search Engine", body: "Search has failed.")
            }
        }
    }

    private func restoreSearchJobs() async {
        do {
            let jobs = try await store.searchJobs()
            for job in jobs {
                let plugin = job.plugins.isEmpty ? "enabled" : job.plugins.joined(separator: "|")
                if let index = searchTabs.firstIndex(where: { $0.id == job.id }) {
                    searchTabs[index].query = job.pattern
                    searchTabs[index].category = job.category
                    searchTabs[index].plugin = plugin
                } else {
                    searchTabs.append(SearchResultTab(
                        id: job.id,
                        query: job.pattern,
                        category: job.category,
                        plugin: plugin,
                        results: [],
                        status: job.status,
                        total: job.total
                    ))
                }

                do {
                    let response = try await store.searchResults(job.id)
                    updateSearchTab(job.id, response: response)
                    if response.status == "Running", searchTasks[job.id] == nil {
                        searchTasks[job.id] = Task { await pollSearch(job.id) }
                    }
                } catch {
                    if let index = searchTabs.firstIndex(where: { $0.id == job.id }) {
                        searchTabs[index].status = "Error"
                    }
                    errorMessage = error.localizedDescription
                }
            }

            if selectedSearchTabID == nil, let last = searchTabs.last {
                selectedSearchTabID = last.id
                query = last.query
                selectedCategory = last.category
                selectedPlugin = last.plugin
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopSearch(_ id: Int) {
        searchTasks[id]?.cancel()
        searchTasks[id] = nil
        if let index = searchTabs.firstIndex(where: { $0.id == id }), searchTabs[index].status == "Running" {
            searchTabs[index].status = "Stopped"
        }
        Task {
            do { try await store.stopSearch(id) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func stopAllSearches() {
        for task in searchStartTasks.values { task.cancel() }
        searchStartTasks.removeAll()
        for id in Array(searchTasks.keys) { stopSearch(id) }
    }

    private func updateSearchTab(_ id: Int, response: SearchResultsResponse) {
        guard let index = searchTabs.firstIndex(where: { $0.id == id }) else { return }
        searchTabs[index].results = response.results
        searchTabs[index].status = response.status
        searchTabs[index].total = response.total
    }

    private func parsedSize(_ value: String, unit: SearchSizeUnit) -> Double? {
        guard let amount = Double(value), amount > 0, amount.isFinite else { return nil }
        let bytes = amount * unit.multiplier
        return bytes.isFinite ? bytes : nil
    }

    private func tabBinding<Value>(_ keyPath: WritableKeyPath<SearchResultTab, Value>, default defaultValue: Value) -> Binding<Value> {
        Binding(
            get: { searchTabs.first(where: { $0.id == selectedSearchTabID })?[keyPath: keyPath] ?? defaultValue },
            set: { value in
                guard let index = searchTabs.firstIndex(where: { $0.id == selectedSearchTabID }) else { return }
                searchTabs[index][keyPath: keyPath] = value
            }
        )
    }

    private func clearFilters() {
        tabBinding(\.resultFilter, default: "").wrappedValue = ""
        tabBinding(\.minimumSeeders, default: "").wrappedValue = ""
        tabBinding(\.maximumSeeders, default: "").wrappedValue = ""
        tabBinding(\.minimumSize, default: "").wrappedValue = ""
        tabBinding(\.maximumSize, default: "").wrappedValue = ""
        filterAsRegex = false
    }

    private func publicationDate(_ timestamp: Int64) -> String {
        guard timestamp > 0 else { return "—" }
        return Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(date: .abbreviated, time: .shortened)
    }

    private func downloadSearchResults(_ results: [SearchResult]) {
        guard !results.isEmpty else { return }
        if showTorrentAdditionDialog {
            openDownloadWindows(results)
            return
        }
        Task {
            for result in results {
                do { try await store.downloadSearchResult(result) }
                catch { errorMessage = error.localizedDescription; return }
            }
        }
    }

    private func openDescriptionPages(_ results: [SearchResult]) {
        for result in results {
            guard let url = URL(string: result.descrLink),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { continue }
            NSWorkspace.shared.open(url)
        }
    }

    private func openDownloadWindows(_ results: [SearchResult]) {
        guard let first = results.first else { return }
        pendingAddOptionsResults = Array(results.dropFirst())
        addOptionsSearchResult = first
    }

    private func presentNextAddOptions() {
        guard !pendingAddOptionsResults.isEmpty else { return }
        addOptionsSearchResult = pendingAddOptionsResults.removeFirst()
    }

    private func copy(_ values: [String]) {
        let values = values.filter { !$0.isEmpty }
        guard !values.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(values.joined(separator: "\n"), forType: .string)
    }

    private func closeSearchTab(_ id: Int) {
        let shouldStop = searchTasks[id] != nil || searchTabs.first(where: { $0.id == id })?.status == "Running"
        searchTasks[id]?.cancel()
        searchTasks[id] = nil
        if let index = searchTabs.firstIndex(where: { $0.id == id }), searchTabs[index].status == "Running" {
            searchTabs[index].status = "Stopped"
        }
        searchTabs.removeAll { $0.id == id }
        if selectedSearchTabID == id {
            selectedSearchTabID = searchTabs.last?.id
            if let selectedSearchTab {
                query = selectedSearchTab.query
                selectedCategory = selectedSearchTab.category
                selectedPlugin = selectedSearchTab.plugin
            }
        }
        Task {
            if shouldStop { try? await store.stopSearch(id) }
            do { try await store.deleteSearch(id) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct SearchTabMiddleClickMonitor: NSViewRepresentable {
    let onMiddleClick: () -> Void

    func makeNSView(context: Context) -> SearchTabMiddleClickView {
        let view = SearchTabMiddleClickView()
        view.onMiddleClick = onMiddleClick
        return view
    }

    func updateNSView(_ view: SearchTabMiddleClickView, context: Context) {
        view.onMiddleClick = onMiddleClick
    }
}

private final class SearchTabMiddleClickView: NSView {
    var onMiddleClick: (() -> Void)?
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            eventMonitor = nil
            return
        }
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
            guard event.buttonNumber == 2,
                  let self,
                  let window = self.window,
                  event.window === window else { return event }

            let point = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(point) else { return event }
            self.onMiddleClick?()
            return nil
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
