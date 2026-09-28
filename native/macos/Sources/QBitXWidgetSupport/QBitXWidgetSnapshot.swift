import Foundation

public struct QBitXWidgetSnapshot: Codable, Equatable, Sendable {
    public let sampledAt: Date
    public let isConnected: Bool
    public let totalTorrentCount: Int
    public let activeTorrentCount: Int
    public let downloadingCount: Int
    public let seedingCount: Int
    public let downloadRate: Int64
    public let uploadRate: Int64

    public init(
        sampledAt: Date = .now,
        isConnected: Bool,
        totalTorrentCount: Int,
        activeTorrentCount: Int,
        downloadingCount: Int,
        seedingCount: Int,
        downloadRate: Int64,
        uploadRate: Int64
    ) {
        self.sampledAt = sampledAt
        self.isConnected = isConnected
        self.totalTorrentCount = totalTorrentCount
        self.activeTorrentCount = activeTorrentCount
        self.downloadingCount = downloadingCount
        self.seedingCount = seedingCount
        self.downloadRate = downloadRate
        self.uploadRate = uploadRate
    }
}

public enum QBitXWidgetSnapshotStore {
    public static let appGroupInfoKey = "QBitXAppGroupIdentifier"
    public static let widgetKind = "QBitXTransferWidget"

    public static func load(from bundle: Bundle = .main) -> QBitXWidgetSnapshot? {
        guard let groupIdentifier = bundle.object(forInfoDictionaryKey: appGroupInfoKey) as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier),
              let data = try? Data(contentsOf: container.appending(path: "transfer-status.json")) else {
            return nil
        }
        return try? JSONDecoder().decode(QBitXWidgetSnapshot.self, from: data)
    }

    public static func save(_ snapshot: QBitXWidgetSnapshot, groupIdentifier: String) throws {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: container.appending(path: "transfer-status.json"), options: .atomic)
    }
}
