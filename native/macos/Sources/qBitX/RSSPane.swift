import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RSSArticleSupport
import QBitXThemeSupport
import TorrentLinkInput

private enum RSSPaneSelection: Hashable {
    case allArticles
    case unreadArticles
    case folder(String)
    case feed(String)
}

private struct RSSNavigationNode: Identifiable {
    let id: String
    let title: String
    let selection: RSSPaneSelection
    let symbol: String
    let unreadCount: Int
    let isLoading: Bool
    let children: [RSSNavigationNode]?

    var folderPath: String? {
        guard case let .folder(path) = selection else { return nil }
        return path
    }
}

private func rssParentPath(_ path: String) -> String {
    guard let separator = path.lastIndex(of: "\\") else { return "" }
    return String(path[..<separator])
}

private func normalizedRSSPath(_ path: String) -> String {
    path.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "/", with: "\\")
}

struct RSSPane: View {
    let store: TorrentStore
    @Binding var unreadCount: Int
    @AppStorage("qBitX.themePalette") private var themePaletteJSON = ""
    @AppStorage("qBitX.rssExpandedFolders") private var rssExpandedFoldersJSON = "[]"
    @Environment(\.colorScheme) private var colorScheme
    @State private var feeds: [RSSFeed] = []
    @State private var rssProcessingEnabled: Bool?
    @State private var selectedFeedItems: Set<RSSPaneSelection> = [.unreadArticles]
    @State private var activeFeedSelection: RSSPaneSelection = .unreadArticles
    @State private var selectedArticleIDs: Set<String> = []
    @State private var showsAddFeed = false
    @State private var feedURL = ""
    @State private var feedName = ""
    @State private var feedFolder = ""
    @State private var feedRefreshInterval = "0"
    @State private var folders: [RSSFolder] = []
    @State private var showsAddFolder = false
    @State private var folderName = ""
    @State private var folderParent = ""
    @State private var showsRenameFolder = false
    @State private var editingFolderPath = ""
    @State private var articleFilter = ""
    @State private var editedFeedURL = ""
    @State private var editedFeedRefreshInterval = "0"
    @State private var showsEditFeed = false
    @State private var showsRemoveFeed = false
    @State private var showsMoveFeed = false
    @State private var editingFeedPath = ""
    @State private var newFeedPath = ""
    @State private var showsRules = false
    @State private var errorMessage: String?
    @State private var pendingRemovalPaths: [String] = []

    private var selectedTitle: String {
        switch activeFeedSelection {
        case .allArticles: "All Articles"
        case .unreadArticles: "Unread Articles"
        case let .folder(path): folders.first { $0.path == path }?.title ?? path
        case let .feed(path): feeds.first { $0.path == path }?.title ?? path
        }
    }

    private var navigationNodes: [RSSNavigationNode] {
        let foldersByParent = Dictionary(grouping: folders, by: { rssParentPath($0.path) })
        let feedsByParent = Dictionary(grouping: feeds, by: { rssParentPath($0.path) })

        func children(of parentPath: String) -> [RSSNavigationNode] {
            let folderNodes = (foldersByParent[parentPath] ?? []).map { folder in
                let nested = children(of: folder.path)
                let unread = feeds
                    .filter { $0.path.hasPrefix(folder.path + "\\") }
                    .reduce(0) { $0 + $1.articles.filter { !$0.isRead }.count }
                return RSSNavigationNode(
                    id: "folder:\(folder.path)", title: folder.title,
                    selection: .folder(folder.path), symbol: "folder", unreadCount: unread,
                    isLoading: false,
                    children: nested.isEmpty ? nil : nested
                )
            }
            let feedNodes = (feedsByParent[parentPath] ?? []).map { feed in
                RSSNavigationNode(
                    id: "feed:\(feed.path)", title: feed.title,
                    selection: .feed(feed.path),
                    symbol: feed.hasError ? "exclamationmark.triangle.fill" : "dot.radiowaves.left.and.right",
                    unreadCount: feed.articles.filter { !$0.isRead }.count,
                    isLoading: feed.isLoading,
                    children: nil
                )
            }
            return (folderNodes + feedNodes).sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }

        return children(of: "")
    }

