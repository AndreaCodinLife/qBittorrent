import Foundation
import Testing
@testable import RSSRuleSupport

struct RSSRuleMatcherTests {
    @Test func appliesQbittorrentWildcardAndExclusionSemantics() {
        let candidates = [
            candidate("A.Show.Release.S01E02.1080p", feed: "Series"),
            candidate("A.Show.Sample.S01E02.1080p", feed: "Series"),
            candidate("A.Show.Release.S01E02.720p", feed: "Series"),
            candidate("A.Different.Release.S01E02.1080p", feed: "Movies")
        ]

        let groups = RSSRuleMatcher.matchingArticles(
            candidates,
            rule: rule(feeds: ["series"], mustContain: "show 1080p|alternate", mustNotContain: "sample")
        )

        #expect(groups == [RSSRuleMatchGroup(feedTitle: "Series", titles: ["A.Show.Release.S01E02.1080p"])])
    }

    @Test func appliesRegexModeCaseInsensitively() {
        let candidates = [candidate("Show.S01E02.1080p", feed: "Series"), candidate("Show.S01E03.1080p", feed: "Series")]

        let groups = RSSRuleMatcher.matchingArticles(
            candidates,
            rule: rule(feeds: ["series"], mustContain: #"s01e0[2-3]"#, mustNotContain: #"720p|sample"#, useRegex: true)
        )

        #expect(groups.flatMap(\.titles) == ["Show.S01E02.1080p", "Show.S01E03.1080p"])
    }

    @Test func appliesSeasonEpisodeListsRangesAndLaterSeasonRanges() {
        let candidates = [
            candidate("Show.S01E02.mkv", feed: "Series"),
            candidate("Show.1x10.mkv", feed: "Series"),
            candidate("Show.S02E01.mkv", feed: "Series"),
            candidate("Show.S01E29.mkv", feed: "Series"),
            candidate("Show.S01E11.mkv", feed: "Series")
        ]

        let groups = RSSRuleMatcher.matchingArticles(
            candidates,
            rule: rule(feeds: ["series"], episodeFilter: "1x2;8-10;30-;")
        )

        #expect(groups.flatMap(\.titles) == ["Show.1x10.mkv", "Show.S01E02.mkv", "Show.S02E01.mkv"])
    }

    @Test func ignoresOldMatchesAndHonorsSmartEpisodeRepackPreference() {
        let candidates = [
            candidate("Show.S01E02.mkv", feed: "Series", date: date("2024-01-08T00:00:00Z")),
            candidate("Show.S01E02.REPACK.mkv", feed: "Series", date: date("2024-01-08T00:00:00Z")),
            candidate("Show.S01E03.mkv", feed: "Series", date: date("2024-01-06T00:00:00Z"))
        ]
        let definition = rule(
            feeds: ["series"],
            smartFilter: true,
            ignoreDays: 5,
            lastMatch: "Tue, 02 Jan 2024 00:00:00 +0000",
            previouslyMatched: ["1x2"]
        )

        let withoutRepacks = RSSRuleMatcher.matchingArticles(
            candidates,
            rule: definition,
            settings: RSSRuleMatchSettings(
                smartEpisodeFilters: RSSRuleMatchSettings.qBittorrentDefaults.smartEpisodeFilters,
                downloadRepacks: false
            )
        )
        let withRepacks = RSSRuleMatcher.matchingArticles(candidates, rule: definition)

        #expect(withoutRepacks.isEmpty)
        #expect(withRepacks.flatMap(\.titles) == ["Show.S01E02.REPACK.mkv"])
    }

    private func rule(
        feeds: Set<String>,
        mustContain: String = "",
        mustNotContain: String = "",
        useRegex: Bool = false,
        episodeFilter: String = "",
        smartFilter: Bool = false,
        ignoreDays: Int = 0,
        lastMatch: String = "",
        previouslyMatched: Set<String> = []
    ) -> RSSRuleMatchDefinition {
        RSSRuleMatchDefinition(
            affectedFeedURLs: feeds,
            mustContain: mustContain,
            mustNotContain: mustNotContain,
            useRegex: useRegex,
            episodeFilter: episodeFilter,
            smartFilter: smartFilter,
            ignoreDays: ignoreDays,
            lastMatch: lastMatch,
            previouslyMatchedEpisodes: previouslyMatched
        )
    }

    private func candidate(_ title: String, feed: String, date: Date? = nil) -> RSSRuleMatchCandidate {
        RSSRuleMatchCandidate(feedURL: feed.lowercased(), feedTitle: feed, title: title, date: date)
    }

    private func date(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}
