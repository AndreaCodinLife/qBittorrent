import AppKit
import SwiftUI

enum ServerPathSelectionKind: Equatable {
    case file
    case directory
    case fileOrDirectory
    case saveFile

    var listsFiles: Bool { self == .file || self == .fileOrDirectory }
    var choosesFolder: Bool { self == .directory || self == .fileOrDirectory }
}

struct ServerPathBrowserButton: View {
    @State private var showsServerPicker = false

    let store: TorrentStore
    @Binding var path: String
    let kind: ServerPathSelectionKind
    var label: String? = nil

    var body: some View {
        Button {
            if store.usesBundledBackend {
                chooseLocalPath()
            } else {
                showsServerPicker = true
            }
        } label: {
            if let label {
                Text(label)
            } else {
                Image(systemName: "folder")
            }
        }
        .buttonStyle(.glass)
        .help(actionHelp)
        .accessibilityLabel(label ?? actionLabel)
        .sheet(isPresented: $showsServerPicker) {
            ServerPathPickerView(store: store, path: $path, kind: kind, initialPath: path)
        }
    }

    private func chooseLocalPath() {
        if kind == .saveFile {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.init(filenameExtension: "torrent") ?? .data]
            panel.nameFieldStringValue = path.isEmpty ? "new.torrent" : URL(fileURLWithPath: path).lastPathComponent
            if !path.isEmpty { panel.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent() }
            if panel.runModal() == .OK, let url = panel.url { path = url.path }
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = kind == .file || kind == .fileOrDirectory
        panel.canChooseDirectories = kind == .directory || kind == .fileOrDirectory
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = kind == .directory
        panel.message = switch kind {
        case .directory: "Choose a folder on this Mac."
        case .file: "Choose a file on this Mac."
        case .fileOrDirectory: "Choose a file or folder on this Mac."
        case .saveFile: "Choose where to save the .torrent file."
        }
        if !path.isEmpty {
            let currentURL = URL(fileURLWithPath: path)
            if kind == .directory {
                panel.directoryURL = currentURL
            } else if kind == .fileOrDirectory {
                var isDirectory: ObjCBool = false
                let existsAsDirectory = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
                panel.directoryURL = existsAsDirectory ? currentURL : currentURL.deletingLastPathComponent()
            } else {
                panel.directoryURL = currentURL.deletingLastPathComponent()
            }
        }
        if panel.runModal() == .OK, let url = panel.url { path = url.path }
    }

    private var actionLabel: String {
        switch kind {
        case .directory: "Choose folder"
        case .file: "Choose file"
        case .fileOrDirectory: "Choose file or folder"
        case .saveFile: "Choose output file"
        }
    }

    private var actionHelp: String {
        switch (store.usesBundledBackend, kind) {
        case (true, .directory): "Choose a folder on this Mac"
        case (true, .file): "Choose a file on this Mac"
        case (true, .fileOrDirectory): "Choose a file or folder on this Mac"
        case (true, .saveFile): "Choose where to save the .torrent file"
        case (false, .directory): "Browse folders on the qBittorrent server"
        case (false, .file): "Browse files on the qBittorrent server"
        case (false, .fileOrDirectory): "Browse server files and folders"
        case (false, .saveFile): "Choose an output folder on the qBittorrent server"
        }
    }
}

