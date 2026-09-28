import Foundation

public enum RSSArticleMarkup {
    public static func sanitizedHTMLBody(_ source: String, baseURL: String) -> String {
        var html = looksLikeHTML(source) ? source : escapedPlainText(source)

        for tag in ["script", "style", "iframe", "object", "embed", "form", "svg", "canvas", "video", "audio", "noscript", "template"] {
            html = replacing(#"(?is)<\s*\#(tag)\b[^>]*>.*?<\s*/\s*\#(tag)\s*>"#, in: html, with: "")
            html = replacing(#"(?is)<\s*\#(tag)\b[^>]*/?>"#, in: html, with: "")
        }
        html = replacing(#"(?is)<\s*(img|link|meta|base)\b[^>]*>"#, in: html, with: "")
        html = replacing(
            #"(?is)\s+(on[a-z0-9_-]*|style|src|srcset|poster|background|data|action|formaction)\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#,
            in: html,
            with: ""
        )
        return sanitizeLinks(in: html, baseURL: baseURL)
    }

    private static func sanitizeLinks(in html: String, baseURL: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"(?is)<a\b[^>]*>"#) else { return html }
        let matches = expression.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var result = html
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result) else { continue }
            let openTag = String(result[matchRange])
            let hrefPattern = #"(?is)\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
            guard let hrefExpression = try? NSRegularExpression(pattern: hrefPattern),
                  let hrefMatch = hrefExpression.firstMatch(in: openTag, range: NSRange(openTag.startIndex..., in: openTag))
            else {
                result.replaceSubrange(matchRange, with: "<a>")
                continue
            }
            let href = (1...3).compactMap { index -> String? in
                guard let range = Range(hrefMatch.range(at: index), in: openTag) else { return nil }
                return String(openTag[range])
            }.first ?? ""
            let decodedHref = href
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
            let resolved = URL(string: decodedHref, relativeTo: URL(string: baseURL))?.absoluteURL
            guard let resolved, isAllowedLink(resolved) else {
                result.replaceSubrange(matchRange, with: "<a>")
                continue
            }
            let escapedHref = resolved.absoluteString
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
            result.replaceSubrange(matchRange, with: "<a href=\"\(escapedHref)\">")
        }
        return result
    }

    private static func isAllowedLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "magnet" { return true }
        return ["http", "https"].contains(scheme) && url.host != nil
    }

    private static func looksLikeHTML(_ string: String) -> Bool {
        string.range(of: #"<\s*[a-z][^>]*>"#, options: .regularExpression.union(.caseInsensitive)) != nil
    }

    private static func escapedPlainText(_ source: String) -> String {
        var text = source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        for (pattern, replacement) in [
            (#"(?i)\[b\](.*?)\[/b\]"#, "<strong>$1</strong>"),
            (#"(?i)\[i\](.*?)\[/i\]"#, "<em>$1</em>"),
            (#"(?i)\[u\](.*?)\[/u\]"#, "<u>$1</u>"),
            (#"(?i)\[s\](.*?)\[/s\]"#, "<s>$1</s>")
        ] {
            text = replacing(pattern, in: text, with: replacement)
        }
        return "<pre>\(text)</pre>"
    }

    private static func replacing(_ pattern: String, in source: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return source }
        return expression.stringByReplacingMatches(
            in: source,
            range: NSRange(source.startIndex..., in: source),
            withTemplate: replacement
        )
    }
}
