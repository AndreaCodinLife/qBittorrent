import SwiftUI

struct ProgramUpdatePresentation: ViewModifier {
    @Bindable var checker: ProgramUpdateState
    let automaticallyCheck: Bool

    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .task(id: automaticallyCheck) {
                checker.setAutomaticChecking(automaticallyCheck)
            }
            .alert(LocalizedStringKey(checker.prompt?.title ?? "Check for Updates"), isPresented: Binding(
                get: { checker.prompt != nil },
                set: { if !$0 { checker.prompt = nil } }
            )) {
                if let prompt = checker.prompt, let url = prompt.actionURL {
                    Button(LocalizedStringKey(prompt.actionTitle ?? "Open Release")) {
                        checker.prompt = nil
                        openURL(url)
                    }
                }
                Button(checker.prompt?.actionURL == nil ? "OK" : "Later", role: .cancel) {
                    checker.prompt = nil
                }
            } message: {
                Text(LocalizedStringKey(checker.prompt?.message ?? ""))
            }
    }
}
