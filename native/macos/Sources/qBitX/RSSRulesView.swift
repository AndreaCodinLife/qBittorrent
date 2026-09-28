import AppKit
import RSSRuleSupport
import SwiftUI
import UniformTypeIdentifiers

struct RSSRulesView: View {
    @Environment(\.dismiss) private var dismiss
    let store: TorrentStore
    @State private var rules: [String: [String: Any]] = [:]
    @State private var feedURLs: [String] = []
    @State private var selectedName: String?
    @State private var nameDraft = ""
    @State private var newName = ""
    @State private var mustContain = ""
    @State private var mustNotContain = ""
    @State private var episodeFilter = ""
    @State private var useRegex = false
    @State private var smartFilter = false
    @State private var ignoreDays = 0
    @State private var priority = 0
    @State private var enabled = true
    @State private var selectedFeeds: Set<String> = []
    @State private var category = ""
    @State private var tags = ""
    @State private var savePath = ""
    @State private var addPaused = "Default"
    @State private var contentLayout = "Default"
    @State private var matches: [(String, [String])] = []
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var showsImport = false
    @State private var pendingClearDownloadHistoryRule: String?

    private var mustContainValidationError: String? {
        RSSRuleValidation.regularExpressionError(for: mustContain, enabled: useRegex)
    }

    private var mustNotContainValidationError: String? {
        RSSRuleValidation.regularExpressionError(for: mustNotContain, enabled: useRegex)
    }

    private var episodeFilterValidationError: String? {
        guard !RSSRuleValidation.isValidEpisodeFilter(episodeFilter) else { return nil }
        return "Use a season and episode list such as 1x2;8-15;5;30-;. End the filter with a semicolon."
    }

