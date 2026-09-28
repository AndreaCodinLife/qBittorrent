import AppKit
import RSSRuleSupport
import SwiftUI
import UniformTypeIdentifiers

struct RSSRulesView: View {
    @Environment(\.dismiss) private var dismiss
    let store: TorrentStore
    @State private var rules: [String: [String: Any]] = [:]
    @State private var feedURLs: [String] = []
    @State private var supportsLegacyRuleFiles = false
    @State private var selectedName: String?
    @State private var selectedRuleNames: Set<String> = []
    @FocusState private var isRuleNameFieldFocused: Bool
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
    @State private var torrentParamsDraft = TorrentAddOptionsDraft(json: "{}")
    @State private var matches: [(String, [String])] = []
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var showsImport = false
    @State private var pendingClearDownloadHistoryRules: [String] = []
    @State private var pendingRemoveRuleNames: [String] = []
    @State private var matchLoadID = UUID()

    private var legacyRuleFileType: UTType {
        UTType(filenameExtension: "rssrules", conformingTo: .data) ?? .data
    }

    private var importRuleFileTypes: [UTType] {
        supportsLegacyRuleFiles ? [.json, legacyRuleFileType] : [.json]
    }

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
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("RSS Downloader Rules").font(.headline)
                Spacer(minLength: 12)
                Button("Import Rules…") { showsImport = true }.buttonStyle(.glass)
                Button("Export JSON…") { exportRules(format: "json") }
                    .buttonStyle(.glass)
                    .disabled(rules.isEmpty || isSaving)
                    .help(rules.isEmpty ? "Add or import a rule before exporting." : "Export rules as JSON")
                if supportsLegacyRuleFiles {
                    Button("Export .rssrules…") { exportRules(format: "legacy") }
                        .buttonStyle(.glass)
                        .disabled(rules.isEmpty || isSaving)
                        .help(rules.isEmpty
                            ? "Add or import a rule before exporting."
                            : "Export in qBittorrent's legacy format; newer rule options may not be preserved.")
                }
                Button(role: .destructive) { removeSelected() } label: { Image(systemName: "trash") }
                    .buttonStyle(.glass).disabled(selectedRuleNames.isEmpty || isSaving)
                    .help("Remove selected rules")
                    .accessibilityLabel("Remove selected RSS downloader rules")
            }
            .padding(12)
            Divider()

            NavigationSplitView {
                VStack(spacing: 0) {
                    List(selection: $selectedRuleNames) {
                        ForEach(rules.keys.sorted(), id: \.self) { name in
                            HStack {
                                Image(systemName: (rules[name]?["enabled"] as? Bool ?? true) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle((rules[name]?["enabled"] as? Bool ?? true) ? .green : .secondary)
                                Text(name).lineLimit(1)
                            }
                            .tag(name)
                            .onTapGesture(count: 2) { renameRule(named: name) }
                            .contextMenu {
                                if selectedRuleNames.count > 1, selectedRuleNames.contains(name) {
                                    Button("Remove Selected Rules", role: .destructive) {
                                        requestRemoval(of: selectedRuleNames)
                                    }
                                    Button("Clear Downloaded Episodes…") {
                                        pendingClearDownloadHistoryRules = selectedRuleNames.sorted()
                                    }
                                } else {
                                    Button("Enable/Disable") { toggleRule(name) }
                                    Button("Rename…") { renameRule(named: name) }
                                    Button("Clone…") { clone(name) }
                                    Button("Remove", role: .destructive) { requestRemoval(of: [name]) }
                                    Button("Clear Downloaded Episodes…") {
                                        pendingClearDownloadHistoryRules = [name]
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .onKeyPress(KeyEquivalent("\u{F705}")) {
                        renameSelectedRule()
                        return .handled
                    }
                    .onDeleteCommand { removeSelected() }
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
                    Text(detailTitle).font(.title2.weight(.semibold))
                    Spacer()
                    if selectedName != nil {
                        TextField("Rule name", text: $nameDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .focused($isRuleNameFieldFocused)
                            .onSubmit(save)
                        Button("Save") { save() }
                            .buttonStyle(.glassProminent)
                            .disabled(isSaving || !torrentParamsDraft.hasValidValues)
                    }
                    Button("Done") { dismiss() }
                }
                .padding(15)
                Divider()
                if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red).padding(8) }
                if selectedRuleNames.count > 1 {
                    multipleRulesForm
                } else if rules.isEmpty {
                    ContentUnavailableView("No RSS Rules", systemImage: "dot.radiowaves.left.and.right", description: Text("Import a rule set or create a rule in the sidebar."))
                } else if selectedName == nil {
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
                                if let selectedName { pendingClearDownloadHistoryRules = [selectedName] }
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
                        TorrentAddOptionsFields(draft: $torrentParamsDraft, store: store)
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
        }
        .frame(minWidth: 900, minHeight: 700)
        .task { await reload() }
        .onChange(of: selectedRuleNames) { _, names in
            if names.count == 1 {
                selectedName = names.first
            } else {
                selectedName = nil
                if names.isEmpty {
                    matches = []
                    matchLoadID = UUID()
                } else {
                    Task { await loadMatches(names.sorted()) }
                }
            }
        }
        .onChange(of: selectedName) { _, value in loadDraft(value) }
        .confirmationDialog(
            "Clear downloaded episodes?",
            isPresented: Binding(
                get: { !pendingClearDownloadHistoryRules.isEmpty },
                set: { if !$0 { pendingClearDownloadHistoryRules = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Clear Downloaded Episodes", role: .destructive) {
                let names = pendingClearDownloadHistoryRules
                pendingClearDownloadHistoryRules = []
                clearDownloadedEpisodes(named: names)
            }
            Button("Cancel", role: .cancel) { pendingClearDownloadHistoryRules = [] }
        } message: {
            Text(pendingClearDownloadHistoryRules.count == 1
                ? "Are you sure you want to clear downloaded episodes for ‘\(pendingClearDownloadHistoryRules[0])’?"
                : "Are you sure you want to clear downloaded episodes for the selected rules?")
        }
        .confirmationDialog(
            "Remove selected RSS downloader rules?",
            isPresented: Binding(
                get: { !pendingRemoveRuleNames.isEmpty },
                set: { if !$0 { pendingRemoveRuleNames = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Rules", role: .destructive) { removePendingRules() }
            Button("Cancel", role: .cancel) { pendingRemoveRuleNames = [] }
        } message: {
            Text(pendingRemoveRuleNames.count == 1
                ? "Are you sure you want to remove ‘\(pendingRemoveRuleNames[0])’?"
                : "Are you sure you want to remove the selected download rules?")
        }
        .fileImporter(isPresented: $showsImport, allowedContentTypes: importRuleFileTypes) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let maximumFileSize = 10 * 1024 * 1024
                guard let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      fileSize <= maximumFileSize else {
                    errorMessage = "RSS rule files must be 10 MB or smaller."
                    return
                }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                guard data.count <= maximumFileSize else {
                    errorMessage = "RSS rule files must be 10 MB or smaller."
                    return
                }
                let format = url.pathExtension.lowercased() == "rssrules" ? "legacy" : "json"
                guard format != "legacy" || supportsLegacyRuleFiles else {
                    errorMessage = "Legacy .rssrules files require a qBitX-compatible qBittorrent server."
                    return
                }
                Task {
                    do { try await store.importRSSRules(data, format: format); await reload() }
                    catch { errorMessage = error.localizedDescription }
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private var detailTitle: String {
        if selectedRuleNames.count > 1 { return "\(selectedRuleNames.count) Rules Selected" }
        return selectedName == nil ? "Select a rule" : "Rule Settings"
    }

    private var multipleRulesForm: some View {
        Form {
            Section("Feeds") {
                Text("Feed assignments apply to all selected rules.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if feedURLs.isEmpty {
                    Text("Add RSS feeds before assigning them to rules.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(feedURLs, id: \.self) { url in
                        let assignedCount = selectedRuleNames.reduce(into: 0) { count, name in
                            if (rules[name]?["affectedFeeds"] as? [String] ?? []).contains(url) { count += 1 }
                        }
                        Toggle(isOn: Binding(
                            get: { assignedCount == selectedRuleNames.count },
                            set: { setFeedAssignment(url, enabled: $0) }
                        )) {
                            HStack {
                                Text(url)
                                Spacer()
                                if assignedCount > 0, assignedCount < selectedRuleNames.count {
                                    Text("Mixed").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(isSaving)
                    }
                }
            }
            Section("Current matches") {
                if matches.isEmpty {
                    Text("No matching articles for the selected rules.").foregroundStyle(.secondary)
                }
                ForEach(matches, id: \.0) { feed, titles in
                    DisclosureGroup("\(feed) (\(titles.count))") {
                        ForEach(titles, id: \.self) { Text($0).font(.caption) }
                    }
                }
            }
        }
        .formStyle(.grouped)
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

    private func clearDownloadedEpisodes(named names: [String]) {
        guard !names.isEmpty else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                for name in names {
                    guard var rule = rules[name] else { continue }
                    rule["previouslyMatchedEpisodes"] = [String]()
                    let data = try JSONSerialization.data(withJSONObject: rule, options: [.fragmentsAllowed, .sortedKeys])
                    guard let definition = String(data: data, encoding: .utf8) else { throw APIError.badResponse }
                    try await store.setRSSRule(name: name, definition: definition)
                    rules[name] = rule
                }
                if !selectedRuleNames.isEmpty { await loadMatches(selectedRuleNames.sorted()) }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reload() async {
        supportsLegacyRuleFiles = (try? await store.rssRuleFileFormats().contains("legacy")) ?? false
        do {
            let data = try await store.rssRulesData()
            guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { throw APIError.badResponse }
            rules = raw
            let feeds = try await store.rssFeeds()
            feedURLs = feeds.map(\.url).sorted()
            selectedRuleNames.formIntersection(Set(rules.keys))
            if selectedRuleNames.isEmpty, let firstName = rules.keys.sorted().first {
                selectedRuleNames = [firstName]
            }
            if selectedRuleNames.count == 1 {
                selectedName = selectedRuleNames.first
                loadDraft(selectedName)
            } else if selectedRuleNames.count > 1 {
                selectedName = nil
                await loadMatches(selectedRuleNames.sorted())
            } else {
                selectedName = nil
                matches = []
            }
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
        var params = rule["torrentParams"] as? [String: Any] ?? [:]
        if params.isEmpty {
            params["category"] = rule["assignedCategory"] as? String ?? ""
            params["save_path"] = rule["savePath"] as? String ?? ""
            if let stopped = rule["addPaused"] as? Bool { params["stopped"] = stopped }
            if let layout = rule["contentLayout"] as? String { params["content_layout"] = layout }
        }
        if let paramsData = try? JSONSerialization.data(withJSONObject: params, options: [.fragmentsAllowed, .sortedKeys]),
           let paramsJSON = String(data: paramsData, encoding: .utf8) {
            torrentParamsDraft = TorrentAddOptionsDraft(json: paramsJSON)
        } else {
            torrentParamsDraft = TorrentAddOptionsDraft(json: "{}")
        }
        Task { await loadMatches(name) }
    }

    private func loadMatches(_ name: String) async {
        await loadMatches([name])
    }

    private func loadMatches(_ names: [String]) async {
        let requestID = UUID()
        matchLoadID = requestID
        var mergedMatches: [String: Set<String>] = [:]
        do {
            for name in names {
                let data = try await store.rssRuleMatches(name)
                guard let result = try JSONSerialization.jsonObject(with: data) as? [String: [String]] else { throw APIError.badResponse }
                for (feed, titles) in result {
                    mergedMatches[feed, default: []].formUnion(titles)
                }
            }
            guard matchLoadID == requestID else { return }
            matches = mergedMatches
                .map { ($0.key, $0.value.sorted()) }
                .sorted { $0.0 < $1.0 }
        } catch {
            guard matchLoadID == requestID else { return }
            errorMessage = error.localizedDescription
        }
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
                selectedRuleNames = [name]
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
                guard let paramsData = try? JSONSerialization.data(
                    withJSONObject: rule["torrentParams"] as? [String: Any] ?? [:],
                    options: [.fragmentsAllowed, .sortedKeys]
                ),
                      let sourceParams = String(data: paramsData, encoding: .utf8),
                      let editedParamsJSON = torrentParamsDraft.encodedJSON(preserving: sourceParams),
                      let editedParamsData = editedParamsJSON.data(using: .utf8),
                      let editedParams = try JSONSerialization.jsonObject(with: editedParamsData) as? [String: Any] else {
                    errorMessage = "Torrent options contain an invalid value. Check the share limits and try again."
                    isSaving = false
                    return
                }
                rule["torrentParams"] = editedParams
                let encoded = try JSONSerialization.data(withJSONObject: rule, options: [.fragmentsAllowed, .sortedKeys])
                guard let definition = String(data: encoded, encoding: .utf8) else { throw APIError.badResponse }
                if newRuleName != oldName { try await store.renameRSSRule(oldName, to: newRuleName) }
                try await store.setRSSRule(name: newRuleName, definition: definition)
                await reload()
                selectedName = newRuleName
                selectedRuleNames = [newRuleName]
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
            do {
                try await store.cloneRSSRule(name, as: cloneName)
                await reload()
                selectedRuleNames = [cloneName]
                selectedName = cloneName
                loadDraft(cloneName)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func removeSelected() {
        requestRemoval(of: selectedRuleNames)
    }

    private func requestRemoval(of names: Set<String>) {
        requestRemoval(of: Array(names))
    }

    private func requestRemoval(of names: [String]) {
        let validNames = names.filter { rules[$0] != nil }.sorted()
        guard !validNames.isEmpty else { return }
        pendingRemoveRuleNames = validNames
    }

    private func removePendingRules() {
        let names = pendingRemoveRuleNames
        pendingRemoveRuleNames = []
        guard !names.isEmpty else { return }
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                for name in names { try await store.removeRSSRule(name) }
                selectedRuleNames.subtract(names)
                if let selectedName, names.contains(selectedName) { self.selectedName = nil }
                await reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func renameSelectedRule() {
        guard selectedRuleNames.count == 1, let name = selectedRuleNames.first else { return }
        renameRule(named: name)
    }

    private func renameRule(named name: String) {
        guard rules[name] != nil else { return }
        selectedRuleNames = [name]
        selectedName = name
        nameDraft = name
        Task { @MainActor in
            await Task.yield()
            isRuleNameFieldFocused = true
        }
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

    private func setFeedAssignment(_ feedURL: String, enabled: Bool) {
        let names = selectedRuleNames.sorted()
        guard names.count > 1, !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                for name in names {
                    guard var rule = rules[name] else { continue }
                    var affectedFeeds = Set(rule["affectedFeeds"] as? [String] ?? [])
                    if enabled { affectedFeeds.insert(feedURL) }
                    else { affectedFeeds.remove(feedURL) }
                    rule["affectedFeeds"] = affectedFeeds.sorted()
                    let data = try JSONSerialization.data(withJSONObject: rule, options: [.fragmentsAllowed, .sortedKeys])
                    guard let definition = String(data: data, encoding: .utf8) else { throw APIError.badResponse }
                    try await store.setRSSRule(name: name, definition: definition)
                    rules[name] = rule
                }
                await loadMatches(names)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func exportRules(format: String) {
        let panel = NSSavePanel()
        if format == "legacy" {
            panel.allowedContentTypes = [legacyRuleFileType]
            panel.nameFieldStringValue = "rss-downloader-rules.rssrules"
        } else {
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "rss-downloader-rules.json"
        }
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            Task {
                do { try await store.exportRSSRules(format: format).write(to: destination, options: .atomic) }
                catch { errorMessage = error.localizedDescription }
            }
        }
    }
}
