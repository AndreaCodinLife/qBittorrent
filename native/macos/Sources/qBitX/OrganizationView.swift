import SwiftUI

private struct CategoryConfiguration: Decodable {
    let savePath: String?
    let downloadPath: CategoryDownloadPath?
    let ratioLimit: Double?
    let seedingTimeLimit: Int?
    let inactiveSeedingTimeLimit: Int?
    let shareLimitsMode: String?
    let shareLimitAction: String?

    private enum CodingKeys: String, CodingKey {
        case savePath
        case downloadPath = "download_path"
        case ratioLimit = "ratio_limit"
        case seedingTimeLimit = "seeding_time_limit"
        case inactiveSeedingTimeLimit = "inactive_seeding_time_limit"
        case shareLimitsMode = "share_limits_mode"
        case shareLimitAction = "share_limit_action"
    }
}

private enum CategoryDownloadPath: Decodable {
    case enabled(Bool)
    case path(String)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let path = try? value.decode(String.self) { self = .path(path) }
        else { self = .enabled(try value.decode(Bool.self)) }
    }
}

struct OrganizationView: View {
    @Environment(\.dismiss) private var dismiss
    let store: TorrentStore
    private let initialCategoryName: String?
    @State private var categories: [String: CategoryConfiguration] = [:]
    @State private var tags: [String] = []
    @State private var selectedCategory: String?
    @State private var categoryName = ""
    @State private var savePath = ""
    @State private var downloadPathEnabled = false
    @State private var downloadPath = ""
    @State private var ratioLimit = "-2"
    @State private var seedingMinutes = "-2"
    @State private var inactiveMinutes = "-2"
    @State private var shareMode = "Default"
    @State private var shareAction = "Default"
    @State private var newTags = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var isCreatingCategory = false

