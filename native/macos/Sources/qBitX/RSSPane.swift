import SwiftUI

struct RSSPane: View {
    let store: TorrentStore
    @State private var feeds: [RSSFeed] = []
    @State private var selectedFeedID: String?
    @State private var showsAddFeed = false
    @State private var feedURL = ""
    @State private var errorMessage: String?

    private var selectedFeed: RSSFeed? { feeds.first { $0.id == selectedFeedID } }

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
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 190, idealWidth: 230)
            VStack(spacing: 0) {
                HStack {
                    Text(selectedFeed?.title ?? "RSS").font(.headline)
                    Spacer()
                    Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.glass)
                        .help("Refresh feeds")
                }
                .padding(12)
                Divider()
                if let errorMessage {
                    ContentUnavailableView("RSS Unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else if let feed = selectedFeed {
                    if feed.articles.isEmpty {
                        ContentUnavailableView("No Articles", systemImage: "newspaper", description: Text("This feed has no articles."))
                    } else {
                        List(feed.articles) { article in
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
                        }
                    }
                } else {
                    ContentUnavailableView("No Feed Selected", systemImage: "dot.radiowaves.left.and.right", description: Text("Select a feed or add a new one."))
                }
            }
            .frame(minWidth: 350)
        }
        .task(id: store.isConnected) { if store.isConnected { await reload() } }
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
            if selectedFeedID == nil { selectedFeedID = feeds.first?.id }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
