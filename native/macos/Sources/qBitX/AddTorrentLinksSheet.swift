import SwiftUI
import TorrentLinkInput

struct AddTorrentLinksSheet: View {
    let onAdd: ([URL]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(initialText: String, onAdd: @escaping ([URL]) -> Void) {
        self.onAdd = onAdd
        _text = State(initialValue: initialText)
    }

    private var result: TorrentLinkParseResult { TorrentLinkInput.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add Torrent Links")
                    .font(.title2.weight(.semibold))
                Text("Enter one HTTP, HTTPS, FTP, or magnet link per line. Info hashes are supported too.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Paste or type torrent links, one per line")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Torrent links, one per line")
                .frame(minHeight: 190, maxHeight: .infinity)

            HStack(alignment: .firstTextBaseline) {
                if let invalid = result.invalidLines.first {
                    Text(result.invalidLines.count == 1
                         ? "Unsupported link: \(invalid)"
                         : "\(result.invalidLines.count) lines are not supported, starting with: \(invalid)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else {
                    Text("\(result.urls.count) unique link\(result.urls.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: { dismiss() })
                    .keyboardShortcut(.cancelAction)
                Button(result.urls.isEmpty ? "Download" : "Download \(result.urls.count)") {
                    onAdd(result.urls)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(result.urls.isEmpty || !result.invalidLines.isEmpty)
            }
        }
        .padding(22)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 350, idealHeight: 420)
    }
}