struct ServerPathPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPath: String
    @State private var filename: String
    @State private var directoryPath = ""
    @State private var entries: [ServerDirectoryEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var reloadToken = 0
    @State private var activeLoadID = UUID()

    let store: TorrentStore
    @Binding var path: String
    let kind: ServerPathSelectionKind

    init(store: TorrentStore, path: Binding<String>, kind: ServerPathSelectionKind, initialPath: String) {
        self.store = store
        _path = path
        self.kind = kind
        let startsAtParent = kind == .file || kind == .fileOrDirectory || kind == .saveFile
        _currentPath = State(initialValue: startsAtParent && !initialPath.isEmpty ? Self.parent(of: initialPath) : initialPath)
        let initialName = Self.lastComponent(of: initialPath)
        _filename = State(initialValue: kind == .saveFile && !initialName.isEmpty ? initialName : "new.torrent")
    }

    private var sortedEntries: [ServerDirectoryEntry] {
        entries.sorted { left, right in
            if left.isDirectory != right.isDirectory { return left.isDirectory }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    private var parentPath: String {
        Self.parent(of: currentPath)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button {
                        navigate(to: parentPath)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.glass)
                    .disabled(parentPath == currentPath || isLoading)
                    .help("Go to parent folder")

                    TextField("Server path", text: $currentPath)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { directoryPath = currentPath }
                        .accessibilityLabel("Server path")
                        .accessibilityHint("Enter an absolute path on the qBittorrent server and press Return.")

                    Button {
                        if currentPath == directoryPath {
                            reloadToken += 1
                        } else {
                            directoryPath = currentPath
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.glass)
                    .disabled(isLoading)
                    .help("Refresh folder contents")
                }
                .padding(12)

                if let errorMessage {
                    ContentUnavailableView("Folder Unavailable", systemImage: "folder.badge.questionmark", description: Text(errorMessage))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isLoading {
                    ProgressView("Loading server folder…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if sortedEntries.isEmpty {
                    ContentUnavailableView(
                        "Empty Folder",
                        systemImage: "folder",
                        description: Text(kind.listsFiles ? "This server folder has no files or subfolders." : "This server folder has no subfolders.")
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(sortedEntries) { entry in
                        entryRow(entry)
                    }
                    .listStyle(.inset)
                    .disabled(currentPath != directoryPath)
                }
            }
            .navigationTitle(kind == .file ? "Choose Server File" : kind == .saveFile ? "Save Torrent File" : "Choose Server Folder")
            .safeAreaInset(edge: .bottom) {
                if kind == .saveFile {
                    HStack {
                        TextField("Torrent file name", text: $filename)
                            .textFieldStyle(.roundedBorder)
                        Button("Save Here") {
                            let name = filename.trimmingCharacters(in: .whitespacesAndNewlines)
                            let torrentName = name.lowercased().hasSuffix(".torrent") ? name : name + ".torrent"
                            path = Self.appending(torrentName, to: currentPath)
                            dismiss()
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(!canSaveFile || currentPath != directoryPath || errorMessage != nil)
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding(12)
                    .background(.bar)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                if kind.choosesFolder {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Choose This Folder") {
                            path = currentPath
                            dismiss()
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(currentPath.isEmpty || currentPath != directoryPath || isLoading || errorMessage != nil)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .task {
                if currentPath.isEmpty {
                    currentPath = (try? await store.defaultSavePath()).flatMap { $0.isEmpty ? nil : $0 } ?? "/"
                }
                directoryPath = currentPath
            }
            .task(id: "\(directoryPath)|\(reloadToken)") { await loadDirectory(at: directoryPath) }
        }
        .frame(minWidth: 560, minHeight: 440)
    }

    @ViewBuilder
    private func entryRow(_ entry: ServerDirectoryEntry) -> some View {
        if entry.isDirectory {
            HStack(spacing: 8) {
                Button {
                    navigate(to: Self.appending(entry.name, to: currentPath))
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.tint)
                        Text(entry.name)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if kind.choosesFolder {
                    Button("Choose") {
                        path = Self.appending(entry.name, to: currentPath)
                        dismiss()
                    }
                    .buttonStyle(.glass)
                }
            }
        } else if kind.listsFiles {
            Button {
                path = Self.appending(entry.name, to: currentPath)
                dismiss()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "doc")
                        .foregroundStyle(.secondary)
                    Text(entry.name)
                        .lineLimit(1)
                    Spacer()
                    if let size = entry.size {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func navigate(to path: String) {
        currentPath = path
        directoryPath = path
    }

    private func loadDirectory(at path: String) async {
        guard !path.isEmpty else { return }
        let loadID = UUID()
        activeLoadID = loadID
        isLoading = true
        errorMessage = nil
        defer { if activeLoadID == loadID { isLoading = false } }
        do {
            let result = try await store.serverDirectoryContent(path: path, mode: kind.listsFiles ? "all" : "dirs")
            guard activeLoadID == loadID, directoryPath == path else { return }
            entries = result
        } catch {
            guard activeLoadID == loadID, directoryPath == path else { return }
            entries = []
            errorMessage = error.localizedDescription
        }
    }

    private static func appending(_ component: String, to path: String) -> String {
        let separator = path.contains("\\") && !path.contains("/") ? "\\" : "/"
        if path.hasSuffix("/") || path.hasSuffix("\\") { return path + component }
        return path + separator + component
    }

    private var canSaveFile: Bool {
        let name = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        return !currentPath.isEmpty && !name.isEmpty && !name.contains("/") && !name.contains("\\")
    }

    private static func lastComponent(of path: String) -> String {
        path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
    }

    private static func parent(of path: String) -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let root: String
        if normalized.hasPrefix("//") {
            let components = normalized.dropFirst(2).split(separator: "/")
            root = components.count >= 2 ? "//\(components[0])/\(components[1])" : path
        } else if normalized.count >= 3, normalized[normalized.index(after: normalized.startIndex)] == ":" {
            root = String(normalized.prefix(3))
        } else {
            root = "/"
        }

        let trimmed = path.replacingOccurrences(of: #"[/\\]+$"#, with: "", options: .regularExpression)
        if trimmed.isEmpty { return root }
        if trimmed == root || normalized == root { return path }
        guard let separator = trimmed.lastIndex(where: { $0 == "/" || $0 == "\\" }) else { return path }
        let parent = String(trimmed[..<separator])
        if parent.isEmpty { return String(trimmed[...separator]) }
        if parent.count == 2, parent.last == ":" { return parent + String(trimmed[separator]) }
        if normalized.hasPrefix("//"), parent == "//" { return path }
        if normalized.hasPrefix("//") {
            let normalizedParent = parent.replacingOccurrences(of: "\\", with: "/")
            let rootNormalized = root.replacingOccurrences(of: "\\", with: "/")
            if normalizedParent.count < rootNormalized.count { return path }
        }
        return parent
    }
}
