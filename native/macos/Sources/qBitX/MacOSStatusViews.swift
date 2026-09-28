import AppKit
import SwiftUI

struct MenuBarSpeedView: View {
    let store: TorrentStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("↓ \(store.transferStatus.downloadText)   ↑ \(store.transferStatus.uploadText)")
            .accessibilityLabel("Download \(store.transferStatus.downloadText), upload \(store.transferStatus.uploadText)")

        Divider()

        Button("Open qBitX") {
            openWindow(id: "main")
        }
    }
}

@MainActor
enum MacOSStatusPresentation {
    private static let showSpeedInDockKey = "qBitX.showSpeedInDock"

    static func updateDockSpeed(_ status: TransferStatus, enabled: Bool? = nil) {
        let shouldShow = enabled ?? UserDefaults.standard.bool(forKey: showSpeedInDockKey)
        let label: String?

        if shouldShow {
            let rates = [
                status.payloadDownloadRate > 0 ? "↓\(compactRate(status.payloadDownloadRate))" : nil,
                status.payloadUploadRate > 0 ? "↑\(compactRate(status.payloadUploadRate))" : nil
            ].compactMap { $0 }
            label = rates.isEmpty ? nil : rates.joined(separator: " ")
        } else {
            label = nil
        }

        guard NSApp.dockTile.badgeLabel != label else { return }
        NSApp.dockTile.badgeLabel = label
        NSApp.dockTile.display()
    }

    private static func compactRate(_ bytesPerSecond: Int64) -> String {
        let units = ["B", "K", "M", "G", "T"]
        var value = Double(bytesPerSecond)
        var unitIndex = 0
        while value >= 1_000, unitIndex < units.count - 1 {
            value /= 1_000
            unitIndex += 1
        }
        let precision = value >= 10 || unitIndex == 0 ? 0 : 1
        let formatted = value.formatted(.number.precision(.fractionLength(precision)))
        return "\(formatted)\(units[unitIndex])"
    }
}
