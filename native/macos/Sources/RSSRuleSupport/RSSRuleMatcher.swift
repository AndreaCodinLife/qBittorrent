import Foundation

public struct RSSRuleMatchCandidate: Sendable {
    public let feedURL: String
    public let feedTitle: String
    public let title: String
    public let date: Date?

    public init(feedURL: String, feedTitle: String, title: String, date: Date?) {
        self.feedURL = feedURL
        self.feedTitle = feedTitle
        self.title = title
        self.date = date
    }
}

public struct RSSRuleMatchDefinition: Sendable {
    public let affectedFeedURLs: Set<String>
    public let mustContain: String
    public let mustNotContain: String
    public let useRegex: Bool
    public let episodeFilter: String
    public let smartFilter: Bool
    public let ignoreDays: Int
    public let lastMatch: String
    public let previouslyMatchedEpisodes: Set<String>

    public init(
        affectedFeedURLs: Set<String>,
        mustContain: String,
        mustNotContain: String,
        useRegex: Bool,
        episodeFilter: String,
        smartFilter: Bool,
        ignoreDays: Int,
        lastMatch: String,
        previouslyMatchedEpisodes: Set<String>
    ) {
        self.affectedFeedURLs = affectedFeedURLs
        self.mustContain = mustContain
        self.mustNotContain = mustNotContain
        self.useRegex = useRegex
        self.episodeFilter = episodeFilter
        self.smartFilter = smartFilter
        self.ignoreDays = ignoreDays
        self.lastMatch = lastMatch
        self.previouslyMatchedEpisodes = previouslyMatchedEpisodes
    }
}

public struct RSSRuleMatchSettings: Sendable {
    public let smartEpisodeFilters: [String]
    public let downloadRepacks: Bool

    public init(smartEpisodeFilters: [String], downloadRepacks: Bool) {
        self.smartEpisodeFilters = smartEpisodeFilters
        self.downloadRepacks = downloadRepacks
    }

    public static let qBittorrentDefaults = RSSRuleMatchSettings(
        smartEpisodeFilters: [
            #"s(\d+)e(\d+)"#,
            #"(\d+)x(\d+)"#,
            #"(\d{4}[.\-]\d{1,2}[.\-]\d{1,2})"#,
            #"(\d{1,2}[.\-]\d{1,2}[.\-]\d{4})"#
        ],
        downloadRepacks: true
    )
}

public struct RSSRuleMatchGroup: Sendable, Equatable {
    public let feedTitle: String
    public let titles: [String]

    public init(feedTitle: String, titles: [String]) {
        self.feedTitle = feedTitle
        self.titles = titles
    }
}

public enum RSSRuleMatcher {
    public static func matchingArticles(
        _ candidates: [RSSRuleMatchCandidate],
        rule: RSSRuleMatchDefinition,
        settings: RSSRuleMatchSettings = .qBittorrentDefaults
    ) -> [RSSRuleMatchGroup] {
        guard !rule.affectedFeedURLs.isEmpty else { return [] }

        let lastMatch = RSSRuleValidation.lastMatchDate(from: rule.lastMatch)
        let ignoreBefore: Date? = {
            guard rule.ignoreDays > 0, let lastMatch else { return nil }
            return Calendar.current.date(byAdding: .day, value: rule.ignoreDays, to: lastMatch)
        }()
        var groupedTitles: [String: Set<String>] = [:]

        for candidate in candidates where rule.affectedFeedURLs.contains(candidate.feedURL) {
            if let ignoreBefore, let date = candidate.date, date < ignoreBefore { continue }
            guard matchesMustContain(candidate.title, expressionList: rule.mustContain, useRegex: rule.useRegex),
                  matchesMustNotContain(candidate.title, expressionList: rule.mustNotContain, useRegex: rule.useRegex),
                  matchesEpisodeFilter(candidate.title, filter: rule.episodeFilter),
                  matchesSmartFilter(
                    candidate.title,
                    enabled: rule.smartFilter,
                    previouslyMatchedEpisodes: rule.previouslyMatchedEpisodes,
                    settings: settings
                  ) else { continue }

            groupedTitles[candidate.feedTitle, default: []].insert(candidate.title)
        }

        return groupedTitles
            .map { RSSRuleMatchGroup(feedTitle: $0.key, titles: $0.value.sorted()) }
            .sorted { $0.feedTitle.localizedStandardCompare($1.feedTitle) == .orderedAscending }
    }

    private static func matchesMustContain(_ title: String, expressionList: String, useRegex: Bool) -> Bool {
        let expressions = ruleExpressions(expressionList)
        guard !expressions.isEmpty else { return true }
        return expressions.contains { matchesExpression(title, expression: $0, useRegex: useRegex) }
    }

    private static func matchesMustNotContain(_ title: String, expressionList: String, useRegex: Bool) -> Bool {
        let expressions = ruleExpressions(expressionList)
        guard !expressions.isEmpty else { return true }
        return !expressions.contains { matchesExpression(title, expression: $0, useRegex: useRegex) }
    }

    private static func ruleExpressions(_ value: String) -> [String] {
        if value.isEmpty { return [] }
        let expressions = value.components(separatedBy: "|")
        return expressions.count == 1 && expressions[0].isEmpty ? [] : expressions
    }

