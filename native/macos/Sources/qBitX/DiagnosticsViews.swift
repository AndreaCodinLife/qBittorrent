import SwiftUI

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
                    }
                    Section("Performance") {
                        LabeledContent("Peer connections", value: "\(statistics.total_peer_connections ?? 0)")
                        LabeledContent("Read cache hits", value: statistics.read_cache_hits ?? "—")
                        LabeledContent("Queued I/O jobs", value: "\(statistics.queued_io_jobs ?? 0)")
                        LabeledContent("Queued tracker announces", value: "\(statistics.queued_tracker_announces ?? 0)")
                        LabeledContent("Request latency", value: "\(statistics.request_latency ?? 0) ms")
                        LabeledContent("Free disk space", value: bytes(statistics.free_space_on_disk))
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

struct ExecutionLogView: View {
    @Environment(\.dismiss) private var dismiss
    let store: TorrentStore
    @State private var entries: [LogEntry] = []
    @State private var searchText = ""
    @State private var errorMessage: String?

    private var visibleEntries: [LogEntry] {
        entries.filter { searchText.isEmpty || $0.message.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Execution Log").font(.title2.weight(.semibold))
                Spacer()
                TextField("Filter messages…", text: $searchText)
                    .textFieldStyle(.roundedBorder).frame(width: 190)
                Button("Done") { dismiss() }
            }
            .padding(16)
            Divider()
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red).padding(10) }
            List(visibleEntries) { entry in
                HStack(alignment: .top, spacing: 12) {
                    Text(Date(timeIntervalSince1970: TimeInterval(entry.timestamp) / 1_000).formatted(date: .omitted, time: .standard))
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading)
                    Text(entry.message).textSelection(.enabled)
                }
                .font(.caption)
            }
        }
        .frame(width: 780, height: 520)
        .task {
            while !Task.isCancelled {
                do {
                    let latest = try await store.mainLog(after: entries.last?.id ?? -1)
                    entries.append(contentsOf: latest)
                    if entries.count > 2_000 { entries.removeFirst(entries.count - 2_000) }
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
}
