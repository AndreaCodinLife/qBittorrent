import Foundation
import Testing
@testable import RSSArticleSupport

struct RSSArticleMarkupTests {
    @Test func stripsActiveContentAndExtractsSafeImages() {
        let html = #"<p onclick="run()">News<img src="https://tracker.example/pixel.gif" onerror="run()"><script>alert(1)</script><a href="javascript:alert(1)">unsafe</a><a href="https://news.example/story?a=1&amp;b=2" style="color:red">safe</a></p>"#

        let content = RSSArticleMarkup.previewContent(html, baseURL: "https://feed.example/")
        let sanitized = content.htmlBody

        #expect(sanitized.contains("News"))
        #expect(sanitized.contains("unsafe"))
        #expect(sanitized.contains("safe"))
        #expect(sanitized.contains("[QBITX_RSS_IMAGE_0]"))
        #expect(sanitized.contains(#"href="https://news.example/story?a=1&amp;b=2""#))
        #expect(content.imageURLs == [URL(string: "https://tracker.example/pixel.gif")!])
        #expect(!sanitized.localizedCaseInsensitiveContains("script"))
        #expect(!sanitized.localizedCaseInsensitiveContains("javascript:"))
        #expect(!sanitized.localizedCaseInsensitiveContains("tracker.example"))
        #expect(!sanitized.localizedCaseInsensitiveContains("onclick"))
        #expect(!sanitized.localizedCaseInsensitiveContains("onerror"))
        #expect(sanitized.contains(#"style="color: red""#))
    }

    @Test func keepsSafeInlineStylesAndStripsResourceAndLayoutCSS() {
        let html = #"<p style="color:#123456; font-size:18px; background-image:url(https://tracker.example/pixel); position:fixed">Styled</p>"#

        let sanitized = RSSArticleMarkup.sanitizedHTMLBody(html, baseURL: "https://feed.example/")

        #expect(sanitized.contains(#"color: #123456"#))
        #expect(sanitized.contains(#"font-size: 18px"#))
        #expect(!sanitized.contains("background-image"))
        #expect(!sanitized.contains("tracker.example"))
        #expect(!sanitized.contains("position"))
    }

    @Test func resolvesRelativeImageURLsAndRejectsNonHTTPImages() {
        let html = #"<img src="../images/cover.jpg"><img src="file:///etc/passwd"><img src="data:image/png;base64,AAAA">"#

        let content = RSSArticleMarkup.previewContent(html, baseURL: "https://feed.example/news/latest")

        #expect(content.imageURLs == [URL(string: "https://feed.example/images/cover.jpg")!])
        #expect(content.htmlBody.contains("[QBITX_RSS_IMAGE_0]"))
        #expect(!content.htmlBody.contains("file:"))
        #expect(!content.htmlBody.contains("data:image"))
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

    @Test func convertsBBCodeImagesIntoSafeImageReferences() {
        let content = RSSArticleMarkup.previewContent("[img]https://cdn.example/cover.png[/img]", baseURL: "https://feed.example/")

        #expect(content.imageURLs == [URL(string: "https://cdn.example/cover.png")!])
        #expect(content.htmlBody.contains("[QBITX_RSS_IMAGE_0]"))
    }

    @Test func convertsSafeBBCodeLinksColorsAndSizes() {
        let content = RSSArticleMarkup.sanitizedHTMLBody(
            #"[url="https://news.example/story?a=1&b=2"]Read[/url] [color=#ff0099]Pink[/color] [size=18]Large[/size] [color=red;url(https://tracker.example)]Unsafe[/color]"#,
            baseURL: "https://feed.example/"
        )

        #expect(content.contains(#"href="https://news.example/story?a=1&amp;b=2""#))
        #expect(content.contains(##"<font color="#ff0099">Pink</font>"##))
        #expect(content.contains(#"<font size="18">Large</font>"#))
        #expect(!content.contains("url(https://tracker.example)"))
        #expect(content.contains("Unsafe"))
    }
}
