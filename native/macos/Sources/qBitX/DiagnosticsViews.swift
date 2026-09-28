import AppKit
import SwiftUI
import QBitXThemeSupport

struct StatisticsView: View {
    @Environment(\.dismiss) private var dismiss
    let store: TorrentStore
    @State private var statistics: ServerStatistics?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Statistics").font(.title2.weight(.semibold))
                Spacer()
                Button("Refresh") { Task { await load() } }
                Button("Done") { dismiss() }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            if let statistics {
                Form {
                    Section("All Time") {
                        LabeledContent("Downloaded", value: bytes(statistics.alltime_dl))
                        LabeledContent("Uploaded", value: bytes(statistics.alltime_ul))
                        LabeledContent("Global ratio", value: statistics.global_ratio ?? "—")
                    }
                    Section("Current Session") {
                        LabeledContent("Downloaded", value: bytes(statistics.dl_info_data))
                        LabeledContent("Uploaded", value: bytes(statistics.up_info_data))
                        LabeledContent("Wasted", value: bytes(statistics.total_wasted_session))
                        LabeledContent("Connected peers", value: "\(statistics.total_peer_connections ?? 0)")
                    }
                    Section("Cache") {
                        LabeledContent("Read cache hits", value: "\(statistics.read_cache_hits ?? "—")%")
                        LabeledContent("Total buffer size", value: bytes(statistics.total_buffers_size))
                    }
                    Section("Performance") {
                        LabeledContent("Write cache overload", value: "\(statistics.write_cache_overload ?? "—")%")
                        LabeledContent("Read cache overload", value: "\(statistics.read_cache_overload ?? "—")%")
                        LabeledContent("Queued I/O jobs", value: "\(statistics.queued_io_jobs ?? 0)")
                        LabeledContent("Average time in queue", value: "\(statistics.average_time_queue ?? 0) ms")
                        LabeledContent("Total queued size", value: bytes(statistics.total_queued_size))
                        LabeledContent("Queued tracker announces", value: "\(statistics.queued_tracker_announces ?? 0)")
                        LabeledContent("Request latency", value: "\(statistics.request_latency ?? 0) ms")
                    }
                }
            } else if errorMessage == nil {
                ProgressView("Loading statistics…")
            }
        }
        .padding(22)
        .frame(width: 560, height: 540)
        .task { await load() }
    }

    private func bytes(_ value: Int64?) -> String {
        guard let value, value >= 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func load() async {
        do { statistics = try await store.statistics(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}

private enum ExecutionLogTab: String, CaseIterable, Identifiable, Hashable {
    case general = "General"
    case blockedIPs = "Blocked IPs"

    var id: Self { self }
}

struct ExecutionLogView: View {
    private let maximumVisibleEntries = 20_000
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("qBitX.themePalette") private var themePaletteJSON = ""
    let store: TorrentStore
    let onClose: () -> Void
    @State private var entries: [LogEntry] = []
    @State private var peerEntries: [PeerLogEntry] = []
    @State private var selectedTab = ExecutionLogTab.general
    @State private var selectedEntryIDs: Set<Int> = []
    @State private var selectedPeerEntryIDs: Set<Int> = []
    @State private var lastMainLogID = -1
    @State private var lastPeerLogID = -1
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var showNormal = true
    @State private var showInfo = true
    @State private var showWarnings = true
    @State private var showCritical = true

    private var visibleEntries: [LogEntry] {
        entries.filter { entry in
            let matchesType = switch entry.type {
            case 0x1: showNormal
            case 0x2: showInfo
            case 0x4: showWarnings
            case 0x8: showCritical
            default: false
            }
            return matchesType && (searchText.isEmpty || entry.message.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var visiblePeerEntries: [PeerLogEntry] {
        peerEntries.filter {
            searchText.isEmpty
                || $0.ip.localizedCaseInsensitiveContains(searchText)
                || $0.reason.localizedCaseInsensitiveContains(searchText)
                || ($0.blocked ? "Blocked" : "Banned").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Text("Execution Log").font(.title2.weight(.semibold))
                    Spacer()
                    Picker("Log", selection: $selectedTab) {
                        ForEach(ExecutionLogTab.allCases) { tab in Text(tab.rawValue).tag(tab) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                    Button("Hide", action: onClose)
                }
                HStack {
                    TextField("Filter messages…", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                    if selectedTab == .general {
                        Menu("Message Types") {
                            Toggle("Normal", isOn: $showNormal)
                            Toggle("Information", isOn: $showInfo)
                            Toggle("Warning", isOn: $showWarnings)
                            Toggle("Critical", isOn: $showCritical)
                        }
                    }
                    Spacer()
                    Button { copySelectedEntries() } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.glass)
                        .help("Copy selected entries")
                        .accessibilityLabel("Copy selected entries")
                        .disabled(selectedTab == .general ? selectedEntryIDs.isEmpty : selectedPeerEntryIDs.isEmpty)
                    Button { clearVisibleEntries() } label: { Image(systemName: "trash") }
                        .buttonStyle(.glass)
                        .help("Clear visible log entries")
                        .accessibilityLabel("Clear visible log entries")
                }
            }
            .padding(12)
            Divider()
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red).padding(10) }
            switch selectedTab {
            case .general:
                List(visibleEntries, selection: $selectedEntryIDs) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        Text(timestamp(entry.timestamp))
                            .foregroundStyle(themeColor(for: "Log.TimeStamp") ?? Color.primary.opacity(0.6))
                            .frame(width: 90, alignment: .leading)
                        Text(entry.message)
                            .foregroundStyle(messageColor(for: entry.type))
                            .textSelection(.enabled)
                    }
                    .font(.caption)
                    .tag(entry.id)
                    .contextMenu {
                        Button("Copy") { copyMainEntries(entriesToCopy(focusedID: entry.id)) }
                        Button("Clear") { clearMainEntries() }
                    }
                }
            case .blockedIPs:
                List(visiblePeerEntries, selection: $selectedPeerEntryIDs) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        Text(timestamp(entry.timestamp))
                            .foregroundStyle(themeColor(for: "Log.TimeStamp") ?? Color.primary.opacity(0.6))
                            .frame(width: 90, alignment: .leading)
                        Text(entry.ip)
                            .foregroundStyle(themeColor(for: "Log.BannedPeer") ?? .primary)
                            .frame(minWidth: 130, alignment: .leading)
                        Text(entry.blocked ? "Blocked" : "Banned")
                            .foregroundStyle(themeColor(for: "Log.BannedPeer") ?? .primary)
                            .frame(width: 90, alignment: .leading)
                        Text(entry.reason)
                            .foregroundStyle(themeColor(for: "Log.BannedPeer") ?? .primary)
                            .textSelection(.enabled)
                    }
                    .font(.caption)
                    .tag(entry.id)
                    .contextMenu {
                        Button("Copy") { copyPeerEntries(peerEntriesToCopy(focusedID: entry.id)) }
                        Button("Clear") { clearPeerEntries() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: selectedTab) {
            errorMessage = nil
            while !Task.isCancelled {
                do {
                    switch selectedTab {
                    case .general:
                        let latest = try await store.mainLog(after: lastMainLogID)
                        if let newestID = latest.map(\.id).max() {
                            lastMainLogID = max(lastMainLogID, newestID)
                            entries.append(contentsOf: latest)
                            if entries.count > maximumVisibleEntries { entries.removeFirst(entries.count - maximumVisibleEntries) }
                        }
                    case .blockedIPs:
                        let latest = try await store.peerLog(after: lastPeerLogID)
                        if let newestID = latest.map(\.id).max() {
                            lastPeerLogID = max(lastPeerLogID, newestID)
                            peerEntries.append(contentsOf: latest)
                            if peerEntries.count > maximumVisibleEntries { peerEntries.removeFirst(peerEntries.count - maximumVisibleEntries) }
                        }
                    }
                    errorMessage = nil
                    try await Task.sleep(for: .seconds(2))
                } catch is CancellationError { return }
                catch {
                    errorMessage = error.localizedDescription
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        }
    }

    private func timestamp(_ value: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(value)).formatted(date: .omitted, time: .standard)
    }

    private func themeColor(for id: String) -> Color? {
        guard let color = QBitXThemePalette(storedJSON: themePaletteJSON)?
            .color(for: id, isDark: colorScheme == .dark)
        else { return nil }
        return Color(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }

    private func messageColor(for type: Int) -> Color {
        let colorID: String
        let fallback: Color
        switch type {
        case 0x2:
            colorID = "Log.Info"
            fallback = .blue
        case 0x4:
            colorID = "Log.Warning"
            fallback = .orange
        case 0x8:
            colorID = "Log.Critical"
            fallback = .red
        default:
            colorID = "Log.Normal"
            fallback = .primary
        }
        return themeColor(for: colorID) ?? fallback
    }

    private func clearVisibleEntries() {
        if selectedTab == .general { clearMainEntries() }
        else { clearPeerEntries() }
    }

    private func clearMainEntries() {
        entries = []
        selectedEntryIDs = []
    }

    private func clearPeerEntries() {
        peerEntries = []
        selectedPeerEntryIDs = []
    }

    private func entriesToCopy(focusedID: Int) -> [LogEntry] {
        let selected = selectedEntryIDs.isEmpty || !selectedEntryIDs.contains(focusedID)
            ? [focusedID]
            : Array(selectedEntryIDs)
        return entries.filter { selected.contains($0.id) }
    }

    private func peerEntriesToCopy(focusedID: Int) -> [PeerLogEntry] {
        let selected = selectedPeerEntryIDs.isEmpty || !selectedPeerEntryIDs.contains(focusedID)
            ? [focusedID]
            : Array(selectedPeerEntryIDs)
        return peerEntries.filter { selected.contains($0.id) }
    }

    private func copySelectedEntries() {
        if selectedTab == .general {
            copyMainEntries(entries.filter { selectedEntryIDs.contains($0.id) })
        } else {
            copyPeerEntries(peerEntries.filter { selectedPeerEntryIDs.contains($0.id) })
        }
    }

    private func copyMainEntries(_ values: [LogEntry]) {
        let content = values.map { "\(timestamp($0.timestamp))\t\($0.message)" }.joined(separator: "\n")
        guard !content.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    private func copyPeerEntries(_ values: [PeerLogEntry]) {
        let content = values.map {
            "\(timestamp($0.timestamp))\t\($0.ip)\t\($0.blocked ? "Blocked" : "Banned")\t\($0.reason)"
        }.joined(separator: "\n")
        guard !content.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
}
