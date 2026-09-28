import AppKit
import CoreFoundation
import Foundation
import SwiftUI

private enum PreferenceKind { case boolean, number, text, json }

private struct PreferenceChoice: Identifiable, Hashable {
    let label: String
    let value: String
    var id: String { value }
}

private struct PreferenceItem: Identifiable {
    let id: String
    let section: String
    let label: String
    let kind: PreferenceKind
    let sensitive: Bool
    let readOnly: Bool
    var choices: [PreferenceChoice]
    var draft: String
    let original: String
    var secretWasEdited = false

    var isDirty: Bool { sensitive && !readOnly ? secretWasEdited : draft != original }
    var explanation: String {
        if sensitive && !readOnly && secretWasEdited && draft.isEmpty { return "Saving a blank value clears the stored password." }
        return Self.explanation(for: id)
    }
    var secretPlaceholder: String { secretWasEdited && draft.isEmpty ? "Save blank to clear password" : "Leave blank to keep current value" }
    var isMultiline: Bool { kind == .json || draft.contains("\n") || Self.multilineKeys.contains(id) }
    var pathSelectionKind: ServerPathSelectionKind? {
        switch id {
        case "save_path", "temp_path", "file_log_path", "alternative_webui_path": return .directory
        case "ip_filter_path", "web_ui_https_cert_path", "web_ui_https_key_path", "python_executable_path": return .file
        default: return nil
        }
    }
    var availableChoices: [PreferenceChoice] {
        guard !choices.contains(where: { $0.value == draft }) else { return choices }
        return [.init(label: "Current value (\(draft))", value: draft)] + choices
    }

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
        let readOnly = key.contains("api_key") || managed || ["current_interface_name", "add_trackers_url_list"].contains(key)
        let writeOnlySecret = key.contains("password")
        let shownValue = writeOnlySecret ? "" : (key.contains("api_key") && !draft.isEmpty ? "••••••" : draft)
        return PreferenceItem(
            id: key,
            section: section(for: key),
            label: label(for: key),
            kind: kind,
            sensitive: sensitive,
            readOnly: readOnly,
            choices: choices(for: key),
            draft: shownValue,
            original: shownValue
        )
    }

    private static func choices(for key: String) -> [PreferenceChoice] {
        switch key {
        case "locale":
            return [PreferenceChoice(label: "System Default", value: "")]
                + supportedLocales.map { locale in
                    PreferenceChoice(label: localeLabel(locale), value: locale)
                }
        case "torrent_content_layout":
            return [
                .init(label: "Original", value: "Original"),
                .init(label: "Create subfolder", value: "Subfolder"),
                .init(label: "Don't create subfolder", value: "NoSubfolder")
            ]
        case "torrent_stop_condition":
            return [
                .init(label: "None", value: "None"),
                .init(label: "Metadata received", value: "MetadataReceived"),
                .init(label: "Files checked", value: "FilesChecked")
            ]
        case "mail_notification_encryption_type":
            return [
                .init(label: "None", value: "None"),
                .init(label: "STARTTLS", value: "STARTTLS"),
                .init(label: "SMTPS", value: "SMTPS")
            ]
        case "proxy_type":
            return [
                .init(label: "None", value: "None"),
                .init(label: "SOCKS4", value: "SOCKS4"),
                .init(label: "SOCKS5", value: "SOCKS5"),
                .init(label: "HTTP", value: "HTTP")
            ]
        case "bittorrent_protocol":
            return [
                .init(label: "TCP and μTP", value: "0"),
                .init(label: "TCP", value: "1"),
                .init(label: "μTP", value: "2")
            ]
        case "encryption":
            return [
                .init(label: "Allow encryption", value: "0"),
                .init(label: "Require encryption", value: "1"),
                .init(label: "Disable encryption", value: "2")
            ]
        case "share_limits_mode":
            return [
                .init(label: "Use default", value: "Default"),
                .init(label: "Match any limit", value: "MatchAny"),
                .init(label: "Match all limits", value: "MatchAll")
            ]
        case "max_ratio_act":
            return [
                .init(label: "Stop torrent", value: "0"),
                .init(label: "Remove torrent", value: "1"),
                .init(label: "Enable super seeding", value: "2"),
                .init(label: "Remove torrent and its files", value: "3")
            ]
        case "resume_data_storage_type":
            return [
                .init(label: "Fastresume files", value: "Legacy"),
                .init(label: "SQLite database (experimental)", value: "SQLite")
            ]
        case "torrent_content_remove_option":
            return [
                .init(label: "Delete files permanently", value: "Delete"),
                .init(label: "Move files to trash", value: "MoveToTrash")
            ]
        case "auto_delete_mode":
            return [
                .init(label: "Never", value: "0"),
                .init(label: "After adding", value: "1"),
                .init(label: "After adding or cancelling", value: "2")
            ]
        case "scheduler_days":
            return [
                .init(label: "Every day", value: "0"),
                .init(label: "Weekdays", value: "1"),
                .init(label: "Weekends", value: "2"),
                .init(label: "Monday", value: "3"),
                .init(label: "Tuesday", value: "4"),
                .init(label: "Wednesday", value: "5"),
                .init(label: "Thursday", value: "6"),
                .init(label: "Friday", value: "7"),
                .init(label: "Saturday", value: "8"),
                .init(label: "Sunday", value: "9")
            ]
        case "disk_io_type":
            return [
                .init(label: "Default", value: "0"),
                .init(label: "Memory mapped files", value: "1"),
                .init(label: "POSIX-compliant", value: "2"),
                .init(label: "Simple pread/pwrite", value: "3"),
                .init(label: "Pread/pwrite", value: "4")
            ]
        case "disk_io_read_mode":
            return [
                .init(label: "Disable OS cache", value: "0"),
                .init(label: "Enable OS cache", value: "1")
            ]
        case "disk_io_write_mode":
            return [
                .init(label: "Disable OS cache", value: "0"),
                .init(label: "Enable OS cache", value: "1"),
                .init(label: "Write-through", value: "2")
            ]
        case "utp_tcp_mixed_mode":
            return [
                .init(label: "Prefer TCP", value: "0"),
                .init(label: "Peer proportional (throttles TCP)", value: "1")
            ]
        case "upload_slots_behavior":
            return [
                .init(label: "Fixed slots", value: "0"),
                .init(label: "Upload rate based", value: "1")
            ]
        case "upload_choking_algorithm":
            return [
                .init(label: "Round-robin", value: "0"),
                .init(label: "Fastest upload", value: "1"),
                .init(label: "Anti-leech", value: "2")
            ]
        case "dyndns_service":
            return [
                .init(label: "DynDNS", value: "0"),
                .init(label: "NO-IP", value: "1")
            ]
        case "file_log_age_type":
            return [
                .init(label: "Days", value: "0"),
                .init(label: "Months", value: "1"),
                .init(label: "Years", value: "2")
            ]
        default:
            return []
        }
    }

    private static let supportedLocales = [
        "ar", "az@latin", "be", "bg", "bs", "ca", "cs", "da", "el", "en", "en_AU", "en_GB",
        "eo", "es", "et", "eu", "fa", "fi", "fr", "gl", "he", "hi_IN", "hr", "hu", "hy", "id",
        "is", "it", "ja", "ka", "kk", "ko", "lt", "ltg", "lv_LV", "mn_MN", "ms_MY", "nb", "ne_NP",
        "nl", "oc", "pl", "pt_BR", "pt_PT", "ro", "ru", "sk", "sl", "sq", "sr", "sr@latin", "sv",
        "th", "tr", "uk", "uz@Latn", "vi", "zh_CN", "zh_HK", "zh_TW"
    ]

    private static func localeLabel(_ value: String) -> String {
        let identifier: String
        switch value {
        case "az@latin": identifier = "az_Latn"
        case "sr@latin": identifier = "sr_Latn"
        case "uz@Latn": identifier = "uz_Latn"
        default: identifier = value
        }
        return Locale.current.localizedString(forIdentifier: identifier) ?? value
    }

    private static let multilineKeys: Set<String> = [
        "add_trackers", "add_trackers_url_list", "banned_IPs", "bypass_auth_subnet_whitelist",
        "excluded_file_names", "rss_smart_episode_filters", "web_ui_custom_http_headers"
    ]

    private static func label(for key: String) -> String {
        switch key {
        case "store_search_jobs": return "Store opened search tabs"
        case "store_search_job_results": return "Also store search results"
        case "search_enabled": return "Enable search"
        case "add_trackers_url_list": return "Fetched trackers"
        case "current_interface_name": return "Selected interface name"
        case "scan_dirs": return "Watched folders"
        default: break
        }
        let acronyms: Set<String> = ["api", "dht", "i2p", "lsd", "pex", "rss", "smtp", "ssl", "upnp", "url", "webui"]
        return key.split(separator: "_").map { word in
            let value = String(word)
            return acronyms.contains(value.lowercased()) ? value.uppercased() : value.capitalized
        }.joined(separator: " ")
    }

    private static func explanation(for key: String) -> String {
        if key.contains("password") {
            return "Stored server credential. Enter a new value to replace it; leave blank to keep the current value."
        }
        if key.contains("api_key") {
            return "Generate, copy, rotate, or delete this key. Rotating it immediately invalidates the previous key."
        }
        if key.hasSuffix("_path") {
            return "Path on the qBittorrent server. Choose it with a Mac file panel for the bundled library or browse the server folders for a remote connection."
        }
        let descriptions: [String: String] = [
            "dht": "Find peers through the distributed hash table when a torrent has no reachable tracker.",
            "pex": "Exchange peer addresses with peers connected to the same torrent.",
            "lsd": "Discover BitTorrent peers on the local network.",
            "encryption": "Choose whether BitTorrent connections allow encryption, require it, or disable it.",
            "bittorrent_protocol": "Choose whether peer connections use TCP, μTP, or both.",
            "torrent_content_layout": "Choose how qBittorrent arranges files when adding a torrent.",
            "torrent_stop_condition": "Stop a new torrent after metadata arrives or files finish checking.",
            "auto_delete_mode": "Choose when qBittorrent deletes the source .torrent file after adding it.",
            "proxy_type": "Proxy protocol used for configured proxy connections.",
            "mail_notification_encryption_type": "Encryption used by the SMTP server for email notifications.",
            "share_limits_mode": "Choose whether any enabled share limit or every enabled share limit must be reached.",
            "max_ratio_act": "Action taken when a torrent reaches its share limit.",
            "resume_data_storage_type": "Storage format for torrent resume data. Changing this setting requires a restart.",
            "torrent_content_remove_option": "Choose whether removed torrent data is permanently deleted or moved to trash.",
            "dyndns_service": "Dynamic DNS provider used for domain updates.",
            "file_log_age_type": "Unit used for the file log retention age.",
            "add_trackers": "One tracker URL per line to append to torrents when adding them.",
            "banned_IPs": "IP addresses or ranges blocked from connecting to this client.",
            "bypass_auth_subnet_whitelist": "Subnets allowed to bypass Web UI authentication, one per line.",
            "excluded_file_names": "File name patterns excluded from torrents, one per line.",
            "rss_smart_episode_filters": "Episode patterns used by RSS automatic downloader rules.",
            "add_trackers_url_list": "Trackers currently returned by the configured tracker list URL.",
            "current_interface_name": "Name of the selected network interface. Choose the interface by its system name above.",
            "scan_dirs": "Automatically add .torrent files found in watched folders on the connected qBittorrent server.",
            "web_ui_custom_http_headers": "Custom Web UI response headers in Header: value format, one per line.",
            "web_ui_reverse_proxies_list": "Trusted reverse proxy IP addresses or subnets, separated by semicolons.",
            "scheduler_days": "Days when qBittorrent switches to the alternative speed limits.",
            "disk_io_type": "Disk access method used by libtorrent.",
            "disk_io_read_mode": "Controls whether disk reads use the operating system cache.",
            "disk_io_write_mode": "Controls whether disk writes use the operating system cache.",
            "utp_tcp_mixed_mode": "Controls how TCP and μTP bandwidth is shared when both are active.",
            "upload_slots_behavior": "Controls how upload slots are assigned while downloading.",
            "upload_choking_algorithm": "Controls how qBittorrent selects peers to upload to while seeding.",
            "upnp": "Ask the router to forward the listening port automatically.",
            "listen_port": "Port used for incoming BitTorrent connections.",
            "random_port": "Choose a different listening port when the client starts.",
            "max_connec": "Maximum number of peer connections across the session.",
            "max_connec_per_torrent": "Maximum number of peer connections for each torrent.",
            "max_active_downloads": "Maximum number of torrents allowed to download at the same time.",
            "max_active_uploads": "Maximum number of torrents allowed to seed at the same time.",
            "max_active_torrents": "Maximum number of active torrents in the queue.",
            "dl_limit": "Global download speed limit in bytes per second; zero means unlimited.",
            "up_limit": "Global upload speed limit in bytes per second; zero means unlimited.",
            "alt_dl_limit": "Alternative download speed limit in bytes per second.",
            "alt_up_limit": "Alternative upload speed limit in bytes per second.",
            "save_path": "Default folder for newly added torrent data.",
            "temp_path": "Folder used for incomplete torrent data when enabled.",
            "temp_path_enabled": "Store incomplete torrent data in a separate temporary folder.",
            "preallocate_all": "Allocate the full disk space for torrent files before downloading them.",
            "auto_tmm_enabled": "Let qBittorrent choose torrent paths from category and content rules.",
            "incomplete_files_ext": "Append an extension to files that are still downloading.",
            "web_ui_address": "Network interface address where the Web UI listens.",
            "web_ui_port": "TCP port used by the Web UI.",
            "web_ui_username": "Username required to sign in to the Web UI.",
            "use_https": "Serve the Web UI over HTTPS using the configured certificate.",
            "rss_refresh_interval": "How often qBittorrent checks RSS feeds for new articles.",
            "rss_auto_downloading_enabled": "Enable RSS rules that automatically add matching torrents.",
            "search_enabled": "Enable the search tab and search plugins.",
            "store_search_jobs": "Restore the search tabs on the qBittorrent server when it restarts.",
            "store_search_job_results": "Keep completed search results so restored search tabs can show their previous results.",
            "confirm_torrent_deletion": "Ask before removing a torrent from the session.",
            "locale": "Language used by the qBittorrent backend and its Web UI."
        ]
        return descriptions[key] ?? "Backend preference key: \(key). The qBittorrent Web API validates the value when saved."
    }

    private static func section(for key: String) -> String {
        if key.hasPrefix("rss_") { return "RSS" }
        if key.hasPrefix("web_ui_") || key.hasPrefix("alternative_webui") || key.hasPrefix("bypass_auth") || key.hasPrefix("dyndns_") { return "WebUI" }
        if key.contains("search") || key.hasPrefix("python_") { return "Search" }
        if key.hasPrefix("file_log_") || key.hasPrefix("confirm_") || key.hasPrefix("status_bar_")
            || ["locale", "performance_warning", "delete_torrent_content_files", "start_paused"].contains(key) { return "Behavior" }
        if advancedPreferenceKeys.contains(key) { return "Advanced" }
        if bittorrentPreferenceKeys.contains(key) { return "BitTorrent" }
        if key.contains("limit") || key.hasPrefix("schedule_") || key == "scheduler_enabled" || key == "scheduler_days" { return "Speed" }
        if key.contains("proxy") || key.contains("port") || key.contains("interface") || key.hasPrefix("i2p_") || key.hasPrefix("ip_filter") || key == "upnp" || key == "banned_IPs" { return "Connection" }
        if key.contains("path") || key.hasPrefix("auto_tmm") || key.hasPrefix("preallocate") || key.hasPrefix("incomplete_") || key.hasPrefix("scan_dirs") || key.hasPrefix("excluded_file_names") || key.hasPrefix("mail_notification_") || key.hasPrefix("autorun") || key.hasPrefix("torrent_files_backup") || ["torrent_content_layout", "torrent_stop_condition", "add_to_top_of_queue", "add_stopped_enabled", "merge_trackers", "auto_delete_mode", "use_unwanted_folder"].contains(key) { return "Downloads" }
        return "Advanced"
    }

    private static let advancedPreferenceKeys: Set<String> = [
        "current_network_interface", "current_interface_address", "current_interface_name",
        "memory_working_set_limit", "resume_data_storage_type", "save_resume_data_interval",
        "torrent_content_remove_option"
    ]

    private static let bittorrentPreferenceKeys: Set<String> = [
        "dht", "pex", "lsd", "encryption", "anonymous_mode", "bittorrent_protocol", "queueing_enabled",
        "max_active_checking_torrents", "max_active_downloads", "max_active_uploads", "max_active_torrents",
        "dont_count_slow_torrents", "slow_torrent_dl_rate_threshold", "slow_torrent_ul_rate_threshold",
        "slow_torrent_inactive_timer", "max_ratio_enabled", "max_ratio", "max_ratio_act",
        "max_seeding_time_enabled", "max_seeding_time", "max_inactive_seeding_time_enabled",
        "max_inactive_seeding_time", "share_limits_mode", "add_trackers_enabled", "add_trackers",
        "add_trackers_from_url_enabled", "add_trackers_url", "add_trackers_url_list"
    ]
}

