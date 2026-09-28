import SwiftUI

struct ContentLayoutEditorTarget: Identifiable {
    let id = UUID()
    let hash: String
    let torrentName: String
    let initialFileIDs: Set<Int>?
}

struct TorrentContentLayoutEditor: View {
    @Environment(\.dismiss) private var dismiss
    let store: TorrentStore
    let hash: String
    let torrentName: String
    let initialFileIDs: Set<Int>?

    @State private var files: [TorrentFile] = []
    @State private var selectedFileIDs: Set<Int> = []
    @State private var editedPaths: [Int: String] = [:]
    @State private var appliedPaths: [Int: String] = [:]
    @State private var commonPath = ""
    @State private var isLoading = true
    @State private var isApplying = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    private var hasChanges: Bool {
        files.contains { file in
            editedPaths[file.index].map { $0 != basePath(for: file) } ?? false
        }
    }

    private var hasInvalidPaths: Bool {
        files.contains { file in
            guard let path = editedPaths[file.index], path != basePath(for: file) else { return false }
            return !isValidRelativePath(path)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(torrentName)
                .font(.headline)
                .lineLimit(1)

            if isLoading {
                ProgressView("Loading torrent content…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if files.isEmpty {
                ContentUnavailableView(
                    "No File List",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Content paths are available after the torrent metadata has loaded.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(files, selection: $selectedFileIDs) {
                    TableColumn("Index") { file in
                        Text("\(file.index)")
                            .monospacedDigit()
                    }
                    .width(min: 64, ideal: 72, max: 90)

                    TableColumn("Path") { file in
                        TextField("Path", text: pathBinding(for: file))
                            .textFieldStyle(.plain)
                            .lineLimit(1)
                            .accessibilityLabel("Path for file \(file.index + 1)")
                    }
                }
                .alternatingRowBackgrounds(.enabled)
                .onChange(of: selectedFileIDs) { _, _ in refreshCommonPath() }

                HStack(spacing: 10) {
                    Text("Common path:")
                        .foregroundStyle(selectedFileIDs.isEmpty ? .tertiary : .secondary)
                    TextField("Select one or more files", text: commonPathBinding)
                        .textFieldStyle(.roundedBorder)
                        .disabled(selectedFileIDs.isEmpty || isApplying)
                        .accessibilityHint("Changes the common path for the selected files while preserving their remaining path components.")
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") { Task { await applyChanges() } }
                    .buttonStyle(.glassProminent)
                    .disabled(isLoading || isApplying || !hasChanges || hasInvalidPaths)
            }
        }
        .padding(20)
        .frame(minWidth: 620, idealWidth: 760, minHeight: 440, idealHeight: 560)
        .task { await loadFiles() }
    }

    private var commonPathBinding: Binding<String> {
        Binding(
            get: { commonPath },
            set: { updateSelectedCommonPath(to: $0) }
        )
    }

    private func pathBinding(for file: TorrentFile) -> Binding<String> {
        Binding(
            get: { displayedPath(for: file) },
            set: { updatePath($0, for: file) }
        )
    }

    private func displayedPath(for file: TorrentFile) -> String {
        editedPaths[file.index] ?? appliedPaths[file.index] ?? file.name
    }

    private func basePath(for file: TorrentFile) -> String {
        appliedPaths[file.index] ?? file.name
    }

    private func updatePath(_ path: String, for file: TorrentFile) {
        let path = cleanPath(path)
        if path == basePath(for: file) {
            editedPaths.removeValue(forKey: file.index)
        } else {
            editedPaths[file.index] = path
        }
        errorMessage = nil
        statusMessage = nil
    }

    private func updateSelectedCommonPath(to newPath: String) {
        let oldPath = commonPath
        let newPath = cleanPath(newPath)
        guard oldPath != newPath else { return }

        for file in files where selectedFileIDs.contains(file.index) {
            let currentPath = displayedPath(for: file)
            let relativePath = relativeSuffix(of: currentPath, after: oldPath)
            updatePath(joinedPath(newPath, relativePath), for: file)
        }
        commonPath = newPath
    }

    private func refreshCommonPath() {
        let selectedPaths = files
            .filter { selectedFileIDs.contains($0.index) }
            .map(displayedPath(for:))
        commonPath = commonPrefix(of: selectedPaths)
    }

    private func commonPrefix(of paths: [String]) -> String {
        guard let first = paths.first else { return "" }
        var commonComponents = first.split(separator: "/", omittingEmptySubsequences: false).map(String.init)

        for path in paths.dropFirst() {
            let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            var matchCount = 0
            while matchCount < commonComponents.count,
                  matchCount < components.count,
                  commonComponents[matchCount] == components[matchCount] {
                matchCount += 1
            }
            commonComponents = Array(commonComponents.prefix(matchCount))
            if commonComponents.isEmpty { break }
        }

        return commonComponents.joined(separator: "/")
    }

    private func relativeSuffix(of path: String, after prefix: String) -> String {
        guard !prefix.isEmpty else { return path }
        let prefixComponents = prefix.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let pathComponents = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        var sharedCount = 0
        while sharedCount < prefixComponents.count,
              sharedCount < pathComponents.count,
              prefixComponents[sharedCount] == pathComponents[sharedCount] {
            sharedCount += 1
        }
        let parentComponents = Array(repeating: "..", count: prefixComponents.count - sharedCount)
        let childComponents = pathComponents.dropFirst(sharedCount)
        let relativeComponents = parentComponents + childComponents
        return relativeComponents.isEmpty ? "." : relativeComponents.joined(separator: "/")
    }

    private func joinedPath(_ prefix: String, _ suffix: String) -> String {
        if suffix.isEmpty || suffix == "." { return cleanPath(prefix) }
        if prefix.isEmpty { return cleanPath(suffix) }
        return cleanPath("\(prefix)/\(suffix)")
    }

    private func cleanPath(_ path: String) -> String {
        let isAbsolute = path.hasPrefix("/")
        var components: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            if component == "." { continue }
            if component == ".." {
                if let last = components.last, last != ".." {
                    components.removeLast()
                } else if !isAbsolute {
                    components.append(component)
                }
                continue
            }
            components.append(component)
        }

        let normalized = components.joined(separator: "/")
        if isAbsolute { return normalized.isEmpty ? "/" : "/\(normalized)" }
        return normalized
    }

    private func isValidRelativePath(_ path: String) -> Bool {
        !path.isEmpty
            && !path.hasPrefix("/")
            && !path.hasPrefix("\\\\")
            && path.range(of: "^[A-Za-z]:/", options: .regularExpression) == nil
            && !path.contains("\0")
    }

    private func loadFiles() async {
        do {
            files = try await store.files(for: hash).sorted { $0.index < $1.index }
            let initialSelection = Set(files.map(\.index)).intersection(initialFileIDs ?? [])
            if !initialSelection.isEmpty {
                selectedFileIDs = initialSelection
                refreshCommonPath()
            } else if let first = files.first {
                selectedFileIDs = [first.index]
                refreshCommonPath()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func applyChanges() async {
        let changes = files.compactMap { file -> (TorrentFile, String)? in
            guard let newPath = editedPaths[file.index], newPath != basePath(for: file) else { return nil }
            return (file, newPath)
        }
        guard !changes.isEmpty else { return }

        isApplying = true
        errorMessage = nil
        statusMessage = nil
        var failures: [String] = []
        var succeeded: [(Int, String)] = []

        for (file, newPath) in changes {
            let oldPath = basePath(for: file)
            do {
                try await store.renameFile(hash: hash, oldPath: oldPath, newPath: newPath)
                succeeded.append((file.index, newPath))
            } catch {
                failures.append("\(file.name): \(error.localizedDescription)")
            }
        }

        for (index, path) in succeeded {
            appliedPaths[index] = path
            editedPaths.removeValue(forKey: index)
        }

        if let refreshedFiles = try? await store.files(for: hash) {
            files = refreshedFiles.sorted { $0.index < $1.index }
            for file in files where appliedPaths[file.index] == file.name {
                appliedPaths.removeValue(forKey: file.index)
            }
        }
        refreshCommonPath()

        if failures.isEmpty {
            statusMessage = "Applied path changes to \(succeeded.count) file\(succeeded.count == 1 ? "" : "s")."
        } else {
            errorMessage = "Some paths could not be changed:\n\(failures.joined(separator: "\n"))"
        }
        isApplying = false
    }
}
