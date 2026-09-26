import SwiftUI

struct SearchPluginsView: View {
    @Environment(\.dismiss) private var dismiss
    let store: TorrentStore
    @State private var plugins: [SearchPlugin] = []
    @State private var sourceURL = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Search Plugins").font(.title2.weight(.semibold))
                Spacer()
                Button("Update All") { run { try await store.updateSearchPlugins() } }
                    .disabled(isWorking)
            }
            List(plugins) { plugin in
                HStack {
                    VStack(alignment: .leading) {
                        Text(plugin.fullName ?? plugin.name)
                        Text("\(plugin.name) · \(plugin.version ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Enabled", isOn: Binding(
                        get: { plugin.enabled ?? false },
                        set: { value in run { try await store.enableSearchPlugin(plugin.name, enabled: value) } }
                    ))
                    .labelsHidden()
                    Button("Remove", role: .destructive) { run { try await store.uninstallSearchPlugin(plugin.name) } }
                }
            }
            .frame(minHeight: 180)
            HStack {
                TextField("Plugin URL", text: $sourceURL).textFieldStyle(.roundedBorder)
                Button("Install") {
                    let source = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    run { try await store.installSearchPlugin(source) }
                    sourceURL = ""
                }
                .buttonStyle(.glassProminent)
                .disabled(isWorking || URL(string: sourceURL)?.scheme?.hasPrefix("http") != true)
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 570)
        .task { await reload() }
    }

    private func reload() async {
        do { plugins = try await store.searchPlugins(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        isWorking = true
        Task {
            do {
                try await action()
                await reload()
            } catch { errorMessage = error.localizedDescription }
            isWorking = false
        }
    }
}
