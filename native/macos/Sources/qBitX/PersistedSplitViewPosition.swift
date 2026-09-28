import AppKit
import SwiftUI

struct PersistedSplitViewPosition: NSViewRepresentable {
    let name: NSSplitView.AutosaveName

    func makeNSView(context: Context) -> SplitViewAutosaveAnchor {
        let view = SplitViewAutosaveAnchor()
        view.autosaveName = name
        return view
    }

    func updateNSView(_ nsView: SplitViewAutosaveAnchor, context: Context) {
        nsView.autosaveName = name
        nsView.savePositionOnEnclosingSplitView()
    }
}

@MainActor
final class SplitViewAutosaveAnchor: NSView {
    var autosaveName: NSSplitView.AutosaveName?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        savePositionOnEnclosingSplitView()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        savePositionOnEnclosingSplitView()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func savePositionOnEnclosingSplitView() {
        guard let autosaveName else { return }

        var ancestor = superview
        while let view = ancestor {
            if let splitView = view as? NSSplitView {
                if splitView.autosaveName != autosaveName {
                    splitView.autosaveName = autosaveName
                }
                return
            }
            ancestor = view.superview
        }
    }
}
