import SwiftUI

struct SearchPane: View {
    let store: TorrentStore
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var plugins: [SearchPlugin] = []
    @State private var selectedCategory = "all"
    @State private var selectedPlugin = "enabled"
    @State private var showsPlugins = false
    @State private var activeSearchID: Int?
    @State private var searching = false
    @State private var searched = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    private var enabledPlugins: [SearchPlugin] { plugins.filter { $0.enabled == true } }
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
            if let errorMessage {
                ContentUnavailableView("Search Unavailable", systemImage: "magnifyingglass", description: Text(errorMessage))
            } else if enabledPlugins.isEmpty {
                ContentUnavailableView("No Search Plugins", systemImage: "puzzlepiece", description: Text("Use Plugins to install or enable a search engine."))
            } else if results.isEmpty {
                ContentUnavailableView(searched ? "No Results" : "Search Torrents", systemImage: "magnifyingglass", description: Text(searched ? "Try a different search." : "Search with the enabled qBittorrent plugins."))
            } else {
                Table(results) {
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
        searchTask?.cancel()
        results = []
        errorMessage = nil
        searched = true
        searching = true
        searchTask = Task {
            defer { searching = false }
            do {
                let id = try await store.startSearch(pattern, category: selectedCategory, plugin: selectedPlugin)
                activeSearchID = id
                for _ in 0..<60 {
                    try Task.checkCancellation()
                    let response = try await store.searchResults(id)
                    results = response.results
                    if response.status != "Running" { activeSearchID = nil; return }
                    try await Task.sleep(for: .seconds(1))
                }
                try await store.stopSearch(id)
                activeSearchID = nil
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func stopSearch() {
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
}