    private static func matchesExpression(_ title: String, expression: String, useRegex: Bool) -> Bool {
        if expression.isEmpty { return true }
        if useRegex { return regularExpression(expression, matches: title, options: [.caseInsensitive]) }

        let tokens = expression.split(whereSeparator: \.isWhitespace).map(String.init)
        return tokens.allSatisfy { wildcard in
            regularExpression(wildcardToRegex(wildcard), matches: title, options: [.caseInsensitive, .dotMatchesLineSeparators])
        }
    }

    private static func wildcardToRegex(_ wildcard: String) -> String {
        var pattern = ""
        for character in wildcard {
            switch character {
            case "*": pattern += ".*"
            case "?": pattern += "."
            default:
                if #"\.^$|()[]{}+"#.contains(character) { pattern.append("\\") }
                pattern.append(character)
            }
        }
        return pattern
    }

    private static func regularExpression(
        _ pattern: String,
        matches value: String,
        options: NSRegularExpression.Options
    ) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        return expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    private static func matchesEpisodeFilter(_ title: String, filter: String) -> Bool {
        guard !filter.isEmpty else { return true }
        guard let filterMatch = firstMatch(#"^(\d{1,4})x(.*;$)"#, in: filter, options: [.caseInsensitive]),
              filterMatch.count > 2,
              let seasonCapture = filterMatch[1],
              let episodesCapture = filterMatch[2] else { return false }
        let season = Int32(seasonCapture) ?? 0

        for rawEpisode in episodesCapture.split(separator: ";", omittingEmptySubsequences: false) {
            var episode = String(rawEpisode)
            while episode.count > 1 && episode.first == "0" { episode.removeFirst() }
            guard !episode.isEmpty else { continue }

            if episode.contains("-") {
                guard let articleEpisode = articleSeasonAndEpisode(title) else { continue }
                if episode.hasSuffix("-") {
                    let start = Int32(episode.dropLast()) ?? 0
                    if (articleEpisode.season == season && articleEpisode.episode >= start) || articleEpisode.season > season {
                        return true
                    }
                } else {
                    let range = episode.split(separator: "-", omittingEmptySubsequences: false)
                    guard range.count == 2,
                          let first = Int32(range[0]),
                          let last = Int32(range[1]),
                          first <= last else { continue }
                    if articleEpisode.season == season && articleEpisode.episode >= first && articleEpisode.episode <= last {
                        return true
                    }
                }
            } else {
                let pattern = #"\b(?:s0?\#(seasonCapture)[ -_.]?e0?\#(episode)(?:\D|\b)|\#(seasonCapture)x0?\#(episode)(?:\D|\b))"#
                if regularExpression(pattern, matches: title, options: [.caseInsensitive]) { return true }
            }
        }

        return false
    }

    private static func articleSeasonAndEpisode(_ title: String) -> (season: Int32, episode: Int32)? {
        let patterns = [
            #"\bs0?(\d{1,4})[ -_.]?e(0?\d{1,4})(?:\D|\b)"#,
            #"\b(\d{1,4})x(0?\d{1,4})(?:\D|\b)"#
        ]
        for pattern in patterns {
            guard let match = firstMatch(pattern, in: title, options: [.caseInsensitive]),
                  match.count > 2,
                  let season = match[1].flatMap(Int32.init),
                  let episode = match[2].flatMap(Int32.init) else { continue }
            return (season, episode)
        }
        return nil
    }

    private static func matchesSmartFilter(
        _ title: String,
        enabled: Bool,
        previouslyMatchedEpisodes: Set<String>,
        settings: RSSRuleMatchSettings
    ) -> Bool {
        guard enabled else { return true }
        guard let episode = computeEpisodeName(title, patterns: settings.smartEpisodeFilters) else { return false }
        guard previouslyMatchedEpisodes.contains(episode) else { return true }
        guard settings.downloadRepacks else { return false }

        let isRepack = title.range(of: "REPACK", options: .caseInsensitive) != nil
        let isProper = title.range(of: "PROPER", options: .caseInsensitive) != nil
        guard isRepack || isProper else { return false }

        let suffix = (isRepack ? "-REPACK" : "") + (isProper ? "-PROPER" : "")
        let fullEpisode = episode + suffix
        return !previouslyMatchedEpisodes.contains(fullEpisode)
    }

    private static func computeEpisodeName(_ title: String, patterns: [String]) -> String? {
        let combined = #"(?:_|\b)(?:"# + patterns.joined(separator: "|") + #")(?:_|\b)"#
        guard let expression = try? NSRegularExpression(
            pattern: combined,
            options: [.caseInsensitive, .allowCommentsAndWhitespace]
        ) else { return nil }
        let range = NSRange(title.startIndex..., in: title)
        guard let match = expression.firstMatch(in: title, range: range), match.numberOfRanges > 1 else { return nil }

        var parts: [String] = []
        for index in 1..<match.numberOfRanges {
            guard let captureRange = Range(match.range(at: index), in: title) else { continue }
            let capture = String(title[captureRange])
            guard !capture.isEmpty else { continue }
            if let number = Int32(capture) { parts.append(String(number)) }
            else { parts.append(capture) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "x")
    }

    private static func firstMatch(
        _ pattern: String,
        in value: String,
        options: NSRegularExpression.Options
    ) -> [String?]? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options),
              let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return String(value[range])
        }
    }
}
