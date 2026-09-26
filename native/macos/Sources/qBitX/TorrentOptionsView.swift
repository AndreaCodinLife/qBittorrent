import SwiftUI

struct TorrentOptionsTarget: Identifiable {
    let id = UUID()
    let hashes: [String]
}

struct TorrentOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    let store: TorrentStore
    let hashes: [String]
    @State private var downloadLimit = "0"
    @State private var uploadLimit = "0"
    @State private var ratioLimit = "-2"
    @State private var seedingMinutes = "-2"
    @State private var inactiveMinutes = "-2"
    @State private var action = "Default"
    @State private var mode = "Default"
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(hashes.count == 1 ? "Torrent Options" : "Torrent Options (\(hashes.count) selected)")
                .font(.title2.weight(.semibold))
            Form {
                Section("Transfer limits") {
                    TextField("Download limit (KiB/s; 0 = unlimited)", text: $downloadLimit)
                    TextField("Upload limit (KiB/s; 0 = unlimited)", text: $uploadLimit)
                }
                Section("Share limits") {
                    TextField("Ratio (-2 = default, -1 = unlimited)", text: $ratioLimit)
                    TextField("Seeding time in minutes (-2 = default, -1 = unlimited)", text: $seedingMinutes)
                    TextField("Inactive seeding in minutes (-2 = default, -1 = unlimited)", text: $inactiveMinutes)
                    Picker("When a limit is reached", selection: $action) {
                        Text("Default").tag("Default")
                        Text("Stop torrent").tag("Stop")
                        Text("Remove torrent").tag("Remove")
                        Text("Remove torrent and data").tag("RemoveWithContent")
                        Text("Enable super seeding").tag("EnableSuperSeeding")
                    }
                    Picker("Limit behavior", selection: $mode) {
                        Text("Default").tag("Default")
                        Text("Match any limit").tag("MatchAny")
                        Text("Match all limits").tag("MatchAll")
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: 390)
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") { save() }.buttonStyle(.glassProminent)
                    .disabled(!valid || isSaving).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
    }

    private var valid: Bool {
        guard let down = Int64(downloadLimit), let up = Int64(uploadLimit),
              let ratio = Double(ratioLimit), let seed = Int(seedingMinutes), let inactive = Int(inactiveMinutes) else { return false }
        let validMinutes: (Int) -> Bool = { $0 == -2 || $0 == -1 || (0...2_147_483_647).contains($0) }
        return (0...1_000_000).contains(down) && (0...1_000_000).contains(up)
            && ratio.isFinite && ratio >= -2 && ratio <= 100_000
            && validMinutes(seed) && validMinutes(inactive)
    }

    private func save() {
        guard let down = Int64(downloadLimit), let up = Int64(uploadLimit), let ratio = Double(ratioLimit),
              let seed = Int(seedingMinutes), let inactive = Int(inactiveMinutes) else { return }
        isSaving = true
        Task {
            do {
                try await store.setTorrentLimits(hashes: hashes, downloadKiB: down, uploadKiB: up, ratio: ratio, seedingMinutes: seed, inactiveMinutes: inactive, action: action, mode: mode)
                dismiss()
            } catch { errorMessage = error.localizedDescription; isSaving = false }
        }
    }
}
