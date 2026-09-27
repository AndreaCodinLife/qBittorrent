import Foundation
import Security

enum BackendError: LocalizedError {
    case helperMissing
    case couldNotCreateKey
    case didNotStart

    var errorDescription: String? {
        switch self {
        case .helperMissing: "The qBittorrent backend is missing from this app. Rebuild qBitX with package-preview.sh."
        case .couldNotCreateKey: "Could not create a secure local API key."
        case .didNotStart: "The local qBittorrent backend did not start. Check the qBitX backend log."
        }
    }
}

@MainActor
final class BundledBackend {
    private var process: Process?
    private var port: Int {
        guard let configured = ProcessInfo.processInfo.environment["QBITX_TEST_BACKEND_PORT"],
              let port = Int(configured), (1024...65_535).contains(port) else { return 18567 }
        return port
    }

    private var root: URL {
        if let testRoot = ProcessInfo.processInfo.environment["QBITX_TEST_BACKEND_ROOT"], testRoot.hasPrefix("/") {
            return URL(fileURLWithPath: testRoot, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "qBitX/Backend", directoryHint: .isDirectory)
    }

    private var executable: URL {
        Bundle.main.bundleURL
            .appending(path: "Contents/Helpers/qbittorrent-nox.app/Contents/MacOS/qbittorrent-nox")
    }

    func connect() async throws -> QBittorrentAPI {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw BackendError.helperMissing
        }

        let config = root.appending(path: "qBittorrent/config/qBittorrent.ini")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)

        let key: String
        if let existing = try? String(contentsOf: config, encoding: .utf8),
           let match = existing.split(separator: "\n").first(where: { $0.hasPrefix("APIKey=") }) {
            key = String(match.dropFirst("APIKey=".count))
            if existing.contains("LocalHostAuth=false") {
                try existing.replacingOccurrences(of: "LocalHostAuth=false", with: "LocalHostAuth=true")
                    .write(to: config, atomically: true, encoding: .utf8)
            }
        } else {
            key = try generateAPIKey()
            let contents = "[WebUI]\nEnabled=true\nAddress=127.0.0.1\nPort=\(port)\nAPIKey=\(key)\nLocalHostAuth=true\nUseUPnP=false\n"
            try contents.write(to: config, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        }

        let api = try QBittorrentAPI(address: "http://127.0.0.1:\(port)", authentication: .apiKey(key))
        if (try? await api.verify()) != nil { return api }

        let backend = Process()
        backend.executableURL = executable
        backend.arguments = ["--profile=\(root.path)", "--webui-port=\(port)", "--confirm-legal-notice"]

        let logURL = root.appending(path: "backend.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logURL.path)
        }
        let logHandle = try FileHandle(forWritingTo: logURL)
        try logHandle.seekToEnd()
        backend.standardOutput = logHandle
        backend.standardError = logHandle
        try backend.run()
        process = backend

        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(300))
            if (try? await api.verify()) != nil { return api }
            if !backend.isRunning { break }
        }
        throw BackendError.didNotStart
    }

    private func generateAPIKey() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 21)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw BackendError.couldNotCreateKey
        }
        let encoded = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        return "qbt_" + encoded
    }
}
