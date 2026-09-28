import Foundation

public enum WebAPICompatibility {
    private static let minimumVersion = [2, 16, 2]
    private static let minimumVersionLabel = "2.16.2"

    public static func message(serverAPIVersion: String, isConnected: Bool) -> String? {
        guard isConnected else { return nil }
        guard let currentVersion = versionComponents(serverAPIVersion) else {
            return "qBitX could not read this server's Web API version, so full compatibility cannot be confirmed. Some newer features may be unavailable."
        }

        let count = max(currentVersion.count, minimumVersion.count)
        let paddedCurrent = currentVersion + Array(repeating: 0, count: count - currentVersion.count)
        let paddedMinimum = minimumVersion + Array(repeating: 0, count: count - minimumVersion.count)
        guard paddedCurrent.lexicographicallyPrecedes(paddedMinimum) else { return nil }
        return "This server exposes Web API \(serverAPIVersion); full qBitX feature parity requires \(minimumVersionLabel) or later. Some newer RSS and category settings may be unavailable."
    }

    private static func versionComponents(_ value: String) -> [Int]? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ component in
                  !component.isEmpty && component.utf8.allSatisfy { (48...57).contains($0) }
              })
        else { return nil }

        let parsed = components.compactMap { Int($0) }
        return parsed.count == components.count ? parsed : nil
    }
}
