import SwiftUI

struct ConnectionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let store: TorrentStore
    let onRestart: () -> Void

    @State private var useExisting = SavedRemoteConnection.load() != nil
    @State private var address = SavedRemoteConnection.load()?.address ?? "http://127.0.0.1:8080"
    @State private var username = SavedRemoteConnection.load()?.username ?? "admin"
    @State private var authenticationMode = SavedRemoteConnection.load()?.authenticationMode ?? .apiKey
    @State private var secret = ""
    @State private var isApplying = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Connection")
                .font(.title2.weight(.semibold))

            Picker("Library", selection: $useExisting) {
                Text("qBitX Library").tag(false)
                Text("Existing qBittorrent").tag(true)
            }
            .pickerStyle(.segmented)

            if useExisting {
                Text("Enable Web UI in qBittorrent’s Tools → Options → Web UI settings, then enter its address and credentials here. Your existing torrents stay in that app’s profile.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if store.isConnected && store.requiresNewerWebAPIForFullParity {
                    Label("The current server exposes Web API \(store.serverAPIVersion). Full qBitX feature parity requires 2.16.2 or later; some newer RSS and category settings may be unavailable.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                TextField("Web UI address", text: $address)
                    .textFieldStyle(.roundedBorder)

                Picker("Sign in with", selection: $authenticationMode) {
                    ForEach(RemoteAuthenticationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                if authenticationMode == .password {
                    TextField("Username", text: $username)
                        .textFieldStyle(.roundedBorder)
                }

                SecureField(authenticationMode == .apiKey ? "API key" : "Password", text: $secret)
                    .textFieldStyle(.roundedBorder)
                if SavedRemoteConnection.secret() != nil {
                    Text("Leave the credential blank to keep the saved value.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("qBitX runs its own qBittorrent backend and stores torrents in a separate library. It does not alter your existing qBittorrent profile.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(useExisting ? "Connect" : "Use qBitX Library") {
                    isApplying = true
                    Task {
                        do {
                            if useExisting {
                                let settings = SavedRemoteConnection(
                                    address: address,
                                    username: username,
                                    authenticationMode: authenticationMode
                                )
                                try await store.configureRemote(settings, secret: secret)
                            } else {
                                store.useBundledBackend()
                            }
                            onRestart()
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                            isApplying = false
                        }
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(isApplying)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(25)
        .frame(width: 500)
    }
}
