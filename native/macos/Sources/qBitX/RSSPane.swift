import SwiftUI

struct RSSPane: View {
    let store: TorrentStore
    @State private var feeds: [RSSFeed] = []
    @State private var selectedFeedID: String?
    @State private var showsAddFeed = false
    @State private var feedURL = ""
    @State private var articleFilter = ""
    @State private var editedFeedURL = ""
    @State private var showsEditFeed = false
    @State private var showsRemoveFeed = false
    @State private var errorMessage: String?

    private var selectedFeed: RSSFeed? { feeds.first { $0.id == selectedFeedID } }
    private var visibleArticles: [RSSArticle] {
        selectedFeed?.articles.filter { articleFilter.isEmpty || $0.title.localizedCaseInsensitiveContains(articleFilter) } ?? []
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("FEEDS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button { showsAddFeed = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.glass)
                        .help("Add RSS feed")
                }
                .padding(12)
                List(selection: $selectedFeedID) {
                    ForEach(feeds) { feed in
                        Label(feed.title, systemImage: "dot.radiowaves.left.and.right")
                            .tag(feed.id)
                            .contextMenu {
                                Button("Refresh") { Task { await refresh(feed) } }
                                Button("Mark All Read") { Task { await markRead(feed) } }
                                Button("Edit URL…") { selectedFeedID = feed.id; editedFeedURL = feed.url; showsEditFeed = true }
                                Button("Remove Feed", role: .destructive) { selectedFeedID = feed.id; showsRemoveFeed = true }
                            }
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 190, idealWidth: 230)
            VStack(spacing: 0) {
                HStack {
                    Text(selectedFeed?.title ?? "RSS").font(.headline)
                    Spacer()
                    Button { if let feed = selectedFeed { Task { await refresh(feed) } } else { Task { await reload() } } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.glass)
                        .help("Refresh feeds")
                }
                .padding(12)
                Divider()
                if let errorMessage {
                    ContentUnavailableView("RSS Unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else if let feed = selectedFeed {
                    TextField("Filter articles…", text: $articleFilter)
                        .textFieldStyle(.roundedBorder)
                        .padding(10)
                    if visibleArticles.isEmpty {
                        ContentUnavailableView("No Articles", systemImage: "newspaper", description: Text("This feed has no articles."))
                    } else {
                        List(visibleArticles) { article in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(article.title).fontWeight(article.isRead ? .regular : .semibold)
                                    Text(article.date).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Add Torrent") {
                                    Task {
                                        do {
                                            try await store.addRSSArticle(article)
                                            try await store.markRSSArticleRead(path: feed.path, articleID: article.id)
                                            await reload()
                                        } catch { errorMessage = error.localizedDescription }
                                    }
                                }
                                .buttonStyle(.glass)
                            }
                            .contextMenu {
                                Button("Mark Read") {
                                    Task {
                                        do { try await store.markRSSArticleRead(path: feed.path, articleID: article.id); await reload() }
                                        catch { errorMessage = error.localizedDescription }
                                    }
                                }
                                if let url = URL(string: article.link), ["http", "https"].contains(url.scheme ?? "") {
                                    Button("Open Article") { NSWorkspace.shared.open(url) }
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("No Feed Selected", systemImage: "dot.radiowaves.left.and.right", description: Text("Select a feed or add a new one."))
                }
            }
            .frame(minWidth: 350)
        }
        .task(id: store.isConnected) { if store.isConnected { await reload() } }
        .confirmationDialog("Remove this RSS feed?", isPresented: $showsRemoveFeed) {
            Button("Remove Feed", role: .destructive) {
                guard let feed = selectedFeed else { return }
                Task {
                    do { try await store.removeRSSFeed(path: feed.path); selectedFeedID = nil; await reload() }
                    catch { errorMessage = error.localizedDescription }
                }
            }
        }
        .sheet(isPresented: $showsEditFeed) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit RSS Feed").font(.title2.weight(.semibold))
                TextField("Feed URL", text: $editedFeedURL).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { showsEditFeed = false }
                    Button("Save") {
                        guard let feed = selectedFeed else { return }
                        Task {
                            do { try await store.editRSSFeed(path: feed.path, url: editedFeedURL); showsEditFeed = false; await reload() }
                            catch { errorMessage = error.localizedDescription }
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(URL(string: editedFeedURL)?.scheme?.hasPrefix("http") != true)
                }
            }
            .padding(22)
            .frame(width: 430)
        }
        .sheet(isPresented: $showsAddFeed) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add RSS Feed").font(.title2.weight(.semibold))
                TextField("https://example.com/feed.xml", text: $feedURL)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { showsAddFeed = false }
                    Button("Add Feed") {
                        Task {
                            do {
                                try await store.addRSSFeed(feedURL.trimmingCharacters(in: .whitespacesAndNewlines))
                                showsAddFeed = false
                                feedURL = ""
                                await reload()
                            } catch { errorMessage = error.localizedDescription }
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(URL(string: feedURL)?.scheme?.hasPrefix("http") != true)
                }
            }
            .padding(22)
            .frame(width: 430)
        }
    }

    private func reload() async {
        do {
            feeds = try await store.rssFeeds()
            if selectedFeedID == nil || !feeds.contains(where: { $0.id == selectedFeedID }) { selectedFeedID = feeds.first?.id }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refresh(_ feed: RSSFeed) async {
        do {
            try await store.refreshRSSFeed(path: feed.path)
            try await Task.sleep(for: .milliseconds(500))
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    private func markRead(_ feed: RSSFeed) async {
        do { try await store.markRSSFeedRead(path: feed.path); await reload() }
        catch { errorMessage = error.localizedDescription }
    }
}
