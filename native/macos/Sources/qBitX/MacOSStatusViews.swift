import AppKit
import SwiftUI

struct MenuBarSpeedView: View {
    let store: TorrentStore
    @Environment(\.openWindow) private var openWindow
    @State private var controlError: String?

    var body: some View {
        Text("Transfers")
            .font(.headline)
        Label("↓ \(store.transferStatus.downloadText)", systemImage: "arrow.down.circle")
        Label("↑ \(store.transferStatus.uploadText)", systemImage: "arrow.up.circle")
        Label("\(downloadingCount) downloading · \(seedingCount) seeding", systemImage: "arrow.down.arrow.up")

        Divider()

        Button("Pause All Transfers") {
            setSessionPaused(true)
        }
        .disabled(!store.isConnected)

        Button("Resume All Transfers") {
            setSessionPaused(false)
        }
        .disabled(!store.isConnected)

        if let controlError {
            Text(controlError)
                .foregroundStyle(.secondary)
        }

        Divider()

        Button("Open qBitX") {
            openWindow(id: "main")
        }
    }

    private var downloadingCount: Int {
        store.torrents.filter { $0.state == .downloading }.count
    }

    private var seedingCount: Int {
        store.torrents.filter { $0.state == .seeding }.count
    }

    private func setSessionPaused(_ paused: Bool) {
        controlError = nil
        Task {
            do {
                try await store.setSessionPaused(paused)
            } catch {
                controlError = error.localizedDescription
            }
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