private enum PreferenceError: LocalizedError {
    case invalidValue
    var errorDescription: String? { "Enter a valid value before saving this preference." }
}

private enum APIKeyAction: Equatable {
    case generate, rotate, delete

    var confirmationTitle: String {
        switch self {
        case .generate: "Generate API key?"
        case .rotate: "Rotate API key?"
        case .delete: "Delete API key?"
        }
    }

    var buttonTitle: String {
        switch self {
        case .generate: "Generate API Key"
        case .rotate: "Rotate API Key"
        case .delete: "Delete API Key"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .generate: "Generate a key that can be used to authenticate with qBittorrent's Web API?"
        case .rotate: "The current key will stop working immediately and a new key will be generated."
        case .delete: "The current key will stop working immediately."
        }
    }
}

struct BackendPreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    let store: TorrentStore
    @State private var items: [PreferenceItem] = []
    @State private var section = "Behavior"
    @State private var searchText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var currentAPIKey = ""
    @State private var apiKeyAction: APIKeyAction?
    @State private var isSendingTestEmail = false
    @State private var isRefreshingIPFilter = false
    @State private var statusMessage: String?
    @State private var hasAdvancedWatchedFolderOptions = false

    private let sections = ["Behavior", "Downloads", "Connection", "Speed", "BitTorrent", "Search", "RSS", "WebUI", "Advanced"]

    var body: some View {
        NavigationSplitView {
            List(sections, id: \.self, selection: $section) { name in Text(name).tag(name) }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 155, ideal: 175)
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    Text(LocalizedStringKey(searchText.isEmpty ? section : "Search Results")).font(.title2.weight(.semibold))
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
                if let statusMessage {
                    Text(statusMessage).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
                }
                List {
                    ForEach($items) { $item in
                        if (searchText.isEmpty ? item.section == section : true)
                            && (searchText.isEmpty || item.id.localizedCaseInsensitiveContains(searchText) || item.label.localizedCaseInsensitiveContains(searchText) || item.explanation.localizedCaseInsensitiveContains(searchText)) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizedStringKey(item.label)).font(.subheadline)
                                    Text(item.id).font(.caption2).foregroundStyle(.tertiary)
                                    Text(LocalizedStringKey(item.explanation)).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                    if !searchText.isEmpty { Text(LocalizedStringKey(item.section)).font(.caption2.weight(.medium)).foregroundStyle(.tint) }
                                }
                                .frame(width: 250, alignment: .leading)
                                Spacer(minLength: 10)
                                if item.id == "web_ui_api_key" {
                                    HStack(spacing: 8) {
                                        Text(currentAPIKey.isEmpty ? "Not set" : "••••••")
                                            .font(.system(.body, design: .monospaced))
                                            .accessibilityLabel("API key")
                                            .accessibilityValue(currentAPIKey.isEmpty ? "Not set" : "Set")
                                        if !currentAPIKey.isEmpty {
                                            Button("Copy") { copyAPIKey() }
                                                .buttonStyle(.glass)
                                                .disabled(isSaving || !store.isConnected)
                                                .accessibilityLabel("Copy API key")
                                        }
                                        Button(currentAPIKey.isEmpty ? "Generate" : "Rotate") {
                                            apiKeyAction = currentAPIKey.isEmpty ? .generate : .rotate
                                        }
                                        .buttonStyle(.glass)
                                        .disabled(isSaving || !store.isConnected)
                                        if !currentAPIKey.isEmpty {
                                            Button("Delete", role: .destructive) { apiKeyAction = .delete }
                                                .buttonStyle(.glass)
                                                .disabled(isSaving || !store.isConnected)
                                        }
                                    }
                                } else if item.sensitive && !item.readOnly {
                                    SecureField(item.secretPlaceholder, text: Binding(
                                        get: { item.draft },
                                        set: {
                                            item.draft = $0
                                            item.secretWasEdited = true
                                        }
                                    ))
                                        .textFieldStyle(.roundedBorder)
                                        .accessibilityLabel(item.label)
                                        .accessibilityHint(item.explanation)
                                } else if !item.choices.isEmpty && !item.readOnly {
                                    Picker("", selection: $item.draft) {
                                        ForEach(item.availableChoices) { choice in
                                            Text(LocalizedStringKey(choice.label)).tag(choice.value)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .accessibilityLabel(item.label)
                                    .accessibilityHint(item.explanation)
                                } else if item.kind == .boolean && !item.readOnly {
                                    Toggle("", isOn: Binding(
                                        get: { item.draft == "true" },
                                        set: { item.draft = $0 ? "true" : "false" }
                                    ))
                                    .labelsHidden()
                                    .accessibilityLabel(item.label)
                                    .accessibilityHint(item.explanation)
                                    .disabled(item.id == "store_search_job_results"
                                        && items.first(where: { $0.id == "store_search_jobs" })?.draft != "true")
                                } else if item.id == "scan_dirs" {
                                    WatchedFoldersPreferenceEditor(
                                        json: $item.draft,
                                        store: store,
                                        advancedOptions: hasAdvancedWatchedFolderOptions
                                    )
                                        .frame(minWidth: 340, alignment: .leading)
                                } else if item.isMultiline {
                                    TextEditor(text: $item.draft)
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(minHeight: 72, maxHeight: 96)
                                        .disabled(item.readOnly)
                                        .scrollContentBackground(.hidden)
                                        .padding(4)
                                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
                                        .accessibilityLabel(item.label)
                                        .accessibilityHint(item.explanation)
                                } else {
                                    HStack(spacing: 6) {
                                        TextField("Value", text: $item.draft)
                                            .textFieldStyle(.roundedBorder)
                                            .disabled(item.readOnly)
                                            .accessibilityLabel(item.label)
                                            .accessibilityHint(item.explanation)
                                        if let kind = item.pathSelectionKind, !item.readOnly {
                                            ServerPathBrowserButton(
                                                store: store,
                                                path: $item.draft,
                                                kind: kind,
                                                label: store.usesBundledBackend ? "Choose…" : "Browse…"
                                            )
                                            .accessibilityLabel("\(store.usesBundledBackend ? "Choose" : "Browse") \(item.label)")
                                            .accessibilityHint(store.usesBundledBackend
                                                ? (kind == .directory ? "Choose a folder on this Mac." : "Choose a file on this Mac.")
                                                : (kind == .directory ? "Browse folders on the qBittorrent server." : "Browse files on the qBittorrent server."))
                                        }
                                    }
                                }
                                if item.id == "mail_notification_enabled" {
                                    Button("Send Test Email", action: sendTestEmail)
                                        .buttonStyle(.glass)
                                        .disabled(!canSendTestEmail)
                                        .help(testEmailButtonHelp)
                                }
                                if item.id == "ip_filter_path" {
                                    Button("Refresh Filter") { refreshIPFilter() }
                                        .buttonStyle(.glass)
                                        .disabled(!canRefreshIPFilter || item.isDirty)
                                        .help(ipFilterButtonHelp)
                                }
                                if item.isDirty && !item.readOnly {
                                    Button("Save") { save(item) }
                                        .buttonStyle(.glass)
                                        .disabled(isSaving)
                                        .accessibilityLabel("Save \(item.label)")
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
        .onDisappear { currentAPIKey = "" }
        .confirmationDialog(
            apiKeyAction?.confirmationTitle ?? "API key",
            isPresented: Binding(
                get: { apiKeyAction != nil },
                set: { if !$0 { apiKeyAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = apiKeyAction {
                Button(action.buttonTitle, role: action == .delete ? .destructive : nil) {
                    apiKeyAction = nil
                    performAPIKeyAction(action)
                }
            }
            Button("Cancel", role: .cancel) { apiKeyAction = nil }
        } message: {
            Text(apiKeyAction?.confirmationMessage ?? "")
        }
    }

    private var canSendTestEmail: Bool {
        store.isConnected
            && !isSendingTestEmail
            && items.first(where: { $0.id == "mail_notification_enabled" })?.draft == "true"
            && !items.contains(where: { $0.id.hasPrefix("mail_notification_") && $0.isDirty })
    }

    private var testEmailButtonHelp: String {
        if !store.isConnected { return "Connect to qBittorrent before sending a test email." }
        if items.contains(where: { $0.id.hasPrefix("mail_notification_") && $0.isDirty }) {
            return "Save the changed email settings before sending a test."
        }
        if items.first(where: { $0.id == "mail_notification_enabled" })?.draft != "true" {
            return "Enable email notifications before sending a test."
        }
        return "Ask qBittorrent to send a test email using the saved email settings."
    }

    private var canRefreshIPFilter: Bool {
        store.isConnected
            && store.usesBundledBackend
            && !isRefreshingIPFilter
            && items.first(where: { $0.id == "ip_filter_enabled" })?.draft == "true"
            && items.first(where: { $0.id == "ip_filter_path" })?.draft.isEmpty == false
            && !items.contains(where: { ["ip_filter_enabled", "ip_filter_path"].contains($0.id) && $0.isDirty })
    }

    private var ipFilterButtonHelp: String {
        if !store.isConnected { return "Connect to qBittorrent before refreshing the IP filter." }
        if !store.usesBundledBackend { return "IP-filter refresh is available with the bundled qBittorrent backend." }
        if items.first(where: { $0.id == "ip_filter_enabled" })?.draft != "true" {
            return "Enable IP filtering before refreshing the filter."
        }
        if items.contains(where: { ["ip_filter_enabled", "ip_filter_path"].contains($0.id) && $0.isDirty }) {
            return "Save IP-filter settings before refreshing the filter."
        }
        return "Reload the saved filter file. Check the Execution Log for the parse result."
    }

    private func reload() async {
        do {
            let data = try await store.preferencesData()
            guard let values = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PreferenceError.invalidValue }
            currentAPIKey = values["web_ui_api_key"] as? String ?? ""
            var loadedItems = values.map { PreferenceItem.make(key: $0.key, value: $0.value, bundled: store.usesBundledBackend) }
                .sorted { $0.id < $1.id }

            hasAdvancedWatchedFolderOptions = false
            if let watchedFoldersData = try? await store.watchedFoldersData(),
               let watchedFolders = try? JSONSerialization.jsonObject(with: watchedFoldersData) as? [String: Any],
               let scanDirectoriesIndex = loadedItems.firstIndex(where: { $0.id == "scan_dirs" }) {
                loadedItems[scanDirectoriesIndex] = PreferenceItem.make(
                    key: "scan_dirs",
                    value: watchedFolders,
                    bundled: true
                )
                hasAdvancedWatchedFolderOptions = true
            }

            if let interfaces = try? await store.networkInterfaces(),
               let index = loadedItems.firstIndex(where: { $0.id == "current_network_interface" }) {
                var choices = [PreferenceChoice(label: "Any interface", value: "")]
                    + interfaces.map { PreferenceChoice(label: $0.name, value: $0.value) }
                let currentInterface = loadedItems[index].draft
                if !currentInterface.isEmpty && !choices.contains(where: { $0.value == currentInterface }) {
                    let name = values["current_interface_name"] as? String ?? currentInterface
                    choices.append(.init(label: "Current interface (\(name))", value: currentInterface))
                }
                loadedItems[index].choices = choices
            }

            let currentInterface = values["current_network_interface"] as? String ?? ""
            if let addresses = try? await store.networkInterfaceAddresses(for: currentInterface),
               let index = loadedItems.firstIndex(where: { $0.id == "current_interface_address" }) {
                let choices = [
                    PreferenceChoice(label: "All addresses", value: ""),
                    PreferenceChoice(label: "All IPv4 addresses", value: "0.0.0.0"),
                    PreferenceChoice(label: "All IPv6 addresses", value: "::")
                ] + addresses.map { PreferenceChoice(label: $0, value: $0) }
                loadedItems[index].choices = choices
            }

            items = loadedItems
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func copyAPIKey() {
        guard !currentAPIKey.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentAPIKey, forType: .string)
    }

    private func sendTestEmail() {
        guard canSendTestEmail else { return }
        isSendingTestEmail = true
        statusMessage = nil
        Task {
            do {
                try await store.sendTestEmail()
                statusMessage = "qBittorrent attempted to send a test email. Check your inbox and the Execution Log for the result."
            } catch {
                errorMessage = error.localizedDescription
            }
            isSendingTestEmail = false
        }
    }

    private func refreshIPFilter() {
        guard canRefreshIPFilter else { return }
        isRefreshingIPFilter = true
        statusMessage = nil
        Task {
            do {
                try await store.refreshIPFilter()
                statusMessage = "qBittorrent requested an IP-filter refresh. Check the Execution Log for the parse result."
            } catch {
                errorMessage = error.localizedDescription
            }
            isRefreshingIPFilter = false
        }
    }

    private func performAPIKeyAction(_ action: APIKeyAction) {
        isSaving = true
        Task {
            do {
                switch action {
                case .generate, .rotate:
                    let result = try await store.rotateWebUIAPIKey()
                    currentAPIKey = result.key
                    await reload()
                    if let warning = result.warning { errorMessage = warning }
                case .delete:
                    currentAPIKey = ""
                    if try await store.deleteWebUIAPIKey() {
                        await reload()
                    } else {
                        errorMessage = store.connectionError
                    }
                }
            } catch { errorMessage = error.localizedDescription }
            isSaving = false
        }
    }

    private func save(_ item: PreferenceItem) {
        isSaving = true
        Task {
            do {
                if item.id == "scan_dirs", hasAdvancedWatchedFolderOptions {
                    try await store.setWatchedFolders(json: item.draft)
                } else {
                    try await store.setPreference(key: item.id, jsonValue: item.encodedValue())
                }
                await reload()
            } catch { errorMessage = error.localizedDescription }
            isSaving = false
        }
    }
}
