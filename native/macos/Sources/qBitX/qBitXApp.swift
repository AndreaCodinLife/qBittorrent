import SwiftUI

@main
struct QBitXApp: App {
    @NSApplicationDelegateAdaptor(QBitXApplicationDelegate.self) private var appDelegate
    @State private var store: TorrentStore
    @State private var programUpdateChecker = ProgramUpdateState()
    @AppStorage("qBitX.showSpeedInMenuBar") private var showSpeedInMenuBar = false

    // AppKit may report the current status item visibility repeatedly. Writing the
    // same value through AppStorage invalidates the app graph on every report.
    private var menuBarVisibility: Binding<Bool> {
        Binding(
            get: { showSpeedInMenuBar },
            set: { isVisible in
                guard showSpeedInMenuBar != isVisible else { return }
                showSpeedInMenuBar = isVisible
            }
        )
    }

    init() {
        let store = TorrentStore()
        _store = State(initialValue: store)
        QBitXApplicationDelegate.store = store
    }

    var body: some Scene {
        WindowGroup("qBitX", id: "main") {
            Group {
                if store.hasCompletedInitialConnection {
                    ContentView(store: store, programUpdateChecker: programUpdateChecker)
                } else {
                    VStack(spacing: 16) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .accessibilityHidden(true)
                        ProgressView("Starting qBittorrent…")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                }
            }
            .frame(minWidth: 980, minHeight: 620)
        }
        .commands {
            if store.hasCompletedInitialConnection {
                QBitXCommands()
            }
        }
        .defaultSize(width: 1220, height: 760)

        MenuBarExtra(isInserted: menuBarVisibility) {
            MenuBarSpeedView(store: store)
                .environment(\.locale, store.interfaceLocale.isEmpty ? .current : Locale(identifier: store.interfaceLocale))
        } label: {
            Label {
                Text("↓ \(store.transferStatus.downloadText)  ↑ \(store.transferStatus.uploadText)")
            } icon: {
                Image(systemName: "arrow.down.arrow.up.circle")
            }
            .accessibilityLabel("qBitX. Download \(store.transferStatus.downloadText), upload \(store.transferStatus.uploadText)")
        }
        .menuBarExtraStyle(.menu)
    }
}
