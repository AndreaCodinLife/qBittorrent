import SwiftUI

enum TorrentDoubleClickAction: String, CaseIterable, Identifiable {
    case toggleStop
    case openDestination
    case previewFile
    case openOptions
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleStop: "Start / Stop Torrent"
        case .openDestination: "Open Destination Folder"
        case .previewFile: "Preview File, Otherwise Open Destination Folder"
        case .openOptions: "Open Torrent Options"
        case .none: "No Action"
        }
    }
}

struct AppPreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("qBitX.doubleClick.downloading") private var downloadingAction = TorrentDoubleClickAction.toggleStop.rawValue
    @AppStorage("qBitX.doubleClick.completed") private var completedAction = TorrentDoubleClickAction.openDestination.rawValue
    @AppStorage("qBitX.dragContentFiles") private var dragContentFiles = false
    @AppStorage("qBitX.confirmOnExit") private var confirmOnExit = true
    @AppStorage("qBitX.confirmAutoCompletionAction") private var confirmAutoCompletionAction = true
    @AppStorage("qBitX.systemNotificationsEnabled") private var systemNotificationsEnabled = true
    @AppStorage("qBitX.notifyTorrentAdded") private var notifyOnTorrentAdded = false
    @AppStorage("qBitX.notifyDownloadComplete") private var notifyOnDownloadComplete = true
    @AppStorage("qBitX.notifyTorrentError") private var notifyOnTorrentError = true
    @AppStorage("qBitX.notifySearchComplete") private var notifyOnSearchComplete = true
    @AppStorage("qBitX.startMinimized") private var startMinimized = false
    @AppStorage("qBitX.confirmTorrentDeletion") private var confirmTorrentDeletion = true
    @AppStorage("qBitX.confirmRemoveAllTags") private var confirmRemoveAllTags = true
    @AppStorage("qBitX.confirmRemoveTrackerFromAllTorrents") private var confirmRemoveTrackerFromAllTorrents = true
    @AppStorage("qBitX.recursiveDownloadEnabled") private var recursiveDownloadEnabled = true
    @AppStorage("qBitX.hideZeroValues") private var hideZeroValues = false
    @AppStorage("qBitX.hideZeroValuesMode") private var hideZeroValuesMode = "always"
    @AppStorage("qBitX.alternatingTransferRows") private var alternatingTransferRows = true
    @AppStorage("qBitX.colorTransfersByState") private var colorTransfersByState = true
    @AppStorage("qBitX.progressBarFollowsStateColor") private var progressBarFollowsStateColor = false
    @AppStorage("qBitX.showFreeDiskSpace") private var showFreeDiskSpace = false
    @AppStorage("qBitX.showExternalIP") private var showExternalIP = false
    @AppStorage("qBitX.showTorrentAdditionDialog") private var showTorrentAdditionDialog = true

    let store: TorrentStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Transfer List") {
                    Picker("Double-click a downloading torrent", selection: $downloadingAction) {
                        ForEach(TorrentDoubleClickAction.allCases) { action in
                            Text(action.title).tag(action.rawValue)
                        }
                    }
                    Picker("Double-click a completed torrent", selection: $completedAction) {
                        ForEach(TorrentDoubleClickAction.allCases) { action in
                            Text(action.title).tag(action.rawValue)
                        }
                    }
                    Toggle("Hide zero and infinity values", isOn: $hideZeroValues)
                    if hideZeroValues {
                        Picker("Apply to", selection: $hideZeroValuesMode) {
                            Text("All torrents").tag("always")
                            Text("Stopped downloads only").tag("stopped")
                        }
                    }
                    Toggle("Confirm before removing torrents", isOn: $confirmTorrentDeletion)
                    Toggle("Confirm before removing all tags", isOn: $confirmRemoveAllTags)
                    Toggle("Confirm before removing a tracker from all torrents", isOn: $confirmRemoveTrackerFromAllTorrents)
                    Toggle("Use alternating row colors", isOn: $alternatingTransferRows)
                    Toggle("Use different text colors by torrent state", isOn: $colorTransfersByState)
                    Toggle("Make progress bars follow state colors", isOn: $progressBarFollowsStateColor)
                        .disabled(!colorTransfersByState)
                }

                Section("When Adding Torrents") {
                    Toggle("Show torrent addition options", isOn: $showTorrentAdditionDialog)
                    Text("When off, new torrents use the connected qBittorrent server’s default add settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Torrent Content") {
                    Toggle("Drag downloaded files from the Content tab", isOn: $dragContentFiles)
                        .disabled(!store.usesBundledBackend)
                    if !store.usesBundledBackend {
                        Text("Files belong to the remote server and cannot be dragged into Mac apps.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Completed Downloads") {
                    Toggle("Ask before adding .torrent files found inside completed downloads", isOn: $recursiveDownloadEnabled)
                        .disabled(!store.usesBundledBackend)
                    if store.usesBundledBackend {
                        Text("When a download finishes, qBitX checks its files and offers to add any .torrent files to the same folder.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Remote server files are not available for local inspection.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notifications") {
                    Toggle("Enable macOS notifications", isOn: $systemNotificationsEnabled)
                    Toggle("When a torrent is added", isOn: $notifyOnTorrentAdded)
                        .disabled(!systemNotificationsEnabled)
                    Toggle("When a download finishes", isOn: $notifyOnDownloadComplete)
                        .disabled(!systemNotificationsEnabled)
                    Toggle("When a torrent has an error", isOn: $notifyOnTorrentError)
                        .disabled(!systemNotificationsEnabled)
                    Toggle("When a background search finishes", isOn: $notifyOnSearchComplete)
                        .disabled(!systemNotificationsEnabled)
                    Text("macOS asks for notification permission when qBitX first sends a notification.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Status Bar") {
                    Toggle("Show free disk space", isOn: $showFreeDiskSpace)
                    Toggle("Show external IP addresses", isOn: $showExternalIP)
                }

                Section("When Quitting") {
                    Toggle("Confirm when torrents are transferring", isOn: $confirmOnExit)
                    Toggle("Confirm automatic action when downloads finish", isOn: $confirmAutoCompletionAction)
                }

                Section("When Starting") {
                    Toggle("Start minimized", isOn: $startMinimized)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("qBitX Preferences")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 650, minHeight: 430)
        .onChange(of: systemNotificationsEnabled) { _, enabled in
            guard enabled else { return }
            Task { _ = await MacOSNotifications.requestAuthorization() }
        }
    }
}
