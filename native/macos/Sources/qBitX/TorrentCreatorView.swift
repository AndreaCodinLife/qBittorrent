import AppKit
import SwiftUI

struct TorrentCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    let store: TorrentStore
    @State private var sourcePath = ""
    @State private var outputPath = ""
    @State private var trackers = ""
    @State private var comment = ""
    @State private var isPrivate = false
    @State private var format = "hybrid"
    @State private var taskStatus = ""
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
                Toggle("Private torrent", isOn: $isPrivate)
                TextField("Comment", text: $comment)
                VStack(alignment: .leading) {
                    Text("Trackers (one URL per line)")
                    TextEditor(text: $trackers).frame(height: 85)
                        .border(.quaternary)
                }
            }
            .formStyle(.grouped)
            .frame(height: 390)
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
        .frame(width: 650)
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
                let id = try await store.createTorrent(sourcePath: sourcePath, outputPath: outputPath, trackers: trackers, comment: comment, isPrivate: isPrivate, format: format)
                for _ in 0..<600 {
                    let result = try await store.torrentCreationStatus(taskID: id)
                    taskStatus = result.status
                    progress = result.progress ?? 0
                    if result.status == "Finished" { isWorking = false; return }
                    if result.status == "Failed" {
                        errorMessage = result.errorMessage ?? "Torrent creation failed."
                        isWorking = false
                        return
                    }
                    try await Task.sleep(for: .seconds(1))
                }
                errorMessage = "Torrent creation is still running. Check the output file later."
            } catch { errorMessage = error.localizedDescription }
            isWorking = false
        }
    }
}
