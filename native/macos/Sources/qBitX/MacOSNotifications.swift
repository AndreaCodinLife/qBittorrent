import UserNotifications

final class QBitXNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == MacOSNotifications.toggleTorrentAction,
              let hash = response.notification.request.content.userInfo[MacOSNotifications.torrentHashKey] as? String else { return }
        await Self.toggleTorrent(hash)
    }

    @MainActor
    private static func toggleTorrent(_ hash: String) async {
        guard let store = QBitXApplicationDelegate.store,
              store.isConnected,
              let torrent = store.torrents.first(where: { $0.id == hash }) else { return }

        do {
            if torrent.state == .paused {
                try await store.start(hash)
            } else {
                try await store.command(.stop, hashes: [hash])
            }
        } catch {
            NSLog("qBitX couldn't change torrent state from a notification: %@", error.localizedDescription)
        }
    }
}

@MainActor
enum MacOSNotifications {
    nonisolated static let toggleTorrentAction = "QBITX_TOGGLE_TORRENT"
    nonisolated static let torrentHashKey = "qBitX.torrentHash"
    private static let torrentCategory = "QBITX_TORRENT"

    static func setDelegate(_ delegate: UNUserNotificationCenterDelegate) {
        let center = UNUserNotificationCenter.current()
        let toggleAction = UNNotificationAction(
            identifier: toggleTorrentAction,
            title: "Pause / Resume",
            options: []
        )
        let openAction = UNNotificationAction(
            identifier: "QBITX_OPEN_APP",
            title: "Open qBitX",
            options: [.foreground]
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: torrentCategory,
                actions: [toggleAction, openAction],
                intentIdentifiers: [],
                options: []
            )
        ])
        center.delegate = delegate
    }

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    static func post(title: String, body: String, torrentHash: String? = nil) {
        Task {
            guard await requestAuthorization() else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            if let torrentHash {
                content.categoryIdentifier = torrentCategory
                content.threadIdentifier = torrentHash
                content.userInfo[torrentHashKey] = torrentHash
            }
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}
