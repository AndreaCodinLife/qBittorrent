import SwiftUI

struct SpeedLimitsView: View {
    @Environment(\.dismiss) private var dismiss
    let store: TorrentStore
    @State private var normalDown = "0"
    @State private var normalUp = "0"
    @State private var alternateDown = "0"
    @State private var alternateUp = "0"
    @State private var usesAlternate = false
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Speed Limits").font(.title2.weight(.semibold))
            Text("Enter 0 for unlimited. Limits are in KiB/s.")
                .font(.subheadline).foregroundStyle(.secondary)
            Form {
                Section("Normal") {
                    TextField("Download", text: $normalDown)
                    TextField("Upload", text: $normalUp)
                }
                Section("Alternative") {
                    TextField("Download", text: $alternateDown)
                    TextField("Upload", text: $alternateUp)
                    Toggle("Use alternative limits", isOn: $usesAlternate)
                }
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") { save() }
                    .buttonStyle(.glassProminent)
                    .disabled(isSaving || parsedLimits == nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .task {
            do {
                let (limits, mode) = try await store.speedLimits()
                normalDown = "\(limits.dl_limit / 1024)"
                normalUp = "\(limits.up_limit / 1024)"
                alternateDown = "\(limits.alt_dl_limit / 1024)"
                alternateUp = "\(limits.alt_up_limit / 1024)"
                usesAlternate = mode
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private var parsedLimits: SpeedLimits? {
        guard let down = Int64(normalDown), let up = Int64(normalUp),
              let altDown = Int64(alternateDown), let altUp = Int64(alternateUp),
              [down, up, altDown, altUp].allSatisfy({ $0 >= 0 && $0 <= 1_000_000 }) else { return nil }
        return SpeedLimits(dl_limit: down * 1024, up_limit: up * 1024, alt_dl_limit: altDown * 1024, alt_up_limit: altUp * 1024)
    }

    private func save() {
        guard let parsedLimits else { return }
        isSaving = true
        Task {
            do {
                try await store.setSpeedLimits(parsedLimits, alternativeMode: usesAlternate)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}
