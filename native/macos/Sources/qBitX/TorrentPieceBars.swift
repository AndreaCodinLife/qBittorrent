import SwiftUI

struct TorrentPieceBars: View {
    let states: [Int]
    let availability: [Int]

    private var downloadedCount: Int { states.filter { $0 == 2 }.count }
    private var requestedCount: Int { states.filter { $0 == 1 }.count }
    private var maximumAvailability: Int { availability.max() ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Downloaded Pieces")
                    Spacer()
                    Text("\(downloadedCount) / \(states.count)")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.caption2)
                Canvas { context, size in
                    drawPieces(states, in: &context, size: size)
                }
                .frame(height: 12)
                .help("\(downloadedCount) downloaded, \(requestedCount) requested, \(max(0, states.count - downloadedCount - requestedCount)) missing")
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Piece Availability")
                    Spacer()
                    Text("Max \(maximumAvailability) peers")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.caption2)
                Canvas { context, size in
                    drawAvailability(availability, in: &context, size: size)
                }
                .frame(height: 12)
                .help("Average availability \(availability.isEmpty ? "—" : String(format: "%.3f", Double(availability.reduce(0, +)) / Double(availability.count)))")
            }
        }
        .padding(.bottom, 5)
    }

    private func drawPieces(_ values: [Int], in context: inout GraphicsContext, size: CGSize) {
        drawBackground(in: &context, size: size)
        guard !values.isEmpty, size.width > 1 else { return }
        let columns = min(max(1, Int(size.width.rounded(.down))), 2_048)
        let step = Double(values.count) / Double(columns)
        for column in 0..<columns {
            let start = min(values.count - 1, Int(Double(column) * step))
            let end = min(values.count, max(start + 1, Int(Double(column + 1) * step)))
            let bucket = values[start..<end]
            let complete = Double(bucket.filter { $0 == 2 }.count) / Double(bucket.count)
            let requested = Double(bucket.filter { $0 == 1 }.count) / Double(bucket.count)
            let rect = CGRect(x: Double(column) * size.width / Double(columns), y: 1, width: size.width / Double(columns) + 0.5, height: max(1, size.height - 2))
            if complete > 0 {
                context.fill(Path(rect), with: .color(Color.accentColor.opacity(0.18 + 0.82 * complete)))
            } else if requested > 0 {
                context.fill(Path(rect), with: .color(Color.orange.opacity(0.2 + 0.8 * requested)))
            }
        }
        drawBorder(in: &context, size: size)
    }

    private func drawAvailability(_ values: [Int], in context: inout GraphicsContext, size: CGSize) {
        drawBackground(in: &context, size: size)
        guard !values.isEmpty, size.width > 1, maximumAvailability > 0 else { return }
        let columns = min(max(1, Int(size.width.rounded(.down))), 2_048)
        let step = Double(values.count) / Double(columns)
        for column in 0..<columns {
            let start = min(values.count - 1, Int(Double(column) * step))
            let end = min(values.count, max(start + 1, Int(Double(column + 1) * step)))
            let bucket = values[start..<end]
            let average = Double(bucket.reduce(0, +)) / Double(bucket.count)
            let intensity = min(1, average / Double(maximumAvailability))
            let rect = CGRect(x: Double(column) * size.width / Double(columns), y: 1, width: size.width / Double(columns) + 0.5, height: max(1, size.height - 2))
            context.fill(Path(rect), with: .color(Color.accentColor.opacity(0.9 * intensity)))
        }
        drawBorder(in: &context, size: size)
    }

    private func drawBackground(in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(Color.secondary.opacity(0.12)))
    }

    private func drawBorder(in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(x: 0.5, y: 0.5, width: max(0, size.width - 1), height: max(0, size.height - 1))
        context.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(Color.secondary.opacity(0.28)), lineWidth: 1)
    }
}
