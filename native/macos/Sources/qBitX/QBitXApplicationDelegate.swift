import AppKit
import UserNotifications

@MainActor
final class QBitXApplicationDelegate: NSObject, NSApplicationDelegate {
    static weak var store: TorrentStore?
    private let notificationDelegate = QBitXNotificationDelegate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MacOSNotifications.setDelegate(notificationDelegate)
        Self.store?.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let shouldConfirm = UserDefaults.standard.object(forKey: "qBitX.confirmOnExit") as? Bool ?? true
        let hasActiveTransfers = Self.store?.torrents.contains { torrent in
            torrent.downloadRateBytes > 0 || torrent.uploadRateBytes > 0
        } ?? false
        guard shouldConfirm, hasActiveTransfers else { return .terminateNow }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Quit qBitX?"
        alert.informativeText = "Some files are currently transferring. Are you sure you want to quit qBitX?"
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit")
        alert.showsSuppressionButton = true

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            if alert.suppressionButton?.state == .on {
                UserDefaults.standard.set(false, forKey: "qBitX.confirmOnExit")
            }
            return .terminateNow
        }
        return .terminateCancel
    }
}
