import SwiftUI

@main
struct QBitXApp: App {
    @State private var store = TorrentStore()
    @AppStorage("qBitX.showSpeedInMenuBar") private var showSpeedInMenuBar = false

    var body: some Scene {
        WindowGroup("qBitX", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 980, minHeight: 620)
        }
        .commands { QBitXCommands() }
        .defaultSize(width: 1220, height: 760)

        MenuBarExtra(isInserted: $showSpeedInMenuBar) {
            MenuBarSpeedView(store: store)
        } label: {
            Label("qBitX", systemImage: "arrow.down.arrow.up.circle")
        }
        .menuBarExtraStyle(.menu)
    }
}