    private var lastMatchDescription: String {
        guard let selectedName,
              let value = rules[selectedName]?["lastMatch"] as? String,
              let date = RSSRuleValidation.lastMatchDate(from: value)
        else { return "Last match: Unknown" }
        let elapsedDays = Int(Date.now.timeIntervalSince(date) / 86_400)
        return "Last match: \(elapsedDays) days ago"
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("RSS Downloader Rules").font(.headline)
                    Spacer()
                    Button("Import…") { showsImport = true }.buttonStyle(.glass)
                    Button("Export…", action: exportRules).buttonStyle(.glass)
                    Button { createRule() } label: { Image(systemName: "plus") }.buttonStyle(.glass)
                        .help("Add rule")
                        .accessibilityLabel("Add RSS downloader rule")
                    Button(role: .destructive) { removeSelected() } label: { Image(systemName: "trash") }
                        .buttonStyle(.glass).disabled(selectedName == nil)
                        .help("Remove selected rule")
                        .accessibilityLabel("Remove selected RSS downloader rule")
                }
                .padding(12)
                List(selection: $selectedName) {
                    ForEach(rules.keys.sorted(), id: \.self) { name in
                        HStack {
                            Image(systemName: (rules[name]?["enabled"] as? Bool ?? true) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle((rules[name]?["enabled"] as? Bool ?? true) ? .green : .secondary)
                            Text(name).lineLimit(1)
                        }
                        .tag(name)
                        .contextMenu {
                            Button("Enable/Disable") { toggleRule(name) }
                            Button("Clone…") { clone(name) }
                            Button("Remove", role: .destructive) { Task { await remove(name) } }
                        }
                    }
                }
                .listStyle(.sidebar)
                HStack {
                    TextField("New rule name", text: $newName).textFieldStyle(.roundedBorder)
                    Button("Add") { createRule() }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(10)
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 270)
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    Text(selectedName == nil ? "Select a rule" : "Rule Settings").font(.title2.weight(.semibold))
                    Spacer()
                    if selectedName != nil {
                        TextField("Rule name", text: $nameDraft).textFieldStyle(.roundedBorder).frame(width: 220)
                        Button("Save") { save() }.buttonStyle(.glassProminent).disabled(isSaving)
                    }
                    Button("Done") { dismiss() }
                }
                .padding(15)
                Divider()
                if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red).padding(8) }
                if selectedName == nil {
                    ContentUnavailableView("No Rule Selected", systemImage: "dot.radiowaves.left.and.right", description: Text("Create or select a rule to configure automatic torrent downloads."))
                } else {
                    Form {
                        Section("Matching") {
                            Toggle("Enabled", isOn: $enabled)
                            Toggle("Use regular expressions", isOn: $useRegex)
                            HStack(spacing: 8) {
                                TextField("Must contain", text: $mustContain)
                                validationWarning(mustContainValidationError, label: "Invalid must contain expression")
                            }
                            HStack(spacing: 8) {
                                TextField("Must not contain", text: $mustNotContain)
                                validationWarning(mustNotContainValidationError, label: "Invalid must not contain expression")
                            }
                            HStack(spacing: 8) {
                                TextField("Episode filter", text: $episodeFilter)
                                validationWarning(episodeFilterValidationError, label: "Invalid episode filter")
                            }
                            Toggle("Smart episode filter", isOn: $smartFilter)
                            Stepper("Ignore episodes older than \(ignoreDays) days", value: $ignoreDays, in: 0...365)
                            HStack {
                                Text(lastMatchDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("Priority")
                                Stepper(value: $priority, in: Int(Int32.min)...Int(Int32.max)) {
                                    Text("\(priority)").monospacedDigit()
                                }
                                    .fixedSize()
                            }
                            Button("Clear Downloaded Episodes…", role: .destructive) {
                                pendingClearDownloadHistoryRule = selectedName
                            }
                            .disabled(selectedName == nil || isSaving)
                        }
                        Section("Feeds") {
                            if feedURLs.isEmpty {
                                Text("Add RSS feeds before assigning them to a rule.").foregroundStyle(.secondary)
                            } else {
                                ForEach(feedURLs, id: \.self) { url in
                                    Toggle(url, isOn: Binding(
                                        get: { selectedFeeds.contains(url) },
                                        set: { selected in
                                            if selected { selectedFeeds.insert(url) }
                                            else { selectedFeeds.remove(url) }
                                        }
                                    ))
                                }
                            }
                        }
                        Section("When a match is found") {
                            TextField("Category", text: $category)
                            TextField("Tags (comma separated)", text: $tags)
                            HStack {
                                TextField("Save in folder (blank uses category/default)", text: $savePath)
                                ServerPathBrowserButton(store: store, path: $savePath, kind: .directory)
                            }
                            Picker("Add paused", selection: $addPaused) {
                                Text("Use qBittorrent default").tag("Default")
                                Text("Always paused").tag("Always")
                                Text("Start immediately").tag("Never")
                            }
                            Picker("Content layout", selection: $contentLayout) {
                                Text("Default").tag("Default")
                                Text("Original").tag("Original")
                                Text("Subfolder").tag("Subfolder")
                                Text("No subfolder").tag("NoSubfolder")
                            }
                        }
                        Section("Current matches") {
                            if matches.isEmpty { Text("Save the rule to check matching articles.").foregroundStyle(.secondary) }
                            ForEach(matches, id: \.0) { feed, titles in
                                DisclosureGroup("\(feed) (\(titles.count))") {
                                    ForEach(titles, id: \.self) { Text($0).font(.caption) }
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 700)
        .task { await reload() }
        .onChange(of: selectedName) { _, value in loadDraft(value) }
        .confirmationDialog(
            "Clear downloaded episodes?",
            isPresented: Binding(
                get: { pendingClearDownloadHistoryRule != nil },
                set: { if !$0 { pendingClearDownloadHistoryRule = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Clear Downloaded Episodes", role: .destructive) {
                guard let name = pendingClearDownloadHistoryRule else { return }
                pendingClearDownloadHistoryRule = nil
                clearDownloadedEpisodes(named: name)
            }
            Button("Cancel", role: .cancel) { pendingClearDownloadHistoryRule = nil }
        } message: {
            Text("Are you sure you want to clear the list of downloaded episodes for this rule?")
        }
        .fileImporter(isPresented: $showsImport, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                Task {
                    do { try await store.importRSSRules(data); await reload() }
                    catch { errorMessage = error.localizedDescription }
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    @ViewBuilder
    private func validationWarning(_ message: String?, label: String) -> some View {
        if let message {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .help(message)
                .accessibilityLabel(label)
                .accessibilityValue(message)
        }
    }

    private func clearDownloadedEpisodes(named name: String) {
        guard var rule = rules[name] else { return }
        rule["previouslyMatchedEpisodes"] = [String]()
        do {
            let data = try JSONSerialization.data(withJSONObject: rule, options: [.fragmentsAllowed, .sortedKeys])
            guard let definition = String(data: data, encoding: .utf8) else { throw APIError.badResponse }
            Task {
                isSaving = true
                defer { isSaving = false }
                do {
                    try await store.setRSSRule(name: name, definition: definition)
                    rules[name] = rule
                    if selectedName == name { await loadMatches(name) }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() async {
        do {
            let data = try await store.rssRulesData()
            guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { throw APIError.badResponse }
            rules = raw
            let feeds = try await store.rssFeeds()
            feedURLs = feeds.map(\.url).sorted()
            if selectedName == nil || rules[selectedName!] == nil { selectedName = rules.keys.sorted().first }
            loadDraft(selectedName)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func loadDraft(_ name: String?) {
        guard let name, let rule = rules[name] else { return }
        nameDraft = name
        enabled = rule["enabled"] as? Bool ?? true
        useRegex = rule["useRegex"] as? Bool ?? false
        mustContain = rule["mustContain"] as? String ?? ""
        mustNotContain = rule["mustNotContain"] as? String ?? ""
        episodeFilter = rule["episodeFilter"] as? String ?? ""
        smartFilter = rule["smartFilter"] as? Bool ?? false
        ignoreDays = min(max(rule["ignoreDays"] as? Int ?? 0, 0), 365)
        priority = min(max(rule["priority"] as? Int ?? 0, Int(Int32.min)), Int(Int32.max))
        selectedFeeds = Set(rule["affectedFeeds"] as? [String] ?? [])
        let params = rule["torrentParams"] as? [String: Any] ?? [:]
        category = params["category"] as? String ?? rule["assignedCategory"] as? String ?? ""
        tags = (params["tags"] as? [String] ?? []).joined(separator: ", ")
        savePath = params["save_path"] as? String ?? rule["savePath"] as? String ?? ""
        if let paused = params["stopped"] as? Bool { addPaused = paused ? "Always" : "Never" }
        else if let paused = rule["addPaused"] as? Bool { addPaused = paused ? "Always" : "Never" }
        else { addPaused = "Default" }
        contentLayout = params["content_layout"] as? String ?? rule["contentLayout"] as? String ?? "Default"
        Task { await loadMatches(name) }
    }

    private func loadMatches(_ name: String) async {
        do {
            let data = try await store.rssRuleMatches(name)
            guard let result = try JSONSerialization.jsonObject(with: data) as? [String: [String]] else { return }
            matches = result.sorted { $0.key < $1.key }
        } catch { errorMessage = error.localizedDescription }
    }

    private func createRule() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, rules[name] == nil else { return }
        Task {
            do {
                try await store.setRSSRule(name: name, definition: "{}")
                newName = ""
                await reload()
                selectedName = name
                loadDraft(name)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func save() {
        guard let oldName = selectedName else { return }
        let newRuleName = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newRuleName.isEmpty else { errorMessage = "Enter a rule name."; return }
        isSaving = true
        Task {
            do {
                var rule = rules[oldName] ?? [:]
                rule["enabled"] = enabled
                rule["useRegex"] = useRegex
                rule["mustContain"] = mustContain
                rule["mustNotContain"] = mustNotContain
                rule["episodeFilter"] = episodeFilter
                rule["smartFilter"] = smartFilter
                rule["ignoreDays"] = ignoreDays
                rule["priority"] = priority
                rule["affectedFeeds"] = Array(selectedFeeds).sorted()
                var params = rule["torrentParams"] as? [String: Any] ?? [:]
                params["category"] = category
                params["tags"] = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                params["save_path"] = savePath
                params["use_auto_tmm"] = savePath.isEmpty
                if addPaused == "Default" { params["stopped"] = NSNull() }
                else { params["stopped"] = addPaused == "Always" }
                if contentLayout == "Default" { params["content_layout"] = NSNull() }
                else { params["content_layout"] = contentLayout }
                rule["torrentParams"] = params
                let encoded = try JSONSerialization.data(withJSONObject: rule, options: [.fragmentsAllowed, .sortedKeys])
                guard let definition = String(data: encoded, encoding: .utf8) else { throw APIError.badResponse }
                if newRuleName != oldName { try await store.renameRSSRule(oldName, to: newRuleName) }
                try await store.setRSSRule(name: newRuleName, definition: definition)
                await reload()
                selectedName = newRuleName
                await loadMatches(newRuleName)
            } catch { errorMessage = error.localizedDescription }
            isSaving = false
        }
    }

    private func toggleRule(_ name: String) {
        guard var rule = rules[name] else { return }
        rule["enabled"] = !(rule["enabled"] as? Bool ?? true)
        persist(rule, name: name)
    }

    private func clone(_ name: String) {
        let cloneName = "\(name) copy"
        Task {
            do { try await store.cloneRSSRule(name, as: cloneName); await reload() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func removeSelected() {
        guard let selectedName else { return }
        Task { await remove(selectedName) }
    }

    private func remove(_ name: String) async {
        do { try await store.removeRSSRule(name); selectedName = nil; await reload() }
        catch { errorMessage = error.localizedDescription }
    }

    private func persist(_ rule: [String: Any], name: String) {
        Task {
            do {
                let data = try JSONSerialization.data(withJSONObject: rule, options: [.fragmentsAllowed, .sortedKeys])
                guard let definition = String(data: data, encoding: .utf8) else { throw APIError.badResponse }
                try await store.setRSSRule(name: name, definition: definition)
                await reload()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func exportRules() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "rss-downloader-rules.json"
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            Task {
                do { try await store.exportRSSRules().write(to: destination, options: .atomic) }
                catch { errorMessage = error.localizedDescription }
            }
        }
    }
}
