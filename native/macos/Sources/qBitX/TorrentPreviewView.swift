import SwiftUI
import UniformTypeIdentifiers

enum TorrentFilePreview {
    private static let multimediaExtensions: Set<String> = [
        "3gp", "aac", "ac3", "aif", "aifc", "aiff", "asf", "au", "avi", "flac", "flv",
        "m3u", "m4a", "m4p", "m4v", "mid", "mkv", "mov", "mp2", "mp3", "mp4", "mpc",
        "mpe", "mpeg", "mpg", "mpp", "ogg", "ogm", "ogv", "qt", "ra", "ram", "rm",
        "rmv", "rmvb", "swa", "swf", "ts", "vob", "wav", "wma", "wmv"
    ]

    static func isPreviewable(_ filename: String) -> Bool {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)
        return multimediaExtensions.contains(ext) || type?.conforms(to: .audio) == true || type?.conforms(to: .movie) == true
    }
}

struct TorrentPreviewView: View {
    let torrent: Torrent
    let store: TorrentStore
    let openFile: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var files: [TorrentFile] = []
    @State private var selectedFileID: Int?
    @State private var isLoading = true
    @State private var loadError: String?

    private var previewableFiles: [TorrentFile] {
        files.filter { TorrentFilePreview.isPreviewable($0.name) }
    }

    private var selectedFile: TorrentFile? {
        previewableFiles.first { $0.id == selectedFileID }
    }

    private var selectedURL: URL? {
        guard let selectedFile else { return nil }
        return URL(fileURLWithPath: torrent.savePath, isDirectory: true)
            .appending(path: selectedFile.name)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Preview File")
                        .font(.title2.weight(.semibold))
                    Text(torrent.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Open") { openSelectedFile() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedURL.map { FileManager.default.fileExists(atPath: $0.path) } != true)
            }
            .padding()
            Divider()

            Group {
                if isLoading {
                    ProgressView("Loading torrent files…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError {
                    ContentUnavailableView("Couldn’t Load Files", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else if previewableFiles.isEmpty {
                    ContentUnavailableView("No Previewable Files", systemImage: "play.rectangle", description: Text("This torrent has no audio or video files."))
                } else {
                    List(selection: $selectedFileID) {
                        ForEach(previewableFiles) { file in
                            HStack(spacing: 12) {
                                Image(systemName: URL(fileURLWithPath: file.name).pathExtension.lowercased() == "mp3" ? "waveform" : "film")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(URL(fileURLWithPath: file.name).lastPathComponent)
                                        .lineLimit(1)
                                    Text(file.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(file.progress.formatted(.percent.precision(.fractionLength(0))))
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 42, alignment: .trailing)
                            }
                            .tag(file.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                selectedFileID = file.id
                                openFileIfPresent(file)
                            }
                        }
                    }
                    .listStyle(.inset)
                    if selectedFile != nil, let url = selectedURL, !FileManager.default.fileExists(atPath: url.path) {
                        Label("This file has not been downloaded yet.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.bottom, 10)
                    }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 400)
        .task { await loadFiles() }
    }

    private func loadFiles() async {
        do {
            files = try await store.files(for: torrent.id)
            selectedFileID = previewableFiles.first?.id
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func openSelectedFile() {
        guard let selectedFile else { return }
        openFileIfPresent(selectedFile)
    }

    private func openFileIfPresent(_ file: TorrentFile) {
        let url = URL(fileURLWithPath: torrent.savePath, isDirectory: true).appending(path: file.name)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        openFile(url)
        dismiss()
    }
}
