import SwiftUI

struct SearchPane: View {
    let store: TorrentStore
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var plugins: [SearchPlugin] = []
    @State private var searching = false
    @State private var searched = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Search torrents…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(search)
                Button("Search", action: search)
                    .buttonStyle(.glassProminent)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searching || !store.isConnected)
                if searching { ProgressView().controlSize(.small) }
            }
            .padding(14)
            Divider()
            if let errorMessage {
                ContentUnavailableView("Search Unavailable", systemImage: "magnifyingglass", description: Text(errorMessage))
            } else if plugins.isEmpty {
                ContentUnavailableView("No Search Plugins", systemImage: "puzzlepiece", description: Text("Install search plugins in the qBittorrent backend to use Search."))
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
            do { plugins = try await store.searchPlugins().filter { $0.enabled ?? false } }
            catch { errorMessage = error.localizedDescription }
        }
        .onDisappear { searchTask?.cancel() }
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
                let id = try await store.startSearch(pattern)
                for _ in 0..<60 {
                    try Task.checkCancellation()
                    let response = try await store.searchResults(id)
                    results = response.results
                    if response.status != "Running" { return }
                    try await Task.sleep(for: .seconds(1))
                }
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
