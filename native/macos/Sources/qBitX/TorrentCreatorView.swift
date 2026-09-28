import AppKit
import SwiftUI

struct TorrentCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    let store: TorrentStore
    @AppStorage("qBitX.torrentCreator.sourcePath") private var sourcePath = ""
    @AppStorage("qBitX.torrentCreator.outputPath") private var outputPath = ""
    @AppStorage("qBitX.torrentCreator.trackers") private var trackers = ""
    @AppStorage("qBitX.torrentCreator.webSeeds") private var webSeeds = ""
    @AppStorage("qBitX.torrentCreator.comment") private var comment = ""
    @AppStorage("qBitX.torrentCreator.source") private var source = ""
    @AppStorage("qBitX.torrentCreator.isPrivate") private var isPrivate = false
    @AppStorage("qBitX.torrentCreator.ignoreDotfiles") private var ignoreDotfiles = true
    @AppStorage("qBitX.torrentCreator.startSeeding") private var startSeeding = true
    @AppStorage("qBitX.torrentCreator.ignoreShareLimits") private var ignoreShareLimits = false
    @AppStorage("qBitX.torrentCreator.pieceSize") private var pieceSize = 0
    @AppStorage("qBitX.torrentCreator.format") private var format = "hybrid"
    @State private var calculatedPieceCount: Int?
    @State private var isCalculatingPieces = false
    @State private var pieceCalculationError: String?
    @State private var pieceCalculationTask: Task<Void, Never>?
    @State private var taskStatus = ""
    @State private var tasks: [TorrentCreationStatus] = []
    @State private var progress = 0.0
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    contentCard

                    HStack(alignment: .top, spacing: 14) {
                        optionsCard
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        metadataCard
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    HStack(alignment: .top, spacing: 14) {
                        trackerCard
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        webSeedCard
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    historyCard
                }
                .padding(18)
            }

            Divider()
            footer
        }
        .frame(width: 800, height: 690)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: sourcePath) { _, newPath in
            invalidatePieceCount()
            if outputPath.isEmpty, !newPath.isEmpty {
                outputPath = defaultOutputPath(for: newPath)
            }
        }
        .onChange(of: pieceSize) { _, _ in invalidatePieceCount() }
        .onChange(of: format) { _, _ in invalidatePieceCount() }
        .onChange(of: ignoreDotfiles) { _, _ in invalidatePieceCount() }
        .task {
            while !Task.isCancelled {
                await loadTasks()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .onDisappear { pieceCalculationTask?.cancel() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 42, height: 42)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Create Torrent")
                    .font(.title2.weight(.semibold))
                Text("Choose content and configure the torrent file.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var contentCard: some View {
        TorrentCreatorCard(title: "Content", systemImage: "folder") {
            VStack(spacing: 12) {
                pathField(
                    title: "Source file or folder",
                    placeholder: "Choose the content to share",
                    path: $sourcePath,
                    kind: .fileOrDirectory
                )

                pathField(
                    title: "Save .torrent as",
                    placeholder: "Choose where to save the torrent file",
                    path: $outputPath,
                    kind: .saveFile
                )
            }
        }
    }

    private var optionsCard: some View {
        TorrentCreatorCard(title: "Torrent options", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Format", selection: $format) {
                    Text("Hybrid (v1 + v2)").tag("hybrid")
                    Text("BitTorrent v1").tag("v1")
                    Text("BitTorrent v2").tag("v2")
                }
                Picker("Piece size", selection: $pieceSize) {
                    ForEach(pieceSizes, id: \.self) { size in
                        Text(size == 0 ? "Auto" : ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .binary)).tag(size)
                    }
                }
                HStack(spacing: 10) {
                    Button {
                        calculatePieceCount()
                    } label: {
                        Label("Calculate Pieces", systemImage: "number")
                    }
                    .buttonStyle(.glass)
                    .disabled(sourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking || isCalculatingPieces || !store.supportsTorrentCreatorExtensions)
                    .help(store.supportsTorrentCreatorExtensions
                        ? "Calculate the exact piece count with the connected server."
                        : "This server does not support qBitX's piece-count extension.")

                    if isCalculatingPieces {
                        ProgressView()
                            .controlSize(.small)
                        Text("Calculating…")
                            .foregroundStyle(.secondary)
                    } else if let calculatedPieceCount {
                        Text("\(calculatedPieceCount) pieces")
                            .font(.callout.monospacedDigit())
                    } else if let pieceCalculationError {
                        Text(pieceCalculationError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    } else if !store.supportsTorrentCreatorExtensions {
                        Text("Piece counting requires the qBitX server extension.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                Divider()
                Toggle("Ignore dotfiles", isOn: $ignoreDotfiles)
                Toggle("Private torrent", isOn: $isPrivate)
                Toggle("Start seeding immediately", isOn: $startSeeding)
                Toggle(
                    store.supportsTorrentCreatorExtensions
                        ? "Ignore share limits for this torrent"
                        : "Ignore share limits (server extension required)",
                    isOn: Binding(
                        get: { store.supportsTorrentCreatorExtensions && ignoreShareLimits },
                        set: { ignoreShareLimits = $0 }
                    )
                )
                .disabled(!startSeeding || !store.supportsTorrentCreatorExtensions)
            }
            .controlSize(.regular)
        }
    }

    private var metadataCard: some View {
        TorrentCreatorCard(title: "Optional details", systemImage: "text.alignleft") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Comment")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Add a note to the torrent", text: $comment)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Source")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Optional source identifier", text: $source)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var trackerCard: some View {
        TorrentCreatorCard(title: "Trackers", systemImage: "point.3.connected.trianglepath.dotted") {
            VStack(alignment: .leading, spacing: 7) {
                Text("One URL per line. Leave a blank line between tiers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                editor(text: $trackers, placeholder: "udp://tracker.example:6969/announce", label: "Tracker URLs")
            }
        }
    }

    private var webSeedCard: some View {
        TorrentCreatorCard(title: "Web seeds", systemImage: "network") {
            VStack(alignment: .leading, spacing: 7) {
                Text("Add one URL per line.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                editor(text: $webSeeds, placeholder: "https://example.org/files/", label: "Web seed URLs")
            }
        }
    }

    private var historyCard: some View {
        TorrentCreatorCard(title: "Creation history", systemImage: "clock.arrow.circlepath") {
            VStack(spacing: 0) {
                HStack {
                    Text(tasks.isEmpty ? "Recent torrent creation tasks" : "\(tasks.count) saved task\(tasks.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await loadTasks() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.glass)
                }
                .padding(.bottom, 7)

                if tasks.isEmpty {
                    ContentUnavailableView(
                        "No Creations Yet",
                        systemImage: "doc.badge.plus",
                        description: Text("Torrents you create will appear here.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                } else {
                    ForEach(tasks) { task in
                        taskRow(task)
                        if task.id != tasks.last?.id { Divider().padding(.leading, 34) }
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isWorking || !taskStatus.isEmpty {
                HStack(spacing: 10) {
                    if isWorking { ProgressView(value: progress).frame(width: 140) }
                    Text(taskStatus)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(taskStatus == "Failed" ? .red : .secondary)
                    Spacer()
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(taskStatus == "Finished" ? "Create Another" : "Create Torrent") { create() }
                    .buttonStyle(.glassProminent)
                    .disabled(sourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isWorking)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var pieceSizes: [Int] {
        [0, 16_384, 32_768, 65_536, 131_072, 262_144, 524_288, 1_048_576, 2_097_152, 4_194_304, 8_388_608, 16_777_216, 33_554_432, 67_108_864, 134_217_728]
    }

    private func pathField(title: String, placeholder: String, path: Binding<String>, kind: ServerPathSelectionKind) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 9) {
                TextField(placeholder, text: path)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1)
                ServerPathBrowserButton(
                    store: store,
                    path: path,
                    kind: kind,
                    label: store.usesBundledBackend ? "Choose…" : "Browse…"
                )
            }
        }
    }

    private func editor(text: Binding<String>, placeholder: String, label: String) -> some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(5)
                .accessibilityLabel(label)
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 13)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 94)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func taskRow(_ task: TorrentCreationStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: task.status == "Finished" ? "checkmark.circle.fill" : task.status == "Failed" ? "xmark.circle.fill" : "clock")
                .foregroundStyle(task.status == "Finished" ? .green : task.status == "Failed" ? .red : .secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.sourcePath.map(lastPathComponent) ?? task.taskID)
                    .lineLimit(1)
                Text(task.status)
                    .font(.caption)
                    .foregroundStyle(task.status == "Failed" ? .red : .secondary)
            }
            Spacer(minLength: 8)
            if task.status == "Running", let taskProgress = task.progress {
                ProgressView(value: taskProgress)
                    .frame(width: 90)
            }
            if task.status == "Finished" {
                Button("Export…") { export(task) }
                    .buttonStyle(.glass)
            }
            Button(role: .destructive) { delete(task) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.glass)
            .help("Delete task")
            .accessibilityLabel("Delete \(task.sourcePath.map(lastPathComponent) ?? "creation task")")
        }
        .padding(.vertical, 7)
        .contextMenu {
            if task.status == "Finished" { Button("Export Torrent…") { export(task) } }
            Button("Delete Task", role: .destructive) { delete(task) }
        }
    }

    private func defaultOutputPath(for sourcePath: String) -> String {
        let separator: Character = sourcePath.contains("\\") && !sourcePath.contains("/") ? "\\" : "/"
        var normalized = sourcePath
        while normalized.count > 1, let last = normalized.last, last == "/" || last == "\\" {
            if normalized.count == 3, normalized[normalized.index(normalized.startIndex, offsetBy: 1)] == ":" { break }
            normalized.removeLast()
        }
        if normalized.count == 3, normalized[normalized.index(normalized.startIndex, offsetBy: 1)] == ":" {
            return normalized + "new.torrent"
        }
        let name = normalized.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? "new"
        let lastSeparator = normalized.lastIndex(where: { $0 == "/" || $0 == "\\" })
        guard let lastSeparator else { return name + ".torrent" }
        let parent = String(normalized[..<lastSeparator])
        if parent.isEmpty { return String(separator) + name + ".torrent" }
        return parent + String(separator) + name + ".torrent"
    }

    private func lastPathComponent(_ path: String) -> String {
        path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? path
    }

    private func create() {
        isWorking = true
        errorMessage = nil
        taskStatus = "Queued"
        Task {
            do {
                let id = try await store.createTorrent(sourcePath: sourcePath, outputPath: outputPath, trackers: trackers, webSeeds: webSeeds, comment: comment, source: source, isPrivate: isPrivate, ignoreDotfiles: ignoreDotfiles, startSeeding: startSeeding, ignoreShareLimits: ignoreShareLimits && store.supportsTorrentCreatorExtensions, pieceSize: pieceSize, format: format)
                for _ in 0..<600 {
                    let result = try await store.torrentCreationStatus(taskID: id)
                    taskStatus = result.status
                    progress = result.progress ?? 0
                    if result.status == "Finished" { isWorking = false; await loadTasks(); return }
                    if result.status == "Failed" {
                        errorMessage = result.errorMessage ?? "Torrent creation failed."
                        isWorking = false
                        await loadTasks()
                        return
                    }
                    try await Task.sleep(for: .seconds(1))
                }
                errorMessage = "Torrent creation is still running. Check the output file later."
            } catch { errorMessage = error.localizedDescription }
            isWorking = false
        }
    }

    private func calculatePieceCount() {
        pieceCalculationTask?.cancel()
        isCalculatingPieces = true
        calculatedPieceCount = nil
        pieceCalculationError = nil
        pieceCalculationTask = Task {
            do {
                let taskID = try await store.calculateTorrentPieces(
                    sourcePath: sourcePath,
                    pieceSize: pieceSize,
                    ignoreDotfiles: ignoreDotfiles,
                    format: format
                )
                for _ in 0..<600 {
                    try Task.checkCancellation()
                    let result = try await store.torrentPieceCount(taskID: taskID)
                    if result.status == "Finished" {
                        calculatedPieceCount = result.pieces ?? 0
                        isCalculatingPieces = false
                        return
                    }
                    if result.status == "Failed" {
                        pieceCalculationError = result.errorMessage ?? "Piece-count calculation failed."
                        isCalculatingPieces = false
                        return
                    }
                    try await Task.sleep(for: .milliseconds(500))
                }
                pieceCalculationError = "Piece-count calculation is taking longer than expected."
            } catch is CancellationError {
                return
            } catch {
                pieceCalculationError = error.localizedDescription
            }
            isCalculatingPieces = false
        }
    }

    private func invalidatePieceCount() {
        pieceCalculationTask?.cancel()
        isCalculatingPieces = false
        calculatedPieceCount = nil
        pieceCalculationError = nil
    }

    private func loadTasks() async {
        do { tasks = try await store.torrentCreationTasks() }
        catch { if errorMessage == nil { errorMessage = error.localizedDescription } }
    }

    private func delete(_ task: TorrentCreationStatus) {
        Task {
            do { try await store.deleteTorrentCreationTask(task.taskID); await loadTasks() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func export(_ task: TorrentCreationStatus) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "torrent") ?? .data]
        panel.nameFieldStringValue = (task.sourcePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "created") + ".torrent"
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            Task {
                do { try await store.createdTorrentFile(taskID: task.taskID).write(to: destination, options: .atomic) }
                catch { errorMessage = error.localizedDescription }
            }
        }
    }
}

private struct TorrentCreatorCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        }
    }
}
