import Foundation
import SwiftUI
import CoreFoundation

private enum WatchedFolderDestination: String, CaseIterable, Identifiable {
    case watchedFolder
    case defaultLocation
    case customLocation

    var id: String { rawValue }

    var label: String {
        switch self {
        case .watchedFolder: "Watched folder"
        case .defaultLocation: "Default save location"
        case .customLocation: "Custom location"
        }
    }
}

private struct WatchedFolderDraft: Identifiable, Equatable {
    let id: UUID
    var path: String
    var recursive: Bool
    var destination: WatchedFolderDestination
    var customSavePath: String
    var addTorrentParamsJSON: String

    init(
        path: String = "",
        recursive: Bool = false,
        destination: WatchedFolderDestination = .defaultLocation,
        customSavePath: String = "",
        addTorrentParamsJSON: String = Self.defaultAddTorrentParamsJSON
    ) {
        id = UUID()
        self.path = path
        self.recursive = recursive
        self.destination = destination
        self.customSavePath = customSavePath
        self.addTorrentParamsJSON = addTorrentParamsJSON
    }

    private static let defaultAddTorrentParamsJSON = """
    {"category":"","tags":[],"save_path":"","download_path":"","operating_mode":"AutoManaged","seed_mode":false,"upload_limit":-1,"download_limit":-1,"ratio_limit":-2,"seeding_time_limit":-2,"inactive_seeding_time_limit":-2,"share_limit_action":"Default","share_limits_mode":"Default","ssl_certificate":"","ssl_private_key":"","ssl_dh_params":""}
    """

    static func decode(path: String, value: Any) -> WatchedFolderDraft? {
        if let legacySavePath = value as? String {
            return WatchedFolderDraft(
                path: path,
                destination: .customLocation,
                customSavePath: legacySavePath
            )
        }

        if let number = value as? NSNumber {
            return WatchedFolderDraft(
                path: path,
                destination: number.intValue == 0 ? .watchedFolder : .defaultLocation
            )
        }

        guard let options = value as? [String: Any],
              let recursive = options["recursive"] as? Bool,
              let addTorrentParams = options["add_torrent_params"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: addTorrentParams, options: [.sortedKeys]),
              let paramsJSON = String(data: data, encoding: .utf8) else { return nil }

        return WatchedFolderDraft(path: path, recursive: recursive, addTorrentParamsJSON: paramsJSON)
    }

    var encodedValue: Any? {
        let cleanPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPath.isEmpty else { return nil }

        if let data = addTorrentParamsJSON.data(using: .utf8),
           let params = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return ["recursive": recursive, "add_torrent_params": params]
        }
        return ["recursive": recursive, "add_torrent_params": [:]]
    }

    var encodedLegacyValue: Any? {
        let cleanPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPath.isEmpty else { return nil }
        switch destination {
        case .watchedFolder:
            return 0
        case .defaultLocation:
            return 1
        case .customLocation:
            let savePath = customSavePath.trimmingCharacters(in: .whitespacesAndNewlines)
            return savePath.isEmpty ? nil : savePath
        }
    }
}

struct WatchedFoldersPreferenceEditor: View {
    @Binding private var json: String
    @State private var folders: [WatchedFolderDraft]
    @State private var editingFolder: FolderOptionsSelection?

    let store: TorrentStore
    let advancedOptions: Bool

