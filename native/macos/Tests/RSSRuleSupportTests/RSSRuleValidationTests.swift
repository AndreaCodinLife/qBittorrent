import Foundation
import Testing
@testable import RSSRuleSupport

struct RSSRuleValidationTests {
    @Test func validatesRegexOnlyWhenRegexModeIsEnabled() {
        #expect(RSSRuleValidation.regularExpressionError(for: "[", enabled: true) != nil)
        #expect(RSSRuleValidation.regularExpressionError(for: "episode.*", enabled: true) == nil)
        #expect(RSSRuleValidation.regularExpressionError(for: "[", enabled: false) == nil)
        #expect(RSSRuleValidation.regularExpressionError(for: "", enabled: true) == nil)
    }

    @Test func validatesEpisodeFilterSyntaxAndAllowsAnEmptyFilter() {
        #expect(RSSRuleValidation.isValidEpisodeFilter(""))
        #expect(RSSRuleValidation.isValidEpisodeFilter("1x2;8-15;5;30-;"))
        #expect(RSSRuleValidation.isValidEpisodeFilter("1x30-;"))
        #expect(!RSSRuleValidation.isValidEpisodeFilter("1x2;8-15"))
        #expect(!RSSRuleValidation.isValidEpisodeFilter("not an episode filter"))
    }

    @Test func parsesQbittorrentRFC2822LastMatchDates() {
        let date = RSSRuleValidation.lastMatchDate(from: "Tue, 02 Jan 2024 15:04:05 +0000")
        #expect(date != nil)
        if let date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            #expect(components.year == 2024)
            #expect(components.month == 1)
            #expect(components.day == 2)
            #expect(components.hour == 15)
            #expect(components.minute == 4)
            #expect(components.second == 5)
        }
        #expect(RSSRuleValidation.lastMatchDate(from: "unknown") == nil)
    }
}