    init(store: TorrentStore, initialCategoryName: String? = nil) {
        self.store = store
        self.initialCategoryName = initialCategoryName
        _categoryName = State(initialValue: initialCategoryName ?? "")
        _isCreatingCategory = State(initialValue: initialCategoryName != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Categories and Tags").font(.title2.weight(.semibold))
                Spacer()
                Button("New Category") { beginNewCategory() }
                Button("New Subcategory") { beginNewSubcategory() }
                    .disabled(selectedCategory == nil || isWorking)
                Button("Refresh") { Task { await reload() } }
                Button("Done") { dismiss() }
            }
            .padding(16)
            Divider()
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red).padding(8) }
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Categories").font(.headline)
                    List(selection: $selectedCategory) {
                        ForEach(categories.keys.sorted(), id: \.self) { name in Text(name).tag(name) }
                    }
                    .onChange(of: selectedCategory) { _, name in
                        if let name {
                            isCreatingCategory = false
                            loadCategorySettings(name)
                        } else if !isCreatingCategory {
                            loadCategorySettings(nil)
                        }
                    }
                    Form {
                        Section("Category") {
                            TextField("Category name (use / for subcategories)", text: $categoryName)
                                .disabled(!isCreatingCategory && selectedCategory != nil)
                            HStack {
                                TextField("Save path", text: $savePath)
                                ServerPathBrowserButton(store: store, path: $savePath, kind: .directory)
                            }
                            Toggle("Use a separate path for completed torrents", isOn: $downloadPathEnabled)
                            if downloadPathEnabled {
                                HStack {
                                    TextField("Completed path", text: $downloadPath)
                                    ServerPathBrowserButton(store: store, path: $downloadPath, kind: .directory)
                                }
                            }
                        }
                        Section("Share limits") {
                            TextField("Ratio (-2 = default, -1 = unlimited)", text: $ratioLimit)
                            TextField("Seeding time in minutes (-2 = default, -1 = unlimited)", text: $seedingMinutes)
                            TextField("Inactive time in minutes (-2 = default, -1 = unlimited)", text: $inactiveMinutes)
                            Picker("Limit behavior", selection: $shareMode) {
                                Text("Default").tag("Default")
                                Text("Match any limit").tag("MatchAny")
                                Text("Match all limits").tag("MatchAll")
                            }
                            Picker("When a limit is reached", selection: $shareAction) {
                                Text("Default").tag("Default")
                                Text("Stop torrent").tag("Stop")
                                Text("Remove torrent").tag("Remove")
                                Text("Remove torrent and data").tag("RemoveWithContent")
                                Text("Enable super seeding").tag("EnableSuperSeeding")
                            }
                        }
                    }
                    .formStyle(.grouped)
                    .frame(maxHeight: 380)
                    HStack {
                        Button("Create") { createCategory() }
                            .disabled(isWorking || !isCreatingCategory || !validCategory || categories[categoryName] != nil)
                        Button("Save Settings") { editCategory() }
                            .disabled(isWorking || isCreatingCategory || selectedCategory == nil || !validCategory)
                        Button("Delete", role: .destructive) { deleteCategory() }
                            .disabled(isWorking || isCreatingCategory || selectedCategory == nil)
                    }
                }
                .padding(16)
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tags").font(.headline)
                    List(tags, id: \.self) { tag in
                        HStack {
                            Text(tag)
                            Spacer()
                            Button("Delete", role: .destructive) { deleteTag(tag) }
                                .disabled(isWorking)
                        }
                    }
                    TextField("One or more comma-separated tags", text: $newTags).textFieldStyle(.roundedBorder)
                    Button("Create Tags") { createTags() }
                        .disabled(isWorking || newTags.split(separator: ",").isEmpty)
                }
                .padding(16)
            }
        }
        .frame(width: 940, height: 740)
        .task {
            await reload()
            if let initialCategoryName {
                selectedCategory = nil
                categoryName = initialCategoryName
                isCreatingCategory = true
            }
        }
    }

    private var validCategory: Bool {
        let name = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix("/"), !name.hasSuffix("/"),
              !name.contains("\\"), !name.contains("//"),
              let ratio = Double(ratioLimit), let seeding = Int(seedingMinutes), let inactive = Int(inactiveMinutes) else { return false }
        let validMinutes: (Int) -> Bool = { $0 == -2 || $0 == -1 || $0 >= 0 }
        return ratio.isFinite && (ratio == -2 || ratio == -1 || ratio >= 0) && validMinutes(seeding) && validMinutes(inactive)
    }

    private func reload() async {
        do {
            let categoryData = try await store.categoriesData()
            categories = try JSONDecoder().decode([String: CategoryConfiguration].self, from: categoryData)
            let tagData = try await store.tagsData()
            tags = (try JSONSerialization.jsonObject(with: tagData) as? [String] ?? []).sorted()
            if !isCreatingCategory, (selectedCategory == nil || categories[selectedCategory!] == nil) {
                selectedCategory = categories.keys.sorted().first
            }
            if !isCreatingCategory { loadCategorySettings(selectedCategory) }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func beginNewCategory() {
        selectedCategory = nil
        isCreatingCategory = true
        categoryName = ""
        savePath = ""
        downloadPathEnabled = false
        downloadPath = ""
        ratioLimit = "-2"
        seedingMinutes = "-2"
        inactiveMinutes = "-2"
        shareMode = "Default"
        shareAction = "Default"
    }

    private func beginNewSubcategory() {
        guard let selectedCategory else { return }
        let parent = selectedCategory.hasSuffix("/") ? selectedCategory : selectedCategory + "/"
        beginNewCategory()
        categoryName = parent
    }

    private func loadCategorySettings(_ name: String?) {
        guard let name, let category = categories[name] else {
            categoryName = ""
            savePath = ""
            downloadPathEnabled = false
            downloadPath = ""
            ratioLimit = "-2"
            seedingMinutes = "-2"
            inactiveMinutes = "-2"
            shareMode = "Default"
            shareAction = "Default"
            return
        }
        categoryName = name
        savePath = category.savePath ?? ""
        switch category.downloadPath {
        case let .path(path): downloadPathEnabled = true; downloadPath = path
        case let .enabled(enabled): downloadPathEnabled = enabled; downloadPath = ""
        case nil: downloadPathEnabled = false; downloadPath = ""
        }
        ratioLimit = category.ratioLimit.map { String($0) } ?? "-2"
        seedingMinutes = category.seedingTimeLimit.map { String($0) } ?? "-2"
        inactiveMinutes = category.inactiveSeedingTimeLimit.map { String($0) } ?? "-2"
        shareMode = category.shareLimitsMode ?? "Default"
        shareAction = category.shareLimitAction ?? "Default"
    }

    private func createCategory() {
        let name = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isCreatingCategory, !name.isEmpty else { return }
        isWorking = true
        Task {
            do {
                try await store.createCategory(name, savePath: savePath, downloadPathEnabled: downloadPathEnabled, downloadPath: downloadPath, ratioLimit: ratioLimit, seedingMinutes: seedingMinutes, inactiveMinutes: inactiveMinutes, mode: shareMode, action: shareAction)
                isCreatingCategory = false
                await reload()
                selectedCategory = name
            } catch { errorMessage = error.localizedDescription }
            isWorking = false
        }
    }

    private func editCategory() {
        guard let selectedCategory else { return }
        isWorking = true
        Task {
            do {
                try await store.editCategory(selectedCategory, savePath: savePath, downloadPathEnabled: downloadPathEnabled, downloadPath: downloadPath, ratioLimit: ratioLimit, seedingMinutes: seedingMinutes, inactiveMinutes: inactiveMinutes, mode: shareMode, action: shareAction)
                await reload()
            } catch { errorMessage = error.localizedDescription }
            isWorking = false
        }
    }

    private func deleteCategory() {
        guard let selectedCategory else { return }
        isWorking = true
        Task {
            do { try await store.removeCategory(selectedCategory); self.selectedCategory = nil; await reload() }
            catch { errorMessage = error.localizedDescription }
            isWorking = false
        }
    }

    private func createTags() {
        let values = newTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        isWorking = true
        Task {
            do { try await store.createTags(values); newTags = ""; await reload() }
            catch { errorMessage = error.localizedDescription }
            isWorking = false
        }
    }

    private func deleteTag(_ tag: String) {
        isWorking = true
        Task {
            do { try await store.removeTag(tag); await reload() }
            catch { errorMessage = error.localizedDescription }
            isWorking = false
        }
    }
}