    init(json: Binding<String>, store: TorrentStore, advancedOptions: Bool) {
        _json = json
        _folders = State(initialValue: Self.decode(json.wrappedValue))
        self.store = store
        self.advancedOptions = advancedOptions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if folders.isEmpty {
                Text("No watched folders")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach($folders) { $folder in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                TextField("Folder containing .torrent files", text: $folder.path)
                                    .textFieldStyle(.roundedBorder)
                                ServerPathBrowserButton(store: store, path: $folder.path, kind: .directory)
                                    .accessibilityLabel("Choose watched folder")
                                Button(role: .destructive) {
                                    folders.removeAll { $0.id == folder.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove watched folder")
                            }

                            if advancedOptions {
                                HStack {
                                    Toggle("Watch subfolders", isOn: $folder.recursive)
                                        .toggleStyle(.checkbox)
                                    Spacer()
                                    Button("Torrent Options…") {
                                        editingFolder = FolderOptionsSelection(id: folder.id)
                                    }
                                    .buttonStyle(.glass)
                                }
                            } else {
                                legacyDestinationEditor(for: $folder)
                            }
                        }
                        .padding(8)
                        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(maxHeight: 260)

            Button {
                folders.append(WatchedFolderDraft())
            } label: {
                Label("Add Watched Folder", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
        .onChange(of: folders) { _, _ in encode() }
        .sheet(item: $editingFolder) { selection in
            WatchedFolderAddOptionsSheet(folder: binding(for: selection.id), store: store)
        }
    }

    @ViewBuilder
    private func legacyDestinationEditor(for folder: Binding<WatchedFolderDraft>) -> some View {
        Picker("Add torrents to", selection: folder.destination) {
            ForEach(WatchedFolderDestination.allCases) { destination in
                Text(LocalizedStringKey(destination.label)).tag(destination)
            }
        }
        .pickerStyle(.menu)

        if folder.wrappedValue.destination == .customLocation {
            HStack(spacing: 6) {
                TextField("Custom save folder", text: folder.customSavePath)
                    .textFieldStyle(.roundedBorder)
                ServerPathBrowserButton(store: store, path: folder.customSavePath, kind: .directory)
                    .accessibilityLabel("Choose custom save folder")
            }
        }
    }

    private func binding(for id: UUID) -> Binding<WatchedFolderDraft> {
        guard let index = folders.firstIndex(where: { $0.id == id }) else {
            return .constant(WatchedFolderDraft())
        }
        return $folders[index]
    }

    private static func decode(_ json: String) -> [WatchedFolderDraft] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return values.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.compactMap { path in
            guard let value = values[path] else { return nil }
            return WatchedFolderDraft.decode(path: path, value: value)
        }
    }

    private func encode() {
        var values: [String: Any] = [:]
        for folder in folders {
            let path = folder.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { continue }
            let value = advancedOptions ? folder.encodedValue : folder.encodedLegacyValue
            guard let value else { continue }
            values[path] = value
        }
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]),
              let value = String(data: data, encoding: .utf8) else { return }
        json = value
    }
}

private struct FolderOptionsSelection: Identifiable {
    let id: UUID
}

enum DefaultableBool: String, CaseIterable, Identifiable {
    case `default`
    case yes
    case no

    var id: String { rawValue }

    var label: String {
        switch self {
        case .default: "Default"
        case .yes: "Yes"
        case .no: "No"
        }
    }

    init(value: Bool?) {
        switch value {
        case .some(true): self = .yes
        case .some(false): self = .no
        case .none: self = .default
        }
    }

    var value: Bool? {
        switch self {
        case .default: nil
        case .yes: true
        case .no: false
        }
    }
}

enum ShareValueMode: String, CaseIterable, Identifiable {
    case defaultValue
    case unlimited
    case setValue

    var id: String { rawValue }

    var label: String {
        switch self {
        case .defaultValue: "Default"
        case .unlimited: "Unlimited"
        case .setValue: "Set to"
        }
    }
}

struct TorrentAddOptionsDraft {
    var managementMode = DefaultableBool.default
    var savePath = ""
    var useDownloadPath = DefaultableBool.default
    var downloadPath = ""
    var category = ""
    var tags = ""
    var contentLayout: String?
    var seedMode = false
    var startTorrent = DefaultableBool.default
    var stopCondition: String?
    var addToQueueTop = DefaultableBool.default
    var ratioMode = ShareValueMode.defaultValue
    var ratioValue = "1.0"
    var seedingTimeMode = ShareValueMode.defaultValue
    var seedingTimeValue = "1440"
    var inactiveTimeMode = ShareValueMode.defaultValue
    var inactiveTimeValue = "1440"
    var shareLimitsMode = "Default"
    var shareLimitAction = "Default"

    init(json: String) {
        guard let data = json.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        managementMode = DefaultableBool(value: values["use_auto_tmm"] as? Bool)
        savePath = values["save_path"] as? String ?? ""
        useDownloadPath = DefaultableBool(value: values["use_download_path"] as? Bool)
        downloadPath = values["download_path"] as? String ?? ""
        category = values["category"] as? String ?? ""
        tags = (values["tags"] as? [String] ?? []).joined(separator: ", ")
        contentLayout = values["content_layout"] as? String
        seedMode = values["seed_mode"] as? Bool ?? false
        startTorrent = DefaultableBool(value: Self.boolValue(values["stopped"]).map { !$0 })
        stopCondition = values["stop_condition"] as? String
        addToQueueTop = DefaultableBool(value: values["add_to_top_of_queue"] as? Bool)

        if let value = Self.number(values["ratio_limit"]) {
            ratioMode = value == -2 ? .defaultValue : (value == -1 ? .unlimited : .setValue)
            ratioValue = String(value.doubleValue)
        }
        if let value = Self.number(values["seeding_time_limit"])?.intValue {
            seedingTimeMode = value == -2 ? .defaultValue : (value == -1 ? .unlimited : .setValue)
            seedingTimeValue = String(max(0, value))
        }
        if let value = Self.number(values["inactive_seeding_time_limit"])?.intValue {
            inactiveTimeMode = value == -2 ? .defaultValue : (value == -1 ? .unlimited : .setValue)
            inactiveTimeValue = String(max(0, value))
        }
        shareLimitsMode = values["share_limits_mode"] as? String ?? "Default"
        shareLimitAction = values["share_limit_action"] as? String ?? "Default"
    }

