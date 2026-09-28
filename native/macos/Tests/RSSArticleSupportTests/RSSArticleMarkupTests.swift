import Foundation
import Testing
@testable import RSSArticleSupport

struct RSSArticleMarkupTests {
    @Test func stripsActiveAndRemoteContentButKeepsArticleText() {
        let html = #"<p onclick="run()">News<img src="https://tracker.example/pixel.gif" onerror="run()"><script>alert(1)</script><a href="javascript:alert(1)">unsafe</a><a href="https://news.example/story?a=1&amp;b=2" style="color:red">safe</a></p>"#

        let sanitized = RSSArticleMarkup.sanitizedHTMLBody(html, baseURL: "https://feed.example/")

        #expect(sanitized.contains("News"))
        #expect(sanitized.contains("unsafe"))
        #expect(sanitized.contains("safe"))
        #expect(sanitized.contains(#"href="https://news.example/story?a=1&amp;b=2""#))
        #expect(!sanitized.localizedCaseInsensitiveContains("script"))
        #expect(!sanitized.localizedCaseInsensitiveContains("javascript:"))
        #expect(!sanitized.localizedCaseInsensitiveContains("tracker.example"))
        #expect(!sanitized.localizedCaseInsensitiveContains("onclick"))
        #expect(!sanitized.localizedCaseInsensitiveContains("onerror"))
        #expect(!sanitized.localizedCaseInsensitiveContains("style="))
    }

    @Test func resolvesRelativeArticleLinksAgainstTheArticleURL() {
        let html = #"<a href="../story?id=7&amp;view=full">Read story</a>"#

        let sanitized = RSSArticleMarkup.sanitizedHTMLBody(html, baseURL: "https://feed.example/news/latest")

        #expect(sanitized.contains(#"href="https://feed.example/story?id=7&amp;view=full""#))
    }

    @Test func escapesPlainDescriptionsAndPreservesBasicBBCode() {
        let sanitized = RSSArticleMarkup.sanitizedHTMLBody("2 < 3 & [b]bold[/b]\nsecond line", baseURL: "https://feed.example/")

        #expect(sanitized.contains("2 &lt; 3"))
        #expect(sanitized.contains("&amp;"))
        #expect(sanitized.contains("<strong>bold</strong>"))
        #expect(sanitized.contains("\nsecond line"))
    }
}
