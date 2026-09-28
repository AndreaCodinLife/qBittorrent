import Foundation
import QBitXThemeSupport

enum QBitXThemeFileImporter {
    static func palette(from url: URL) async throws -> QBitXThemePalette {
        guard url.pathExtension.lowercased() == "qbtheme" else {
            return try QBitXThemePalette(contentsOf: url)
        }

        let configData = try await Task.detached(priority: .userInitiated) {
            try extractConfigData(from: url)
        }.value
        return try QBitXThemePalette(configData: configData)
    }

    private static func extractConfigData(from url: URL) throws -> Data {
        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 64 * 1_024 * 1_024 {
            throw QBitXThemeFileImportError.resourceTooLarge
        }

        let extractorURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/qbitx-qbtheme-extractor")
        guard FileManager.default.isExecutableFile(atPath: extractorURL.path) else {
            throw QBitXThemeFileImportError.extractorUnavailable
        }

        let process = Process()
        process.executableURL = extractorURL
        process.arguments = [url.path]
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()

        let data = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw QBitXThemeFileImportError.extractionFailed(message.isEmpty ? nil : message)
        }
        guard data.count <= 1_048_576 else { throw QBitXThemeImportError.fileTooLarge }
        return data
    }
}

private enum QBitXThemeFileImportError: Error, LocalizedError {
    case resourceTooLarge
    case extractorUnavailable
    case extractionFailed(String?)

    var errorDescription: String? {
        switch self {
        case .resourceTooLarge:
            "The compiled theme resource is larger than 64 MB."
        case .extractorUnavailable:
            "The compiled theme importer is missing from this qBitX app bundle. Rebuild qBitX with the macOS package script."
        case let .extractionFailed(message):
            message ?? "The compiled theme resource could not be read."
        }
    }
}
