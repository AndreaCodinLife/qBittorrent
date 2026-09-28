import Foundation
import Observation

enum ProgramUpdateResult: Sendable {
    case available(version: String, releaseURL: URL)
    case current
    case noPublishedRelease
}

enum ProgramUpdateError: LocalizedError {
    case invalidInstalledVersion
    case invalidReleaseData
    case serverResponse(Int)

    var errorDescription: String? {
        switch self {
        case .invalidInstalledVersion:
            "The installed qBitX version could not be read."
        case .invalidReleaseData:
            "GitHub returned release information that qBitX could not read."
        case let .serverResponse(status):
            "GitHub returned HTTP \(status) while checking for qBitX updates."
        }
    }
}

enum ProgramUpdateChecker {
    private static let releaseAPI = URL(string: "https://api.github.com/repos/AndreaCodinLife/qBittorrent/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/AndreaCodinLife/qBittorrent/releases")!

    static func check() async throws -> ProgramUpdateResult {
        let installedVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        guard let installed = SemanticVersion(installedVersion) else {
            throw ProgramUpdateError.invalidInstalledVersion
        }

        var request = URLRequest(url: releaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("qBitX macOS update checker", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ProgramUpdateError.invalidReleaseData
        }
        if response.statusCode == 404 {
            return .noPublishedRelease
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ProgramUpdateError.serverResponse(response.statusCode)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let latest = SemanticVersion(release.tagName),
              release.url.scheme?.lowercased() == "https",
              release.url.host?.lowercased() == "github.com" else {
            throw ProgramUpdateError.invalidReleaseData
        }
        return latest > installed
            ? .available(version: release.tagName, releaseURL: release.url)
            : .current
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let url: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case url = "html_url"
        }
    }
}

struct ProgramUpdatePrompt {
    let title: String
    let message: String
    var actionTitle: String?
    var actionURL: URL?
}

@MainActor
@Observable
final class ProgramUpdateState {
    var prompt: ProgramUpdatePrompt?
    private var automaticCheckTask: Task<Void, Never>?

    func setAutomaticChecking(_ enabled: Bool) {
        guard enabled else {
            automaticCheckTask?.cancel()
            automaticCheckTask = nil
            return
        }
        guard automaticCheckTask == nil else { return }

        automaticCheckTask = Task { @MainActor in
            await check(manual: false)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(24 * 60 * 60)) }
                catch { break }
                await check(manual: false)
            }
            automaticCheckTask = nil
        }
    }

    func check(manual: Bool) async {
        do {
            switch try await ProgramUpdateChecker.check() {
            case let .available(version, releaseURL):
                prompt = ProgramUpdatePrompt(
                    title: "qBitX Update Available",
                    message: "qBitX version \(version) is available. Open its GitHub release page to read the notes and download it.",
                    actionTitle: "View Release",
                    actionURL: releaseURL
                )
            case .current where manual:
                prompt = ProgramUpdatePrompt(
                    title: "qBitX",
                    message: "You are already using the latest published qBitX version."
                )
            case .noPublishedRelease where manual:
                prompt = ProgramUpdatePrompt(
                    title: "No qBitX Release Yet",
                    message: "There is no published qBitX release yet. The release page will show downloads when one is published.",
                    actionTitle: "Open Releases",
                    actionURL: ProgramUpdateChecker.releasesPage
                )
            case .current, .noPublishedRelease:
                break
            }
        } catch {
            if manual {
                prompt = ProgramUpdatePrompt(
                    title: "Update Check Failed",
                    message: error.localizedDescription
                )
            }
        }
    }
}

private struct SemanticVersion: Comparable {
    private enum Identifier: Equatable {
        case number(Int)
        case text(String)
    }

    private let core: [Int]
    private let prerelease: [Identifier]?

    init?(_ source: String) {
        var value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" { value.removeFirst() }
        value = value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? value

        let versionParts = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let coreParts = versionParts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(coreParts.count),
              coreParts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        var parsedCore: [Int] = []
        for part in coreParts {
            guard let number = Int(part) else { return nil }
            parsedCore.append(number)
        }
        core = Array((parsedCore + [0, 0, 0, 0]).prefix(4))

        if versionParts.count == 1 {
            prerelease = nil
        } else {
            let identifiers = versionParts[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !identifiers.isEmpty,
                  identifiers.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }) else {
                return nil
            }
            prerelease = identifiers.map { identifier in
                let value = String(identifier)
                if let number = Int(value) { return .number(number) }
                return .text(value)
            }
        }
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        for index in lhs.core.indices where lhs.core[index] != rhs.core[index] {
            return lhs.core[index] < rhs.core[index]
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        case let (.some(left), .some(right)):
            for index in 0..<min(left.count, right.count) where left[index] != right[index] {
                switch (left[index], right[index]) {
                case let (.number(left), .number(right)):
                    return left < right
                case (.number, .text):
                    return true
                case (.text, .number):
                    return false
                case let (.text(left), .text(right)):
                    return left < right
                }
            }
            return left.count < right.count
        }
    }
}