    var hasValidValues: Bool {
        let ratioValid = ratioMode != .setValue || (Double(ratioValue).map { $0 >= 0 } ?? false)
        let seedingValid = seedingTimeMode != .setValue || (Int(seedingTimeValue).map { $0 >= 0 } ?? false)
        let inactiveValid = inactiveTimeMode != .setValue || (Int(inactiveTimeValue).map { $0 >= 0 } ?? false)
        return ratioValid && seedingValid && inactiveValid
    }

    func encodedJSON(preserving sourceJSON: String) -> String? {
        guard hasValidValues,
              let sourceData = sourceJSON.data(using: .utf8),
              var values = try? JSONSerialization.jsonObject(with: sourceData) as? [String: Any] else { return nil }

        values["category"] = category
        values["tags"] = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        values["seed_mode"] = seedMode
        values["ratio_limit"] = shareValue(ratioMode, value: Double(ratioValue), default: -2, unlimited: -1)
        values["seeding_time_limit"] = shareValue(seedingTimeMode, value: Int(seedingTimeValue), default: -2, unlimited: -1)
        values["inactive_seeding_time_limit"] = shareValue(inactiveTimeMode, value: Int(inactiveTimeValue), default: -2, unlimited: -1)
        values["share_limits_mode"] = shareLimitsMode
        values["share_limit_action"] = shareLimitAction

        setOptionalBool(managementMode.value, key: "use_auto_tmm", in: &values)
        setOptionalBool(addToQueueTop.value, key: "add_to_top_of_queue", in: &values)
        setOptionalString(contentLayout, key: "content_layout", in: &values)
        setOptionalString(stopCondition, key: "stop_condition", in: &values)

        if let starts = startTorrent.value {
            values["stopped"] = !starts
        } else {
            values.removeValue(forKey: "stopped")
        }

        if managementMode.value == false {
            values["save_path"] = savePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if useDownloadPath.value == true {
                values["use_download_path"] = true
                values["download_path"] = downloadPath.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                values.removeValue(forKey: "use_download_path")
                values.removeValue(forKey: "download_path")
            }
        } else {
            values["save_path"] = ""
            values.removeValue(forKey: "use_download_path")
            values["download_path"] = ""
        }

        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func shareValue<T: BinaryInteger>(_ mode: ShareValueMode, value: T?, default defaultValue: T, unlimited unlimitedValue: T) -> T? {
        switch mode {
        case .defaultValue: defaultValue
        case .unlimited: unlimitedValue
        case .setValue: value
        }
    }

    private func shareValue(_ mode: ShareValueMode, value: Double?, default defaultValue: Double, unlimited unlimitedValue: Double) -> Double? {
        switch mode {
        case .defaultValue: defaultValue
        case .unlimited: unlimitedValue
        case .setValue: value
        }
    }

    private func setOptionalBool(_ value: Bool?, key: String, in object: inout [String: Any]) {
        if let value { object[key] = value }
        else { object.removeValue(forKey: key) }
    }

    private func setOptionalString(_ value: String?, key: String, in object: inout [String: Any]) {
        if let value { object[key] = value }
        else { object.removeValue(forKey: key) }
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        guard let value, !(value is NSNull) else { return nil }
        return value as? Bool
    }

    private static func number(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number
    }
}

private struct WatchedFolderAddOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var folder: WatchedFolderDraft
    @State private var draft: TorrentAddOptionsDraft

    let store: TorrentStore

    init(folder: Binding<WatchedFolderDraft>, store: TorrentStore) {
        _folder = folder
        _draft = State(initialValue: TorrentAddOptionsDraft(json: folder.wrappedValue.addTorrentParamsJSON))
        self.store = store
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TorrentAddOptionsFields(draft: $draft, store: store)
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.hasValidValues)
            }
            .padding()
        }
        .frame(minWidth: 620, minHeight: 680)
    }

    private func save() {
        guard let json = draft.encodedJSON(preserving: folder.addTorrentParamsJSON) else { return }
        folder.addTorrentParamsJSON = json
        dismiss()
    }
}
