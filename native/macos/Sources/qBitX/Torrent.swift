import Foundation

enum TorrentState: String, CaseIterable, Sendable {
    case downloading = "Downloading"
    case seeding = "Seeding"
    case paused = "Stopped"
    case stalled = "Stalled"
    case queued = "Queued"
    case checking = "Checking"
    case error = "Error"

    init(apiValue: String) {
        switch apiValue {
        case "uploading", "forcedUP": self = .seeding
        case "downloading", "metaDL", "forcedDL", "forcedMetaDL": self = .downloading
        case "stoppedUP", "stoppedDL": self = .paused
        case "stalledUP", "stalledDL": self = .stalled
        case "queuedUP", "queuedDL": self = .queued
        case "checkingUP", "checkingDL", "checkingResumeData", "moving": self = .checking
        default: self = .error
        }
    }

    var symbol: String {
        switch self {
        case .downloading: "arrow.down.circle.fill"
        case .seeding: "arrow.up.circle.fill"
        case .paused: "pause.circle.fill"
        case .stalled: "exclamationmark.circle.fill"
        case .queued: "clock.fill"
        case .checking: "checkmark.circle.fill"
        case .error: "xmark.circle.fill"
        }
    }
}

struct Torrent: Identifiable, Sendable {
    let id: String
    let name: String
    let category: String
    let tags: String
    let tracker: String
    let sizeBytes: Int64
    let progress: Double
    let downloadRateBytes: Int64
    let uploadRateBytes: Int64
    let seeds: Int
    let peers: Int
    let etaSeconds: Int64
    let ratio: Double
    let savePath: String
    let state: TorrentState

    var size: String { ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file) }
    var downloadRate: String { Self.rate(downloadRateBytes) }
    var uploadRate: String { Self.rate(uploadRateBytes) }
    var eta: String {
        guard state == .downloading, etaSeconds >= 0, etaSeconds < 86_400 * 100 else { return "—" }
        if etaSeconds < 60 { return "< 1 min" }
        if etaSeconds < 3_600 { return "\(etaSeconds / 60) min" }
        if etaSeconds < 86_400 { return "\(etaSeconds / 3_600) h" }
        return "\(etaSeconds / 86_400) d"
    }

    private static func rate(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary) + "/s"
    }
}

enum TorrentFilter: String, CaseIterable, Identifiable {
    case all = "All Torrents"
    case downloading = "Downloading"
    case seeding = "Seeding"
    case paused = "Stopped"
    case stalled = "Stalled"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .all: "square.stack.fill"
        case .downloading: "arrow.down"
        case .seeding: "arrow.up"
        case .paused: "pause"
        case .stalled: "exclamationmark.triangle"
        }
    }

    func includes(_ torrent: Torrent) -> Bool {
        switch self {
        case .all: true
        case .downloading: torrent.state == .downloading
        case .seeding: torrent.state == .seeding
        case .paused: torrent.state == .paused
        case .stalled: torrent.state == .stalled || torrent.state == .error
        }
    }
}

struct TransferStatus: Sendable {
    var downloadRate: Int64 = 0
    var uploadRate: Int64 = 0
    var dhtNodes: Int = 0
    var connectionStatus = "disconnected"

    static func rateText(_ bytes: Int64) -> String {
        bytes == 0 ? "0 B/s" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary) + "/s"
    }

    var downloadText: String {
        Self.rateText(downloadRate)
    }
    var uploadText: String {
        Self.rateText(uploadRate)
    }
}
