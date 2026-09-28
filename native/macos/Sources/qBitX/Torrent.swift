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
        return switch self {
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
    var trackerHosts: [String]
    var hasTrackerWarning: Bool
    var hasTrackerError: Bool
    var hasOtherAnnounceError: Bool
    let sizeBytes: Int64
    let progress: Double
    let downloadRateBytes: Int64
    let uploadRateBytes: Int64
    let seeds: Int
    let peers: Int
    let totalSeeds: Int?
    let totalPeers: Int?
    let etaSeconds: Int64
    let ratio: Double
    let savePath: String
    let rawState: String
    let state: TorrentState
    let forceStart: Bool
    let sequentialDownload: Bool
    let firstLastPiecePriority: Bool
    let automaticManagement: Bool
    let superSeeding: Bool
    let extra: [String: String]
    let sortNumbers: [String: Double]

    func column(_ key: String) -> String { extra[key] ?? "—" }

    var size: String { ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file) }
    var seedCountText: String {
        guard let totalSeeds, totalSeeds >= 0 else { return "\(seeds)" }
        return "\(seeds) (\(totalSeeds))"
    }
    var peerCountText: String {
        guard let totalPeers, totalPeers >= 0 else { return "\(peers)" }
        return "\(peers) (\(totalPeers))"
    }
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
    case all = "All"
    case downloading = "Downloading"
    case seeding = "Seeding"
    case completed = "Completed"
    case running = "Running"
    case stopped = "Stopped"
    case active = "Active"
    case inactive = "Inactive"
    case stalled = "Stalled"
    case stalledUploading = "Stalled Uploading"
    case stalledDownloading = "Stalled Downloading"
    case checking = "Checking"
    case moving = "Moving"
    case errored = "Errored"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .all: "square.stack.fill"
        case .downloading: "arrow.down"
        case .seeding: "arrow.up"
        case .completed: "checkmark.circle"
        case .running: "play.circle"
        case .stopped: "pause"
        case .active: "bolt.fill"
        case .inactive: "moon"
        case .stalled, .stalledUploading, .stalledDownloading: "exclamationmark.triangle"
        case .checking: "checkmark.circle"
        case .moving: "arrow.triangle.2.circlepath"
        case .errored: "xmark.circle"
        }
    }

    func includes(_ torrent: Torrent) -> Bool {
        let value = torrent.rawState
        let isActive = torrent.downloadRateBytes > 0 || torrent.uploadRateBytes > 0
        return switch self {
        case .all: true
        case .downloading: ["downloading", "forcedDL", "metaDL", "forcedMetaDL", "stalledDL", "checkingDL", "stoppedDL", "queuedDL"].contains(value)
        case .seeding: ["uploading", "forcedUP", "stalledUP", "checkingUP", "queuedUP"].contains(value)
        case .completed: ["uploading", "forcedUP", "stalledUP", "checkingUP", "stoppedUP", "queuedUP"].contains(value)
        case .running: value != "stoppedUP" && value != "stoppedDL"
        case .stopped: value == "stoppedUP" || value == "stoppedDL"
        case .active: isActive
        case .inactive: !isActive
        case .stalled: value == "stalledUP" || value == "stalledDL"
        case .stalledUploading: value == "stalledUP"
        case .stalledDownloading: value == "stalledDL"
        case .checking: value.hasPrefix("checking")
        case .moving: value == "moving"
        case .errored: value == "error" || value == "missingFiles"
        }
    }
}

enum TrackerStatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case warning = "Warning"
    case trackerError = "Tracker error"
    case otherError = "Other error"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .all: "network"
        case .warning: "exclamationmark.triangle"
        case .trackerError, .otherError: "xmark.octagon"
        }
    }

    func includes(_ torrent: Torrent) -> Bool {
        switch self {
        case .all: true
        case .warning: torrent.hasTrackerWarning
        case .trackerError: torrent.hasTrackerError
        case .otherError: torrent.hasOtherAnnounceError
        }
    }
}

struct TransferStatus: Sendable {
    var downloadRate: Int64 = 0
    var uploadRate: Int64 = 0
    var totalDownloadRate: Int64 = 0
    var totalUploadRate: Int64 = 0
    var payloadDownloadRate: Int64 = 0
    var payloadUploadRate: Int64 = 0
    var overheadDownloadRate: Int64 = 0
    var overheadUploadRate: Int64 = 0
    var dhtDownloadRate: Int64 = 0
    var dhtUploadRate: Int64 = 0
    var trackerDownloadRate: Int64 = 0
    var trackerUploadRate: Int64 = 0
    var dhtNodes: Int = 0
    var connectionStatus = "disconnected"
    var lastExternalAddressV4: String?
    var lastExternalAddressV6: String?

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
