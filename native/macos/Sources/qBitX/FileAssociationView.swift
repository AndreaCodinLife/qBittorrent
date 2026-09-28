import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileAssociationView: View {
    @State private var torrentIsDefault = false
    @State private var magnetIsDefault = false
    @State private var statusMessage: String?
    @State private var isUpdating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Open torrent files and magnet links with qBitX")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(".torrent files", systemImage: "doc.zipper")
                    Spacer()
                    Button(torrentIsDefault ? "Default App" : "Set as Default…") {
                        Task { await setTorrentDefault() }
                    }
                    .disabled(torrentIsDefault || isUpdating)
                }
                HStack {
                    Label("magnet links", systemImage: "link")
                    Spacer()
                    Button(magnetIsDefault ? "Default App" : "Set as Default…") {
                        Task { await setMagnetDefault() }
                    }
                    .disabled(magnetIsDefault || isUpdating)
                }
            }

            Text("macOS may ask you to confirm a default app change.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 480)
        .task { refreshDefaults() }
    }

    private func refreshDefaults() {
        let workspace = NSWorkspace.shared
        if let torrentType = UTType("org.bittorrent.torrent"),
           let defaultApp = workspace.urlForApplication(toOpen: torrentType) {
            torrentIsDefault = isQBitX(defaultApp)
        }
        if let magnetURL = URL(string: "magnet:?xt=urn:btih:0000000000000000000000000000000000000000"),
           let defaultApp = workspace.urlForApplication(toOpen: magnetURL) {
            magnetIsDefault = isQBitX(defaultApp)
        }
    }

    private func isQBitX(_ applicationURL: URL) -> Bool {
        applicationURL.resolvingSymlinksInPath().standardizedFileURL
            == Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
    }

    private func setTorrentDefault() async {
        guard let torrentType = UTType("org.bittorrent.torrent") else {
            statusMessage = "macOS does not recognize the BitTorrent file type. Rebuild qBitX to register it."
            return
        }
        isUpdating = true
        defer { isUpdating = false }
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: torrentType)
            refreshDefaults()
            statusMessage = torrentIsDefault ? nil : "macOS kept the current default app."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func setMagnetDefault() async {
        isUpdating = true
        defer { isUpdating = false }
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "magnet")
            refreshDefaults()
            statusMessage = magnetIsDefault ? nil : "macOS kept the current default app."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
