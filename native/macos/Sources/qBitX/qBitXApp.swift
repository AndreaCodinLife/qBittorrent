import SwiftUI

@main
struct QBitXApp: App {
    @NSApplicationDelegateAdaptor(QBitXApplicationDelegate.self) private var appDelegate
    @State private var store: TorrentStore
    @AppStorage("qBitX.showSpeedInMenuBar") private var showSpeedInMenuBar = false

    init() {
        let store = TorrentStore()
        _store = State(initialValue: store)
        QBitXApplicationDelegate.store = store
    }

    var body: some Scene {
        WindowGroup("qBitX", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 980, minHeight: 620)
        }
        .commands { QBitXCommands() }
        .defaultSize(width: 1220, height: 760)

        MenuBarExtra(isInserted: $showSpeedInMenuBar) {
            MenuBarSpeedView(store: store)
                .environment(\.locale, store.interfaceLocale.isEmpty ? .current : Locale(identifier: store.interfaceLocale))
        } label: {
            Label("qBitX", systemImage: "arrow.down.arrow.up.circle")
        }
        .menuBarExtraStyle(.menu)
    }
}
