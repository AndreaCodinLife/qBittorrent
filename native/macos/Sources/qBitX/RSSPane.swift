import SwiftUI
import QBitXThemeSupport

struct RSSPane: View {
    let store: TorrentStore
    @Binding var unreadCount: Int
    @AppStorage("qBitX.themePalette") private var themePaletteJSON = ""
    @Environment(\.colorScheme) private var colorScheme
    @State private var feeds: [RSSFeed] = []
    @State private var selectedFeedID: String?
    @State private var showsAddFeed = false
    @State private var feedURL = ""
    @State private var feedName = ""
    @State private var feedFolder = ""
    @State private var folders: [RSSFolder] = []
    @State private var showsAddFolder = false
    @State private var folderName = ""
    @State private var folderParent = ""
    @State private var showsRenameFolder = false
    @State private var editingFolderPath = ""
    @State private var articleFilter = ""
    @State private var editedFeedURL = ""
    @State private var showsEditFeed = false
    @State private var showsRemoveFeed = false
    @State private var showsMoveFeed = false
    @State private var editingFeedPath = ""
    @State private var newFeedPath = ""
    @State private var showsRules = false
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
                    Button { showsAddFolder = true } label: { Image(systemName: "folder.badge.plus") }
                        .buttonStyle(.glass).help("Add RSS folder")
                        .accessibilityLabel("Add RSS folder")
                    Button { showsAddFeed = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.glass)
                        .help("Add RSS feed")
                        .accessibilityLabel("Add RSS feed")
                }
                .padding(12)
                List(selection: $selectedFeedID) {
                    if !folders.isEmpty {
                        Section("Folders") {
                            ForEach(folders) { folder in
                                Label(folder.title, systemImage: "folder")
                                    .accessibilityLabel("RSS folder, \(folder.title)")
                                    .contextMenu {
                                        Button("Rename Folder…") {
                                            editingFolderPath = folder.path
                                            folderName = (folder.path as NSString).lastPathComponent
                                            showsRenameFolder = true
                                        }
                                        Button("Remove Folder", role: .destructive) {
                                            Task {
                                                do { try await store.removeRSSFeed(path: folder.path); await reload() }
                                                catch { errorMessage = error.localizedDescription }
                                            }
                                        }
                                    }
                            }
                        }
                    }
                    Section("Feeds") {
                        ForEach(feeds) { feed in
                            Label(feed.title, systemImage: "dot.radiowaves.left.and.right")
                                .tag(feed.id)
                                .accessibilityLabel("RSS feed, \(feed.title)")
                                .contextMenu {
                                    Button("Refresh") { Task { await refresh(feed) } }
                                    Button("Mark All Read") { Task { await markRead(feed) } }
                                    Button("Edit URL…") { selectedFeedID = feed.id; editedFeedURL = feed.url; showsEditFeed = true }
                                    Button("Rename or Move…") { editingFeedPath = feed.path; newFeedPath = feed.path; showsMoveFeed = true }
                                    Button("Remove Feed", role: .destructive) { selectedFeedID = feed.id; showsRemoveFeed = true }
                                }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minWidth: 190, idealWidth: 230)
            VStack(spacing: 0) {
                HStack {
                    Text(selectedFeed?.title ?? "RSS").font(.headline)
                    Spacer()
                    Button("Downloader Rules…") { showsRules = true }
                        .buttonStyle(.glass)
                    Button { if let feed = selectedFeed { Task { await refresh(feed) } } else { Task { await reload() } } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.glass)
                        .help("Refresh feeds")
                        .accessibilityLabel(selectedFeed.map { "Refresh \($0.title)" } ?? "Refresh RSS feeds")
                }
                .padding(12)
                Divider()
                if let errorMessage {
                    ContentUnavailableView("RSS Unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let feed = selectedFeed {
                    TextField("Filter articles…", text: $articleFilter)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Filter RSS articles")
                        .padding(10)
                    if visibleArticles.isEmpty {
                        ContentUnavailableView("No Articles", systemImage: "newspaper", description: Text("This feed has no articles."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(visibleArticles) { article in
                            HStack(spacing: 12) {
                                Image(systemName: article.isRead ? "circle" : "circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(articleColor(for: article))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(article.title)
                                        .fontWeight(article.isRead ? .regular : .semibold)
                                        .foregroundStyle(articleColor(for: article))
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
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minWidth: 350)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: store.isConnected) {
            guard store.isConnected else { return }
            await reload()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
                await reload()
            }
        }
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
        .sheet(isPresented: $showsMoveFeed) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Rename or Move RSS Feed").font(.title2.weight(.semibold))
                Text("Enter a new feed path. Use Folder/Feed to place it in a folder.")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextField("Feed path", text: $newFeedPath).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { showsMoveFeed = false }
                    Button("Save") {
                        let path = newFeedPath.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            do { try await store.moveRSSItem(path: editingFeedPath, to: path); showsMoveFeed = false; selectedFeedID = path; await reload() }
                            catch { errorMessage = error.localizedDescription }
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(newFeedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(22)
            .frame(width: 470)
        }
        .sheet(isPresented: $showsAddFeed) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add RSS Feed").font(.title2.weight(.semibold))
                TextField("https://example.com/feed.xml", text: $feedURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Feed name or path (optional)", text: $feedName)
                    .textFieldStyle(.roundedBorder)
                Picker("Folder", selection: $feedFolder) {
                    Text("Root").tag("")
                    ForEach(folders) { folder in Text(folder.path).tag(folder.path) }
                }
                HStack {
                    Spacer()
                    Button("Cancel") { showsAddFeed = false }
                    Button("Add Feed") {
                        Task {
                            do {
                                let url = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
                                let name = feedName.trimmingCharacters(in: .whitespacesAndNewlines)
                                let leaf = name.isEmpty ? url : name
                                let path = feedFolder.isEmpty ? leaf : "\(feedFolder)/\(leaf)"
                                try await store.addRSSFeed(url, path: path)
                                showsAddFeed = false
                                feedURL = ""
                                feedName = ""
                                await reload()
                            } catch { errorMessage = error.localizedDescription }
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(URL(string: feedURL)?.scheme?.hasPrefix("http") != true)
                }
            }
            .padding(22)
            .frame(width: 470)
        }
        .sheet(isPresented: $showsAddFolder) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add RSS Folder").font(.title2.weight(.semibold))
                TextField("Folder name", text: $folderName).textFieldStyle(.roundedBorder)
                Picker("Parent folder", selection: $folderParent) {
                    Text("Root").tag("")
                    ForEach(folders) { folder in Text(folder.path).tag(folder.path) }
                }
                HStack {
                    Spacer()
                    Button("Cancel") { showsAddFolder = false }
                    Button("Add Folder") {
                        let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let path = folderParent.isEmpty ? name : "\(folderParent)/\(name)"
                        Task {
                            do { try await store.addRSSFolder(path: path); showsAddFolder = false; folderName = ""; folderParent = ""; await reload() }
                            catch { errorMessage = error.localizedDescription }
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(22)
            .frame(width: 400)
        }
        .sheet(isPresented: $showsRenameFolder) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Rename RSS Folder").font(.title2.weight(.semibold))
                TextField("Folder name", text: $folderName).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { showsRenameFolder = false }
                    Button("Save") {
                        let parent = (editingFolderPath as NSString).deletingLastPathComponent
                        let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let destination = parent == "." || parent.isEmpty ? name : "\(parent)/\(name)"
                        Task {
                            do { try await store.moveRSSItem(path: editingFolderPath, to: destination); showsRenameFolder = false; await reload() }
                            catch { errorMessage = error.localizedDescription }
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(22)
            .frame(width: 400)
        }
        .sheet(isPresented: $showsRules) { RSSRulesView(store: store) }
    }

    private func reload() async {
        do {
            feeds = try await store.rssFeeds()
            unreadCount = feeds.reduce(0) { count, feed in
                count + feed.articles.filter { !$0.isRead }.count
            }
            folders = try await store.rssFolders()
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

    private func articleColor(for article: RSSArticle) -> Color {
        let colorID = article.isRead ? "RSS.ReadArticle" : "RSS.UnreadArticle"
        return themeColor(for: colorID) ?? (article.isRead ? Color.primary.opacity(0.65) : Color.accentColor)
    }

    private func themeColor(for id: String) -> Color? {
        guard let color = QBitXThemePalette(storedJSON: themePaletteJSON)?
            .color(for: id, isDark: colorScheme == .dark)
        else { return nil }
        return Color(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}
