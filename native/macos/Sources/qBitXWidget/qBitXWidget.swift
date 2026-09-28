import QBitXWidgetSupport
import SwiftUI
import WidgetKit

private struct TransferWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: QBitXWidgetSnapshot?
}

private struct TransferWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TransferWidgetEntry {
        TransferWidgetEntry(date: .now, snapshot: placeholderSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (TransferWidgetEntry) -> Void) {
        let snapshot = context.isPreview ? placeholderSnapshot : QBitXWidgetSnapshotStore.load()
        completion(TransferWidgetEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TransferWidgetEntry>) -> Void) {
        let entry = TransferWidgetEntry(date: .now, snapshot: QBitXWidgetSnapshotStore.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private var placeholderSnapshot: QBitXWidgetSnapshot {
        QBitXWidgetSnapshot(
            isConnected: true,
            totalTorrentCount: 8,
            activeTorrentCount: 3,
            downloadingCount: 2,
            seedingCount: 4,
            downloadRate: 2_400_000,
            uploadRate: 820_000
        )
    }
}

private struct TransferWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TransferWidgetEntry

    private var snapshot: QBitXWidgetSnapshot? { entry.snapshot }
    private var connectionLabel: String {
        guard let snapshot else { return "Open qBitX to connect" }
        return snapshot.isConnected ? "Connected" : "Disconnected"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.down.arrow.up.circle.fill")
                    .foregroundStyle(.tint)
                Text("qBitX")
                    .font(.headline)
                Spacer(minLength: 4)
                Circle()
                    .fill(snapshot?.isConnected == true ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(connectionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let snapshot {
                switch family {
                case .systemSmall:
                    smallStatus(snapshot)
                case .systemLarge, .systemExtraLarge:
                    largeStatus(snapshot)
                default:
                    mediumStatus(snapshot)
                }
                Spacer(minLength: 0)
                Text("Updated \(snapshot.sampledAt, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ContentUnavailableView("No transfer data", systemImage: "arrow.down.arrow.up", description: Text("Open qBitX to connect to a qBittorrent server."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func smallStatus(_ snapshot: QBitXWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            rateRow("Download", rate: snapshot.downloadRate, symbol: "arrow.down")
            rateRow("Upload", rate: snapshot.uploadRate, symbol: "arrow.up")
            Text("\(snapshot.activeTorrentCount) active · \(snapshot.totalTorrentCount) total")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func mediumStatus(_ snapshot: QBitXWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                rateMetric("Download", rate: snapshot.downloadRate, symbol: "arrow.down")
                rateMetric("Upload", rate: snapshot.uploadRate, symbol: "arrow.up")
            }
            Label("\(snapshot.activeTorrentCount) active of \(snapshot.totalTorrentCount) torrents", systemImage: "bolt.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func largeStatus(_ snapshot: QBitXWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                rateMetric("Download", rate: snapshot.downloadRate, symbol: "arrow.down")
                rateMetric("Upload", rate: snapshot.uploadRate, symbol: "arrow.up")
            }
            Divider()
            HStack(spacing: 24) {
                countMetric("Downloading", count: snapshot.downloadingCount, symbol: "arrow.down.circle")
                countMetric("Seeding", count: snapshot.seedingCount, symbol: "arrow.up.circle")
                countMetric("Active", count: snapshot.activeTorrentCount, symbol: "bolt.fill")
            }
            Text("\(snapshot.totalTorrentCount) torrents in the library")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func rateRow(_ title: String, rate: Int64, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(TransferWidgetFormat.rate(rate))
                .font(.subheadline.weight(.medium).monospacedDigit())
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(TransferWidgetFormat.rate(rate))")
    }

    private func rateMetric(_ title: String, rate: Int64, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(TransferWidgetFormat.rate(rate))
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func countMetric(_ title: String, count: Int, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(count.formatted())
                .font(.title3.weight(.semibold).monospacedDigit())
        }
    }
}

private enum TransferWidgetFormat {
    static func rate(_ bytesPerSecond: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytesPerSecond, countStyle: .binary) + "/s"
    }
}

private struct QBitXTransferWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: QBitXWidgetSnapshotStore.widgetKind, provider: TransferWidgetProvider()) { entry in
            TransferWidgetView(entry: entry)
        }
        .configurationDisplayName("qBitX Transfers")
        .description("See transfer speeds and torrent activity at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
private struct QBitXWidgetBundle: WidgetBundle {
    var body: some Widget {
        QBitXTransferWidget()
    }
}
