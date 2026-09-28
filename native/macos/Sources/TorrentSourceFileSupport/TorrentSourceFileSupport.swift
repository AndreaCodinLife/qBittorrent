import Foundation

public enum TorrentSourceFileSupport {
    public enum RemovalError: LocalizedError {
        case sourceChanged

        public var errorDescription: String? {
            "The source .torrent file changed after it was opened, so qBitX kept it."
        }
    }

    public static func removeIfUnchanged(at url: URL, matching uploadedData: Data) throws {
        guard url.isFileURL,
              url.pathExtension.lowercased() == "torrent",
              FileManager.default.fileExists(atPath: url.path) else { return }

        let accessGranted = url.startAccessingSecurityScopedResource()
        defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }

        guard try Data(contentsOf: url) == uploadedData else { throw RemovalError.sourceChanged }
        try FileManager.default.removeItem(at: url)
    }
}
