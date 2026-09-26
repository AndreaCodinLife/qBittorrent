import SwiftUI

struct CookiesView: View {
    @Environment(\.dismiss) private var dismiss
    let store: TorrentStore
    @State private var cookies: [BackendCookie] = []
    @State private var draft = BackendCookie(name: "", domain: "", path: "/", value: "", expirationDate: 0)
    @State private var editingIndex: Int?
    @State private var showsEditor = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Cookies").font(.title2.weight(.semibold))
                Spacer()
                Button("Add") { editingIndex = nil; draft = BackendCookie(name: "", domain: "", path: "/", value: "", expirationDate: 0); showsEditor = true }
                    .buttonStyle(.glass)
                Button("Done") { dismiss() }
            }
            .padding(16)
            Divider()
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red).padding(10) }
            List {
                ForEach(Array(cookies.enumerated()), id: \.offset) { index, cookie in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(cookie.name).font(.headline)
                            Text("\(cookie.domain)\(cookie.path)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(cookie.expirationDate > 0 ? Date(timeIntervalSince1970: TimeInterval(cookie.expirationDate)).formatted(date: .abbreviated, time: .omitted) : "Session")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Edit") { editingIndex = index; draft = cookie; showsEditor = true }
                            .buttonStyle(.glass)
                        Button("Remove", role: .destructive) {
                            var updated = cookies
                            updated.remove(at: index)
                            save(updated)
                        }
                        .disabled(isSaving)
                    }
                }
            }
        }
        .frame(width: 680, height: 490)
        .task { await reload() }
        .sheet(isPresented: $showsEditor) {
            VStack(alignment: .leading, spacing: 16) {
                Text(editingIndex == nil ? "Add Cookie" : "Edit Cookie")
                    .font(.title2.weight(.semibold))
                Form {
                    TextField("Name", text: $draft.name)
                    TextField("Domain", text: $draft.domain)
                    TextField("Path", text: $draft.path)
                    TextField("Value", text: $draft.value)
                    TextField("Expiration (Unix seconds; 0 = session)", value: $draft.expirationDate, format: .number)
                }
                .formStyle(.grouped)
                .frame(height: 250)
                HStack {
                    Spacer()
                    Button("Cancel") { showsEditor = false }
                    Button("Save") {
                        var updated = cookies
                        if let editingIndex, updated.indices.contains(editingIndex) { updated[editingIndex] = draft }
                        else { updated.append(draft) }
                        save(updated)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(draft.name.isEmpty || draft.domain.isEmpty || draft.expirationDate < 0 || isSaving)
                }
            }
            .padding(22)
            .frame(width: 510)
        }
    }

    private func reload() async {
        do { cookies = try await store.cookies(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    private func save(_ updated: [BackendCookie]) {
        isSaving = true
        Task {
            do {
                try await store.setCookies(updated)
                await reload()
                showsEditor = false
            } catch { errorMessage = error.localizedDescription }
            isSaving = false
        }
    }
}