    private var visibleArticles: [RSSArticle] {
        let matchingFeeds: [RSSFeed]
        switch activeFeedSelection {
        case .allArticles, .unreadArticles:
            matchingFeeds = feeds
        case let .folder(path):
            matchingFeeds = feeds.filter { $0.path.hasPrefix(path + "\\") }
        case let .feed(path):
            matchingFeeds = feeds.filter { $0.path == path }
        }
        return matchingFeeds.flatMap(\.articles)
            .filter { activeFeedSelection != .unreadArticles || !$0.isRead }
            .filter { articleFilter.isEmpty || $0.title.localizedCaseInsensitiveContains(articleFilter) }
            .sorted {
                switch ($0.dateValue, $1.dateValue) {
                case let (lhs?, rhs?): lhs > rhs
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
            }
    }

    private var selectedArticles: [RSSArticle] {
        visibleArticles.filter { selectedArticleIDs.contains($0.selectionID) }
    }

    private var previewArticle: RSSArticle? {
        visibleArticles.first { selectedArticleIDs.contains($0.selectionID) }
    }

    private var selectedRSSItemPaths: [String] {
        rssPathsForAction()
    }

    var body: some View {
        GeometryReader { geometry in
            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Text("FEEDS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Button { prepareAddFolder() } label: { Image(systemName: "folder.badge.plus") }
                            .buttonStyle(.glass).help("Add RSS folder")
                            .accessibilityLabel("Add RSS folder")
                        Button { prepareAddFeed() } label: { Image(systemName: "plus") }
                            .buttonStyle(.glass)
                            .help("Add RSS feed")
                            .accessibilityLabel("Add RSS feed")
                    }
                    .padding(12)
                    List(selection: $selectedFeedItems) {
                        Section {
                            Label("All", systemImage: "tray.full")
                                .tag(RSSPaneSelection.allArticles)
                                .contextMenu { rssAggregateContextMenu(.allArticles) }
                            Label("Unread (\(unreadCount))", systemImage: "tray")
                                .tag(RSSPaneSelection.unreadArticles)
                                .contextMenu { rssAggregateContextMenu(.unreadArticles) }
                        }
                        Section {
                            navigationRows(navigationNodes)
                        } header: {
                            Text("Subscriptions")
                                .onDrop(of: [UTType.plainText], isTargeted: nil) {
                                    receiveRSSDrop($0, into: "")
                                }
                        }
                    }
                    .listStyle(.sidebar)
                    .onChange(of: selectedFeedItems) { oldItems, newItems in
                        let inserted = newItems.subtracting(oldItems)
                        if let insertedItem = inserted.first {
                            activeFeedSelection = insertedItem
                        } else if !newItems.contains(activeFeedSelection) {
                            activeFeedSelection = newItems.first ?? .unreadArticles
                        }
                        selectedArticleIDs = []
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                .frame(minWidth: 190, idealWidth: 230)
                VStack(spacing: 0) {
                    if rssProcessingEnabled == false {
                        Label("RSS processing is disabled in qBittorrent preferences.", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        Divider()
                    }
                    HStack {
                        Text(selectedTitle).font(.headline)
                        Spacer()
                        Button("Downloader Rules…") { showsRules = true }
                            .buttonStyle(.glass)
                        Button { refreshSelectedRSSItems() } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.glass)
                            .help("Refresh selected RSS feeds")
                            .accessibilityLabel("Refresh selected RSS feeds")
                    }
                    .padding(12)
                    Divider()
                    if let errorMessage {
                        ContentUnavailableView("RSS Unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        TextField("Filter articles…", text: $articleFilter)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Filter RSS articles")
                            .padding(10)
                        if visibleArticles.isEmpty {
                            ContentUnavailableView("No Articles", systemImage: "newspaper", description: Text("There are no matching RSS articles."))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            HStack {
                                Text("\(visibleArticles.count) articles")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Mark Read") { markSelectedArticlesRead() }
                                    .buttonStyle(.glass)
                                    .disabled(selectedArticles.isEmpty)
                                Button("Open Article") { openSelectedArticles() }
                                    .buttonStyle(.glass)
                                    .disabled(!selectedArticles.contains { Self.safeWebURL($0.link) != nil })
                                Button("Add Torrent") { addSelectedArticles() }
                                    .buttonStyle(.glassProminent)
                                    .disabled(!selectedArticles.contains { Self.supportedTorrentURL(for: $0) != nil })
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                            HSplitView {
                                List(visibleArticles, selection: $selectedArticleIDs) { article in
                                    HStack(spacing: 10) {
                                        Image(systemName: article.isRead ? "circle" : "circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(articleColor(for: article))
                                            .accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(article.title)
                                                .fontWeight(article.isRead ? .regular : .semibold)
                                                .foregroundStyle(articleColor(for: article))
                                                .lineLimit(2)
                                            Text(article.date).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .tag(article.selectionID)
                                    .onTapGesture(count: 2) {
                                        addTorrentArticles(articlesForAction(containing: article))
                                    }
                                    .contextMenu {
                                        let actionArticles = articlesForAction(containing: article)
                                        Button("Mark Read") { markArticlesRead(actionArticles) }
                                        if actionArticles.contains(where: { Self.supportedTorrentURL(for: $0) != nil }) {
                                            Button("Download Torrent") { addTorrentArticles(actionArticles) }
                                        }
                                        if actionArticles.contains(where: { Self.safeWebURL($0.link) != nil }) {
                                            Button("Open Article URL") { openArticles(actionArticles) }
                                        }
                                    }
                                }
                                .listStyle(.plain)
                                .frame(minWidth: 270)
                                .onChange(of: selectedArticleIDs) { oldIDs, newIDs in
                                    let deselectedIDs = oldIDs.subtracting(newIDs)
                                    let deselected = feeds.flatMap(\.articles).filter { deselectedIDs.contains($0.selectionID) }
                                    if !deselected.isEmpty { markArticlesRead(deselected) }
                                }
                                RSSArticlePreview(article: previewArticle, onOpenURL: openRSSURL)
                                    .frame(minWidth: 280)
                            }
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                        }
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                .frame(minWidth: 350)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .layoutPriority(1)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .task(id: store.isConnected) {
            guard store.isConnected else { return }
            await reload()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
                await reload()
            }
        }
        .confirmationDialog("Remove selected RSS items?", isPresented: $showsRemoveFeed) {
            Button("Remove Selected Items", role: .destructive) {
                Task {
                    do {
                        for path in pendingRemovalPaths { try await store.removeRSSFeed(path: path) }
                        pendingRemovalPaths = []
                        selectedFeedItems = [.unreadArticles]
                        activeFeedSelection = .unreadArticles
                        selectedArticleIDs = []
                        await reload()
                    }
                    catch { errorMessage = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) { pendingRemovalPaths = [] }
        }
        .sheet(isPresented: $showsEditFeed) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit RSS Feed").font(.title2.weight(.semibold))
                TextField("Feed URL", text: $editedFeedURL).textFieldStyle(.roundedBorder)
                TextField("Refresh interval in seconds (0 = default)", text: $editedFeedRefreshInterval)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { showsEditFeed = false }
                    Button("Save") {
                        guard !editingFeedPath.isEmpty else { return }
                        guard let interval = Int(editedFeedRefreshInterval), interval >= 0 else { return }
                        Task {
                            do {
                                try await store.editRSSFeed(path: editingFeedPath, url: editedFeedURL)
                                try await store.setRSSFeedRefreshInterval(path: editingFeedPath, seconds: interval)
                                showsEditFeed = false
                                await reload()
                            }
                            catch { errorMessage = error.localizedDescription }
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(URL(string: editedFeedURL)?.scheme?.hasPrefix("http") != true
                        || Int(editedFeedRefreshInterval).map { $0 >= 0 } != true)
                }
            }
            .padding(22)
            .frame(width: 430)
        }
        .sheet(isPresented: $showsMoveFeed) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Rename or Move RSS Feed").font(.title2.weight(.semibold))
                Text("Enter a new feed path. Use Folder\\Feed to place it in a folder.")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextField("Feed path", text: $newFeedPath).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { showsMoveFeed = false }
                    Button("Save") {
                        let path = normalizedRSSPath(newFeedPath)
                        Task {
                            do {
                                try await store.moveRSSItem(path: editingFeedPath, to: path)
                                showsMoveFeed = false
                                selectedFeedItems = [.feed(path)]
                                activeFeedSelection = .feed(path)
                                await reload()
                            }
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
                TextField("Refresh interval in seconds (0 = default)", text: $feedRefreshInterval)
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
                                let path = feedFolder.isEmpty ? leaf : "\(feedFolder)\\\(leaf)"
                                guard let interval = Int(feedRefreshInterval), interval >= 0 else {
                                    errorMessage = "Enter a non-negative refresh interval in seconds."
                                    return
                                }
                                try await store.addRSSFeed(url, path: path, refreshInterval: interval)
                                showsAddFeed = false
                                feedURL = ""
                                feedName = ""
                                feedRefreshInterval = "0"
                                selectedFeedItems = [.feed(path)]
                                activeFeedSelection = .feed(path)
                                await reload()
                            } catch { errorMessage = error.localizedDescription }
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(URL(string: feedURL)?.scheme?.hasPrefix("http") != true
                        || Int(feedRefreshInterval).map { $0 >= 0 } != true)
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
                        let path = folderParent.isEmpty ? name : "\(folderParent)\\\(name)"
                        Task {
                            do {
                                try await store.addRSSFolder(path: path)
                                showsAddFolder = false
                                folderName = ""
                                folderParent = ""
                                selectedFeedItems = [.folder(path)]
                                activeFeedSelection = .folder(path)
                                await reload()
                            }
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
                        let parent = rssParentPath(editingFolderPath)
                        let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let destination = parent.isEmpty ? name : "\(parent)\\\(name)"
                        Task {
                            do {
                                try await store.moveRSSItem(path: editingFolderPath, to: destination)
                                showsRenameFolder = false
                                selectedFeedItems = [.folder(destination)]
                                activeFeedSelection = .folder(destination)
                                await reload()
                            }
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

    private var expandedRSSFolderPaths: Set<String> {
        guard let data = rssExpandedFoldersJSON.data(using: .utf8),
              let paths = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(paths)
    }

    private func saveExpandedRSSFolderPaths(_ paths: Set<String>) {
        guard let data = try? JSONEncoder().encode(paths.sorted()),
              let value = String(data: data, encoding: .utf8)
        else { return }
        rssExpandedFoldersJSON = value
    }

    private func expansionBinding(for path: String) -> Binding<Bool> {
        Binding {
            expandedRSSFolderPaths.contains(path)
        } set: { isExpanded in
            var paths = expandedRSSFolderPaths
            if isExpanded {
                paths.insert(path)
            } else {
                paths = paths.filter { $0 != path && !$0.hasPrefix(path + "\\") }
            }
            saveExpandedRSSFolderPaths(paths)
        }
    }

    @ViewBuilder
    private func navigationRows(_ nodes: [RSSNavigationNode]) -> some View {
        ForEach(nodes) { node in
            if let path = node.folderPath, let children = node.children {
                DisclosureGroup(isExpanded: expansionBinding(for: path)) {
                    AnyView(navigationRows(children))
                } label: {
                    navigationLabel(node)
                }
                .contextMenu { rssNodeContextMenu(node) }
            } else {
                navigationLabel(node)
                    .contextMenu { rssNodeContextMenu(node) }
            }
        }
    }

    private func navigationLabel(_ node: RSSNavigationNode) -> some View {
        let itemType = node.folderPath == nil ? "feed" : "folder"
        return Label {
            HStack {
                Text(node.title).lineLimit(1)
                Spacer(minLength: 4)
                if node.unreadCount > 0 {
                    Text("\(node.unreadCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            if node.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: node.symbol)
            }
        }
        .tag(node.selection)
        .accessibilityLabel("RSS \(itemType), \(node.title), \(node.unreadCount) unread")
        .accessibilityHint("Drag to move this \(itemType) into a folder or the subscriptions root.")
        .onDrag { rssDragProvider(for: node.selection) }
        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
            guard let folderPath = node.folderPath else { return false }
            return receiveRSSDrop(providers, into: folderPath)
        }
    }

    private func rssDragProvider(for selection: RSSPaneSelection) -> NSItemProvider {
        let paths = movableRSSPaths(startingWith: selection)
        let data = (try? JSONEncoder().encode(paths)) ?? Data("[]".utf8)
        return NSItemProvider(object: (String(data: data, encoding: .utf8) ?? "[]") as NSString)
    }

    private func movableRSSPaths(startingWith selection: RSSPaneSelection) -> [String] {
        let selections = selectedFeedItems.contains(selection) ? selectedFeedItems : [selection]
        guard !selections.contains(.allArticles), !selections.contains(.unreadArticles) else { return [] }
        let paths = selections.compactMap { selected -> String? in
            switch selected {
            case let .folder(path), let .feed(path): path
            case .allArticles, .unreadArticles: nil
            }
        }
        return paths
            .filter { path in !paths.contains { other in other != path && path.hasPrefix(other + "\\") } }
            .sorted {
                let leftDepth = $0.filter { $0 == "\\" }.count
                let rightDepth = $1.filter { $0 == "\\" }.count
                return leftDepth == rightDepth ? $0 < $1 : leftDepth < rightDepth
            }
    }

    private func receiveRSSDrop(_ providers: [NSItemProvider], into destinationFolder: String) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let encodedPaths = object as? String,
                  let data = encodedPaths.data(using: .utf8),
                  let paths = try? JSONDecoder().decode([String].self, from: data),
                  !paths.isEmpty
            else { return }
            Task { @MainActor in
                await moveRSSItems(paths, into: destinationFolder)
            }
        }
        return true
    }

    private func moveRSSItems(_ paths: [String], into destinationFolder: String) async {
        guard destinationFolder.isEmpty || folders.contains(where: { $0.path == destinationFolder }) else { return }
        let folderPaths = Set(folders.map(\.path))
        let validSourcePaths = folderPaths.union(feeds.map(\.path))
        var movedSelections: [RSSPaneSelection] = []
        do {
            for sourcePath in paths {
                guard validSourcePaths.contains(sourcePath) else { continue }
                if sourcePath == destinationFolder
                    || (folderPaths.contains(sourcePath) && destinationFolder.hasPrefix(sourcePath + "\\")) {
                    continue
                }
                let name = sourcePath.components(separatedBy: "\\").last ?? sourcePath
                let destinationPath = destinationFolder.isEmpty ? name : destinationFolder + "\\" + name
                guard destinationPath != sourcePath else { continue }
                try await store.moveRSSItem(path: sourcePath, to: destinationPath)
                movedSelections.append(folderPaths.contains(sourcePath) ? .folder(destinationPath) : .feed(destinationPath))
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        await reload()
        if !movedSelections.isEmpty {
            selectedFeedItems = Set(movedSelections)
            activeFeedSelection = movedSelections[0]
        }
        if !destinationFolder.isEmpty {
            var expanded = expandedRSSFolderPaths
            expanded.insert(destinationFolder)
            saveExpandedRSSFolderPaths(expanded)
        }
    }

    @ViewBuilder
    private func rssNodeContextMenu(_ node: RSSNavigationNode) -> some View {
        switch node.selection {
        case let .folder(path):
            Button("Refresh") { Task { await refreshRSSItems(rssPathsForAction(.folder(path))) } }
            Button("Mark All Read") { Task { await markRSSItemsRead(rssPathsForAction(.folder(path))) } }
            Divider()
            Button("Add Feed to Folder…") { prepareAddFeed(in: path) }
            if rssSelectionsForAction(.folder(path)).count == 1 {
                Button("Add Subfolder…") { prepareAddFolder(in: path) }
                Button("Rename Folder…") {
                    editingFolderPath = path
                    folderName = path.components(separatedBy: "\\").last ?? path
                    showsRenameFolder = true
                }
            }
            Button("Remove Selected Items", role: .destructive) { beginRemoving(.folder(path)) }
        case let .feed(path):
            if let feed = feeds.first(where: { $0.path == path }) {
                Button("Refresh") { Task { await refreshRSSItems(rssPathsForAction(.feed(path))) } }
                Button("Mark All Read") { Task { await markRSSItemsRead(rssPathsForAction(.feed(path))) } }
                Divider()
                if rssSelectionsForAction(.feed(path)).count == 1 {
                    Button("Edit URL…") {
                        editingFeedPath = feed.path
                        editedFeedURL = feed.url
                        editedFeedRefreshInterval = "\(feed.refreshInterval)"
                        showsEditFeed = true
                    }
                    Button("Rename or Move…") {
                        editingFeedPath = feed.path
                        newFeedPath = feed.path
                        showsMoveFeed = true
                    }
                    Button("Copy Selected Feed URLs") {
                        let urls = rssFeedURLsForAction(.feed(path))
                        NSPasteboard.general.setString(urls.joined(separator: "\n"), forType: .string)
                    }
                }
                Button("Remove Selected Items", role: .destructive) { beginRemoving(.feed(path)) }
            }
        case .allArticles, .unreadArticles:
            Button("Refresh All Feeds") { Task { await refreshRSSItems(rssPathsForAction(node.selection)) } }
            Button("Mark All Read") { Task { await markRSSItemsRead(rssPathsForAction(node.selection)) } }
        }
    }

    @ViewBuilder
    private func rssAggregateContextMenu(_ selection: RSSPaneSelection) -> some View {
        Button("Refresh All Feeds") { Task { await refreshRSSItems(rssPathsForAction(selection)) } }
        Button("Mark All Read") { Task { await markRSSItemsRead(rssPathsForAction(selection)) } }
    }

    private func rssSelectionsForAction(_ target: RSSPaneSelection? = nil) -> Set<RSSPaneSelection> {
        guard let target else { return selectedFeedItems }
        return selectedFeedItems.contains(target) ? selectedFeedItems : [target]
    }

    private func rssPathsForAction(_ target: RSSPaneSelection? = nil) -> [String] {
        let selections = rssSelectionsForAction(target)
        if selections.contains(.allArticles) || selections.contains(.unreadArticles) {
            return feeds.map(\.path)
        }
        let paths = selections.compactMap { selection -> String? in
            switch selection {
            case let .folder(path), let .feed(path): path
            case .allArticles, .unreadArticles: nil
            }
        }
        return paths.filter { path in
            !paths.contains { other in other != path && path.hasPrefix(other + "\\") }
        }
    }

    private func rssFeedURLsForAction(_ target: RSSPaneSelection? = nil) -> [String] {
        let paths = Set(rssSelectionsForAction(target).compactMap { selection -> String? in
            guard case let .feed(path) = selection else { return nil }
            return path
        })
        return feeds.filter { paths.contains($0.path) }.map(\.url)
    }

    private func beginRemoving(_ target: RSSPaneSelection) {
        let selections = rssSelectionsForAction(target)
        selectedFeedItems = selections
        activeFeedSelection = selections.first ?? .unreadArticles
        let paths = selections.compactMap { selection -> String? in
            switch selection {
            case let .folder(path), let .feed(path): path
            case .allArticles, .unreadArticles: nil
            }
        }
        pendingRemovalPaths = paths.filter { path in
            !paths.contains { other in other != path && path.hasPrefix(other + "\\") }
        }.sorted { $0.components(separatedBy: "\\").count > $1.components(separatedBy: "\\").count }
        showsRemoveFeed = !pendingRemovalPaths.isEmpty
    }

    private func prepareAddFeed(in folder: String? = nil) {
        if let folder {
            feedFolder = folder
        } else if case let .folder(path) = activeFeedSelection {
            feedFolder = path
        } else {
            feedFolder = ""
        }
        if feedURL.isEmpty,
           let clipboard = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let scheme = URL(string: clipboard)?.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            feedURL = clipboard
        }
        feedName = ""
        feedRefreshInterval = "0"
        showsAddFeed = true
    }

    private func prepareAddFolder(in folder: String? = nil) {
        if let folder {
            folderParent = folder
        } else if case let .folder(path) = activeFeedSelection {
            folderParent = path
        } else {
            folderParent = ""
        }
        folderName = ""
        showsAddFolder = true
    }

    private func refreshSelectedRSSItems() {
        Task { await refreshRSSItems(selectedRSSItemPaths) }
    }

    private func refreshRSSItems(_ paths: [String]) async {
        guard !paths.isEmpty else { return }
        do {
            for path in paths { try await store.refreshRSSFeed(path: path) }
            try? await Task.sleep(for: .milliseconds(500))
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    private func markRSSItemsRead(_ paths: [String]) async {
        guard !paths.isEmpty else { return }
        do {
            for path in paths { try await store.markRSSFeedRead(path: path) }
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    private func markSelectedArticlesRead() {
        markArticlesRead(selectedArticles)
    }

    private func markArticlesRead(_ articles: [RSSArticle]) {
        let unreadArticles = articles.filter { !$0.isRead }
        guard !unreadArticles.isEmpty else { return }
        Task {
            do {
                for article in unreadArticles {
                    try await store.markRSSArticleRead(path: article.feedPath, articleID: article.id)
                }
                await reload()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func articlesForAction(containing article: RSSArticle) -> [RSSArticle] {
        selectedArticleIDs.contains(article.selectionID) ? selectedArticles : [article]
    }

    private func addSelectedArticles() {
        addTorrentArticles(selectedArticles)
    }

    private func addTorrentArticles(_ articles: [RSSArticle]) {
        let articlesWithTorrentLinks = articles.filter { Self.supportedTorrentURL(for: $0) != nil }
        guard !articlesWithTorrentLinks.isEmpty else { return }
        Task {
            do {
                for article in articlesWithTorrentLinks {
                    try await store.addRSSArticle(article)
                    if !article.isRead {
                        try await store.markRSSArticleRead(path: article.feedPath, articleID: article.id)
                    }
                }
                await reload()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func openSelectedArticles() {
        openArticles(selectedArticles)
    }

    private func openArticles(_ articles: [RSSArticle]) {
        for article in articles {
            guard let url = Self.safeWebURL(article.link) else { continue }
            NSWorkspace.shared.open(url)
        }
    }

    private func openRSSURL(_ url: URL) {
        let scheme = url.scheme?.lowercased()
        if scheme == "magnet" || ((scheme == "http" || scheme == "https") && url.pathExtension.lowercased() == "torrent") {
            Task {
                do { try await store.add(url: url.absoluteString) }
                catch { errorMessage = error.localizedDescription }
            }
        } else if Self.safeWebURL(url.absoluteString) != nil {
            NSWorkspace.shared.open(url)
        }
    }

    private static func safeWebURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil
        else { return nil }
        return url
    }

    private static func supportedTorrentURL(for article: RSSArticle) -> String? {
        let value = article.torrentURL.isEmpty ? article.link : article.torrentURL
        let parsed = TorrentLinkInput.parse(value)
        guard parsed.invalidLines.isEmpty,
              parsed.urls.count == 1,
              let scheme = parsed.urls.first?.scheme?.lowercased(),
              ["http", "https", "magnet"].contains(scheme)
        else { return nil }
        return parsed.urls[0].absoluteString
    }

    private func reload() async {
        do {
            let snapshot = try await store.rssFeedSnapshot()
            feeds = snapshot.feeds
            unreadCount = feeds.reduce(0) { count, feed in
                count + feed.articles.filter { !$0.isRead }.count
            }
            folders = snapshot.folders
            rssProcessingEnabled = try? await store.rssProcessingEnabled()
            let validFeedPaths = Set(feeds.map(\.path))
            let validFolderPaths = Set(folders.map(\.path))
            let validExpandedPaths = expandedRSSFolderPaths.intersection(validFolderPaths)
            if validExpandedPaths != expandedRSSFolderPaths {
                saveExpandedRSSFolderPaths(validExpandedPaths)
            }
            func isValid(_ selection: RSSPaneSelection) -> Bool {
                switch selection {
                case .allArticles, .unreadArticles: true
                case let .feed(path): validFeedPaths.contains(path)
                case let .folder(path): validFolderPaths.contains(path)
                }
            }
            selectedFeedItems = Set(selectedFeedItems.filter(isValid))
            if selectedFeedItems.isEmpty { selectedFeedItems = [.unreadArticles] }
            if !isValid(activeFeedSelection) {
                activeFeedSelection = selectedFeedItems.first ?? .unreadArticles
            }
            let currentArticleIDs = Set(feeds.flatMap(\.articles).map(\.selectionID))
            selectedArticleIDs.formIntersection(currentArticleIDs)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
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
