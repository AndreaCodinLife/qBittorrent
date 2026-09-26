import CoreFoundation
import Foundation
import SwiftUI

private enum PreferenceKind { case boolean, number, text, json }

private struct PreferenceItem: Identifiable {
    let id: String
    let section: String
    let label: String
    let kind: PreferenceKind
    let readOnly: Bool
    var draft: String
    let original: String

    var isDirty: Bool { draft != original }

    func encodedValue() throws -> String {
        switch kind {
        case .boolean: return draft == "true" ? "true" : "false"
        case .number:
            let data = Data(draft.utf8)
            guard let parsed = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? NSNumber,
                  CFGetTypeID(parsed) != CFBooleanGetTypeID() else { throw PreferenceError.invalidValue }
            return draft
        case .text:
            guard let text = String(data: try JSONEncoder().encode(draft), encoding: .utf8) else { throw PreferenceError.invalidValue }
            return text
        case .json:
            _ = try JSONSerialization.jsonObject(with: Data(draft.utf8), options: .fragmentsAllowed)
            return draft
        }
    }

    static func make(key: String, value: Any, bundled: Bool) -> PreferenceItem {
        let kind: PreferenceKind
        let draft: String
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                kind = .boolean
                draft = number.boolValue ? "true" : "false"
            } else {
                kind = .number
                draft = number.stringValue
            }
        } else if let string = value as? String {
            kind = .text
            draft = string
        } else {
            kind = .json
            let data = (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .prettyPrinted, .sortedKeys])) ?? Data("null".utf8)
            draft = String(data: data, encoding: .utf8) ?? "null"
        }
        let sensitive = key.contains("password") || key.contains("api_key")
        let managed = bundled && ["web_ui_address", "web_ui_port", "bypass_local_auth", "web_ui_username", "use_https", "ssl_listen_port"].contains(key)
        let shownValue = sensitive ? "••••••" : draft
        return PreferenceItem(
            id: key,
            section: section(for: key),
            label: key.replacingOccurrences(of: "_", with: " ").capitalized,
            kind: kind,
            readOnly: sensitive || managed,
            draft: shownValue,
            original: shownValue
        )
    }

    private static func section(for key: String) -> String {
        if key.hasPrefix("rss_") { return "RSS" }
        if key.hasPrefix("web_ui_") || key.hasPrefix("alternative_webui") || key.hasPrefix("bypass_auth") { return "WebUI" }
        if key.contains("search") || key.hasPrefix("python_") { return "Search" }
        if key.contains("limit") || key.hasPrefix("schedule_") || key == "scheduler_enabled" { return "Speed" }
        if key.contains("proxy") || key.contains("port") || key.contains("interface") || key.hasPrefix("dyndns_") || key == "upnp" { return "Connection" }
        if key.contains("path") || key.hasPrefix("auto_tmm") || key.hasPrefix("preallocate") || key.hasPrefix("incomplete_") || key.hasPrefix("scan_dirs") { return "Downloads" }
        if ["dht", "pex", "lsd", "encryption", "queueing_enabled", "anonymous_mode", "bittorrent_protocol"].contains(key) || key.hasPrefix("max_active") { return "BitTorrent" }
        if key.hasPrefix("confirm_") || key.hasPrefix("status_bar_") || key.hasPrefix("file_log_") || key == "locale" { return "Behavior" }
        return "Advanced"
    }
}

private enum PreferenceError: LocalizedError {
    case invalidValue
    var errorDescription: String? { "Enter a valid value before saving this preference." }
}

struct BackendPreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    let store: TorrentStore
    @State private var items: [PreferenceItem] = []
    @State private var section = "Behavior"
    @State private var searchText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let sections = ["Behavior", "Downloads", "Connection", "Speed", "BitTorrent", "Search", "RSS", "WebUI", "Advanced"]

    var body: some View {
        NavigationSplitView {
            List(sections, id: \.self, selection: $section) { name in Text(name).tag(name) }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 155, ideal: 175)
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    Text(section).font(.title2.weight(.semibold))
                    Spacer()
                    TextField("Find setting…", text: $searchText)
                        .textFieldStyle(.roundedBorder).frame(width: 180)
                    Button("Done") { dismiss() }
                }
                .padding(16)
                Divider()
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red).padding(12)
                }
                List {
                    ForEach($items) { $item in
                        if item.section == section && (searchText.isEmpty || item.id.localizedCaseInsensitiveContains(searchText) || item.label.localizedCaseInsensitiveContains(searchText)) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.label).font(.subheadline)
                                    Text(item.id).font(.caption2).foregroundStyle(.tertiary)
                                }
                                .frame(width: 190, alignment: .leading)
                                Spacer(minLength: 10)
                                if item.kind == .boolean && !item.readOnly {
                                    Toggle("", isOn: Binding(
                                        get: { item.draft == "true" },
                                        set: { item.draft = $0 ? "true" : "false" }
                                    ))
                                    .labelsHidden()
                                } else if item.kind == .json && !item.readOnly {
                                    TextField("JSON value", text: $item.draft)
                                        .textFieldStyle(.roundedBorder)
                                } else {
                                    TextField("Value", text: $item.draft)
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(item.readOnly)
                                }
                                if item.isDirty && !item.readOnly {
                                    Button("Save") { save(item) }
                                        .buttonStyle(.glass)
                                        .disabled(isSaving)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .task { await reload() }
    }

    private func reload() async {
        do {
            let data = try await store.preferencesData()
            guard let values = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PreferenceError.invalidValue }
            items = values.map { PreferenceItem.make(key: $0.key, value: $0.value, bundled: store.usesBundledBackend) }
                .sorted { $0.id < $1.id }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func save(_ item: PreferenceItem) {
        isSaving = true
        Task {
            do {
                try await store.setPreference(key: item.id, jsonValue: item.encodedValue())
                await reload()
            } catch { errorMessage = error.localizedDescription }
            isSaving = false
        }
    }
}
