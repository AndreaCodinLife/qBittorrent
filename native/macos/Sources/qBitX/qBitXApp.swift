import SwiftUI

@main
struct QBitXApp: App {
    var body: some Scene {
        WindowGroup("qBitX") {
            ContentView()
                .frame(minWidth: 980, minHeight: 620)
        }
        .defaultSize(width: 1220, height: 760)
    }
}
