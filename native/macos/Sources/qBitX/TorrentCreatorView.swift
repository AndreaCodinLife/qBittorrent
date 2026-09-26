import AppKit
import SwiftUI

struct TorrentCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    let store: TorrentStore
    @State private var sourcePath = ""
    @State private var outputPath = ""
    @State private var trackers = ""
    @State private var webSeeds = ""
    @State private var comment = ""
    @State private var source = ""
    @State private var isPrivate = false
    @State private var ignoreDotfiles = true
    @State private var startSeeding = true
    @State private var pieceSize = 0
    @State private var format = "hybrid"
    @State private var taskStatus = ""
    @State private var tasks: [TorrentCreationStatus] = []
    @State private var progress = 0.0
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Torrent").font(.title2.weight(.semibold))
            Form {
                HStack {
                    TextField("Source file or folder", text: $sourcePath)
                    Button("Choose…", action: chooseSource)
                }
                HStack {
                    TextField("Save .torrent as", text: $outputPath)
                    Button("Choose…", action: chooseOutput)
                }
                Picker("Format", selection: $format) {
                    Text("Hybrid (v1 + v2)").tag("hybrid")
                    Text("BitTorrent v1").tag("v1")
                    Text("BitTorrent v2").tag("v2")
                }
                Picker("Piece size", selection: $pieceSize) {
                    ForEach([0, 16_384, 32_768, 65_536, 131_072, 262_144, 524_288, 1_048_576, 2_097_152, 4_194_304, 8_388_608, 16_777_216, 33_554_432, 67_108_864, 134_217_728], id: \.self) { size in
                        Text(size == 0 ? "Auto" : ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .binary)).tag(size)
                    }
                }
                Toggle("Ignore dotfiles", isOn: $ignoreDotfiles)
                Toggle("Private torrent", isOn: $isPrivate)
                Toggle("Start seeding immediately", isOn: $startSeeding)
                TextField("Comment", text: $comment)
                TextField("Source", text: $source)
                VStack(alignment: .leading) {
                    Text("Trackers (blank lines start a new tracker tier)")
                    TextEditor(text: $trackers).frame(height: 85)
                        .border(.quaternary)
                }
                VStack(alignment: .leading) {
                    Text("Web seed URLs (one per line)")
                    TextEditor(text: $webSeeds).frame(height: 65)
                        .border(.quaternary)
                }
            }
            .formStyle(.grouped)
            .frame(height: 500)
            HStack {
                Text("Creation history").font(.headline)
                Spacer()
                Button("Refresh") { Task { await loadTasks() } }
            }
            List(tasks) { task in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.sourcePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? task.taskID)
                            .lineLimit(1)
                        Text(task.status).font(.caption).foregroundStyle(task.status == "Failed" ? .red : .secondary)
                    }
                    Spacer()
                    if task.status == "Running", let progress = task.progress {
                        ProgressView(value: progress).frame(width: 100)
                    }
                    if task.status == "Finished" {
                        Button("Export…") { export(task) }.buttonStyle(.glass)
                    }
                    Button(role: .destructive) { delete(task) } label: { Image(systemName: "trash") }
                        .buttonStyle(.glass).help("Delete task")
                }
                .contextMenu {
                    if task.status == "Finished" { Button("Export Torrent…") { export(task) } }
                    Button("Delete Task", role: .destructive) { delete(task) }
                }
            }
            .frame(height: 140)
            if isWorking || !taskStatus.isEmpty {
                HStack {
                    Text(taskStatus)
                    if isWorking { ProgressView(value: progress).frame(width: 150) }
                }
                .font(.subheadline)
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .buttonStyle(.glassProminent)
                    .disabled(sourcePath.isEmpty || outputPath.isEmpty || isWorking || taskStatus == "Finished")
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 720, height: 770)
        .task {
            while !Task.isCancelled {
                await loadTasks()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func chooseSource() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            sourcePath = url.path
            if outputPath.isEmpty { outputPath = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".torrent").path }
        }
    }

    private func chooseOutput() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "torrent") ?? .data]
        panel.nameFieldStringValue = sourcePath.isEmpty ? "new.torrent" : URL(fileURLWithPath: sourcePath).lastPathComponent + ".torrent"
        if panel.runModal() == .OK, let url = panel.url { outputPath = url.path }
    }

    private func create() {
        isWorking = true
        errorMessage = nil
        taskStatus = "Queued"
        Task {
            do {
                let id = try await store.createTorrent(sourcePath: sourcePath, outputPath: outputPath, trackers: trackers, webSeeds: webSeeds, comment: comment, source: source, isPrivate: isPrivate, ignoreDotfiles: ignoreDotfiles, startSeeding: startSeeding, pieceSize: pieceSize, format: format)
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
