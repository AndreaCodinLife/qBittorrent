import SwiftUI

struct QBitXCommandActions {
    var addTorrentFile: () -> Void
    var addTorrentURL: () -> Void
    var createTorrent: () -> Void
    var removeSelected: () -> Void
    var startSelected: () -> Void
    var stopSelected: () -> Void
    var forceStartSelected: () -> Void
    var recheckSelected: () -> Void
    var moveSelectedToTop: () -> Void
    var moveSelectedUp: () -> Void
    var moveSelectedDown: () -> Void
    var moveSelectedToBottom: () -> Void
    var pauseSession: () -> Void
    var resumeSession: () -> Void
    var showPreferences: () -> Void
    var showStatistics: () -> Void
    var showSpeedLimits: () -> Void
    var focusTorrentFilter: () -> Void
    var selectTransfers: () -> Void
    var selectSearch: () -> Void
    var selectRSS: () -> Void
    var showExecutionLog: () -> Void
}

private struct QBitXCommandActionsKey: FocusedValueKey {
    typealias Value = QBitXCommandActions
}

extension FocusedValues {
    var qBitXCommandActions: QBitXCommandActions? {
        get { self[QBitXCommandActionsKey.self] }
        set { self[QBitXCommandActionsKey.self] = newValue }
    }
}

struct QBitXCommands: Commands {
    @FocusedValue(\.qBitXCommandActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Torrent File…", action: action(\.addTorrentFile))
                .keyboardShortcut("o", modifiers: .command)
            Button("Add Magnet Link or URL…", action: action(\.addTorrentURL))
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Create Torrent…", action: action(\.createTorrent))
                .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("Transfers") {
            Button("Start Selected") { actions?.startSelected() }
                .keyboardShortcut("s", modifiers: .command)
            Button("Stop Selected") { actions?.stopSelected() }
                .keyboardShortcut("p", modifiers: .command)
            Button("Force Start Selected") { actions?.forceStartSelected() }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Button("Force Recheck Selected") { actions?.recheckSelected() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Remove Selected…") { actions?.removeSelected() }
                .keyboardShortcut(.delete)
            Divider()
            Button("Move to Top of Queue") { actions?.moveSelectedToTop() }
                .keyboardShortcut("+", modifiers: [.command, .shift])
            Button("Move Up in Queue") { actions?.moveSelectedUp() }
                .keyboardShortcut("+", modifiers: .command)
            Button("Move Down in Queue") { actions?.moveSelectedDown() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Move to Bottom of Queue") { actions?.moveSelectedToBottom() }
                .keyboardShortcut("-", modifiers: [.command, .shift])
            Divider()
            Button("Pause Session") { actions?.pauseSession() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Resume Session") { actions?.resumeSession() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        CommandMenu("Navigate") {
            Button("Transfers") { actions?.selectTransfers() }
                .keyboardShortcut("1", modifiers: .command)
            Button("Search") { actions?.selectSearch() }
                .keyboardShortcut("2", modifiers: .command)
            Button("RSS") { actions?.selectRSS() }
                .keyboardShortcut("3", modifiers: .command)
            Button("Execution Log") { actions?.showExecutionLog() }
                .keyboardShortcut("4", modifiers: .command)
            Button("Filter Transfers…") { actions?.focusTorrentFilter() }
                .keyboardShortcut("f", modifiers: .command)
        }

        CommandGroup(after: .appSettings) {
            Button("qBittorrent Preferences…") { actions?.showPreferences() }
                .keyboardShortcut("o", modifiers: .option)
            Button("Speed Limits…") { actions?.showSpeedLimits() }
            Button("Statistics…") { actions?.showStatistics() }
        }
    }

    private func action(_ keyPath: KeyPath<QBitXCommandActions, () -> Void>) -> () -> Void {
        { actions?[keyPath: keyPath]() }
    }
}
