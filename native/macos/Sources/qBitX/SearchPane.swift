import SwiftUI

private struct SearchResultTab: Identifiable {
    let id: Int
    let query: String
    let category: String
    let plugin: String
    var results: [SearchResult]
    var status: String
}

struct SearchPane: View {
    let store: TorrentStore
    @AppStorage("qBitX.searchHistoryJSON") private var searchHistoryJSON = "[]"
    @State private var query = ""
    @State private var searchTabs: [SearchResultTab] = []
    @State private var selectedSearchTabID: Int?
    @State private var plugins: [SearchPlugin] = []
    @State private var selectedCategory = "all"
    @State private var selectedPlugin = "enabled"
    @State private var showsPlugins = false
    @State private var activeSearchID: Int?
    @State private var searching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var searchRequestID = UUID()

    private var enabledPlugins: [SearchPlugin] { plugins.filter { $0.enabled == true } }
    private var selectedSearchTab: SearchResultTab? { searchTabs.first { $0.id == selectedSearchTabID } }
    private var searchHistory: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(searchHistoryJSON.utf8))) ?? []
    }
    private var categories: [SearchCategory] {
        let found = enabledPlugins.flatMap { $0.supportedCategories ?? [] }
        return Array(Dictionary(grouping: found, by: \.id).compactMapValues(\.first).values)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Search torrents…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(search)
                Button("Search", action: search)
                    .buttonStyle(.glassProminent)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searching || !store.isConnected)
                if searching { Button("Stop", action: stopSearch).buttonStyle(.glass) }
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
                    HStack(spacing: 6) {
                        ForEach(searchTabs) { tab in
                            Button {
                                selectedSearchTabID = tab.id
                                query = tab.query
                                selectedCategory = tab.category
                                selectedPlugin = tab.plugin
                            } label: {
                                HStack(spacing: 6) {
                                    Text(tab.query).lineLimit(1)
                                    if tab.status == "Running" { ProgressView().controlSize(.mini) }
                                    Text("×")
                                        .foregroundStyle(.secondary)
                                        .onTapGesture { closeSearchTab(tab.id) }
                                }
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .glassEffect(selectedSearchTabID == tab.id ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
                            }
                            .buttonStyle(.plain)
                            .help("\(tab.query) — \(tab.status)")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                Divider()
            }
            if let errorMessage {
                ContentUnavailableView("Search Unavailable", systemImage: "magnifyingglass", description: Text(errorMessage))
            } else if enabledPlugins.isEmpty {
                ContentUnavailableView("No Search Plugins", systemImage: "puzzlepiece", description: Text("Use Plugins to install or enable a search engine."))
            } else if selectedSearchTab?.results.isEmpty != false {
                ContentUnavailableView(selectedSearchTab == nil ? "Search Torrents" : selectedSearchTab?.status == "Running" ? "Searching…" : "No Results", systemImage: "magnifyingglass", description: Text(selectedSearchTab == nil ? "Search with the enabled qBittorrent plugins." : "Try a different search."))
            } else {
                Table(selectedSearchTab?.results ?? []) {
                    TableColumn("Name") { result in Text(result.fileName).lineLimit(1) }
                    TableColumn("Size") { result in Text(ByteCountFormatter.string(fromByteCount: result.fileSize, countStyle: .file)) }.width(85)
                    TableColumn("Seeds") { result in Text("\(result.nbSeeders)") }.width(55)
                    TableColumn("Peers") { result in Text("\(result.nbLeechers)") }.width(55)
                    TableColumn("Engine") { result in Text(result.engineName) }.width(100)
                    TableColumn("Add") { result in
                        Button("Add") {
                            Task {
                                do { try await store.downloadSearchResult(result) }
                                catch { errorMessage = error.localizedDescription }
                            }
                        }
                        .buttonStyle(.glass)
                    }.width(55)
                }
            }
        }
        .task(id: store.isConnected) {
            guard store.isConnected else { return }
            do { plugins = try await store.searchPlugins() }
            catch { errorMessage = error.localizedDescription }
        }
        .sheet(isPresented: $showsPlugins, onDismiss: {
            Task { plugins = (try? await store.searchPlugins()) ?? plugins }
        }) { SearchPluginsView(store: store) }
        .onDisappear { stopSearch() }
    }

    private func search() {
        let pattern = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }
        stopSearch()
        let requestID = UUID()
        searchRequestID = requestID
        errorMessage = nil
        searching = true
        var history = searchHistory.filter { $0.localizedCaseInsensitiveCompare(pattern) != .orderedSame }
        history.insert(pattern, at: 0)
        if history.count > 30 { history.removeLast(history.count - 30) }
        if let data = try? JSONEncoder().encode(history) { searchHistoryJSON = String(decoding: data, as: UTF8.self) }
        searchTask = Task {
            defer { if searchRequestID == requestID { searching = false } }
            do {
                let id = try await store.startSearch(pattern, category: selectedCategory, plugin: selectedPlugin)
                guard !Task.isCancelled, searchRequestID == requestID else {
                    try? await store.stopSearch(id)
                    return
                }
                activeSearchID = id
                selectedSearchTabID = id
                searchTabs.append(SearchResultTab(id: id, query: pattern, category: selectedCategory, plugin: selectedPlugin, results: [], status: "Running"))
                if searchTabs.count > 20 { searchTabs.removeFirst(searchTabs.count - 20) }
                for _ in 0..<60 {
                    try Task.checkCancellation()
                    let response = try await store.searchResults(id)
                    updateSearchTab(id, results: response.results, status: response.status)
                    if response.status != "Running" { activeSearchID = nil; return }
                    try await Task.sleep(for: .seconds(1))
                }
                try await store.stopSearch(id)
                updateSearchTab(id, results: searchTabs.first { $0.id == id }?.results ?? [], status: "Stopped")
                activeSearchID = nil
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func stopSearch() {
        searchRequestID = UUID()
        searchTask?.cancel()
        searching = false
        if let id = activeSearchID {
            activeSearchID = nil
            Task {
                do { try await store.stopSearch(id) }
                catch { errorMessage = error.localizedDescription }
            }
        }
    }

    private func updateSearchTab(_ id: Int, results: [SearchResult], status: String) {
        guard let index = searchTabs.firstIndex(where: { $0.id == id }) else { return }
        searchTabs[index].results = results
        searchTabs[index].status = status
    }

    private func closeSearchTab(_ id: Int) {
        if activeSearchID == id { stopSearch() }
        searchTabs.removeAll { $0.id == id }
        if selectedSearchTabID == id {
            selectedSearchTabID = searchTabs.last?.id
            if let selectedSearchTab {
                query = selectedSearchTab.query
                selectedCategory = selectedSearchTab.category
                selectedPlugin = selectedSearchTab.plugin
            }
        }
    }
}
