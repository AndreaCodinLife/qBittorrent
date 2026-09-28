import Foundation

public struct RSSArticlePreviewContent: Sendable {
    public let htmlBody: String
    public let imageURLs: [URL]

    public init(htmlBody: String, imageURLs: [URL]) {
        self.htmlBody = htmlBody
        self.imageURLs = imageURLs
    }
}

public enum RSSArticleMarkup {
    public static func sanitizedHTMLBody(_ source: String, baseURL: String) -> String {
        previewContent(source, baseURL: baseURL).htmlBody
    }

    public static func previewContent(_ source: String, baseURL: String) -> RSSArticlePreviewContent {
        var html = looksLikeHTML(source) ? source : escapedPlainText(source)
        var imageURLs: [URL] = []
        html = replacingImageTags(in: html, baseURL: baseURL, imageURLs: &imageURLs)

        for tag in ["script", "style", "iframe", "object", "embed", "form", "svg", "canvas", "video", "audio", "noscript", "template"] {
            html = replacing(#"(?is)<\s*\#(tag)\b[^>]*>.*?<\s*/\s*\#(tag)\s*>"#, in: html, with: "")
            html = replacing(#"(?is)<\s*\#(tag)\b[^>]*/?>"#, in: html, with: "")
        }
        html = replacing(#"(?is)<\s*(link|meta|base)\b[^>]*>"#, in: html, with: "")
        html = sanitizingInlineStyles(in: html)
        html = replacing(
            #"(?is)\s+(on[a-z0-9_-]*|src|srcset|poster|background|data|action|formaction)\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#,
            in: html,
            with: ""
        )
        return RSSArticlePreviewContent(htmlBody: sanitizeLinks(in: html, baseURL: baseURL), imageURLs: imageURLs)
    }

    private static func replacingImageTags(in html: String, baseURL: String, imageURLs: inout [URL]) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"(?is)<\s*img\b[^>]*>"#) else { return html }
        let matches = expression.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var result = html
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result) else { continue }
            let tag = String(result[matchRange])
            let srcPattern = #"(?is)\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
            guard let srcExpression = try? NSRegularExpression(pattern: srcPattern),
                  let srcMatch = srcExpression.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag))
            else {
                result.replaceSubrange(matchRange, with: "")
                continue
            }
            let source = (1...3).compactMap { index -> String? in
                guard let range = Range(srcMatch.range(at: index), in: tag) else { return nil }
                return String(tag[range])
            }.first ?? ""
            let decodedSource = source
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
            guard let imageURL = URL(string: decodedSource, relativeTo: URL(string: baseURL))?.absoluteURL,
                  isAllowedImage(imageURL)
            else {
                result.replaceSubrange(matchRange, with: "")
                continue
            }
            let imageIndex: Int
            if let existingIndex = imageURLs.firstIndex(of: imageURL) {
                imageIndex = existingIndex
            } else {
                imageIndex = imageURLs.count
                imageURLs.append(imageURL)
            }
            result.replaceSubrange(matchRange, with: "[QBITX_RSS_IMAGE_\(imageIndex)]")
        }
        return result
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
            let style = safeStyleAttribute(in: openTag).map { " \($0)" } ?? ""
            result.replaceSubrange(matchRange, with: "<a href=\"\(escapedHref)\"\(style)>")
        }
        return result
    }

    private static func sanitizingInlineStyles(in html: String) -> String {
        guard let tagExpression = try? NSRegularExpression(pattern: #"(?is)<[^>]+>"#),
              let styleExpression = try? NSRegularExpression(pattern: #"(?is)\s+style\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#)
        else { return html }
        let tags = tagExpression.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var result = html
        for tagMatch in tags.reversed() {
            guard let tagRange = Range(tagMatch.range, in: result) else { continue }
            var tag = String(result[tagRange])
            guard let styleMatch = styleExpression.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
                  let attributeRange = Range(styleMatch.range, in: tag),
                  let valueRange = Range(styleMatch.range(at: 1), in: tag)
            else { continue }
            let rawValue = String(tag[valueRange])
            let value = rawValue.count >= 2 ? String(rawValue.dropFirst().dropLast()) : rawValue
            let safeDeclarations = value.split(separator: ";").compactMap { declaration -> String? in
                guard let colon = declaration.firstIndex(of: ":") else { return nil }
                let property = declaration[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let cssValue = declaration[declaration.index(after: colon)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard isSafeCSSValue(cssValue, for: property) else { return nil }
                return "\(property): \(cssValue)"
            }
            let replacement = safeDeclarations.isEmpty ? "" : " style=\"\(safeDeclarations.joined(separator: "; "))\""
            tag.replaceSubrange(attributeRange, with: replacement)
            result.replaceSubrange(tagRange, with: tag)
        }
        return result
    }

    private static func safeStyleAttribute(in tag: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: #"(?is)\s+style\s*=\s*"([^"]*)""#),
              let match = expression.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let valueRange = Range(match.range(at: 1), in: tag)
        else { return nil }
        let value = String(tag[valueRange])
        let declarations = value.split(separator: ";").compactMap { declaration -> String? in
            guard let colon = declaration.firstIndex(of: ":") else { return nil }
            let property = declaration[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let cssValue = declaration[declaration.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard isSafeCSSValue(cssValue, for: property) else { return nil }
            return "\(property): \(cssValue)"
        }
        return declarations.isEmpty ? nil : "style=\"\(declarations.joined(separator: "; "))\""
    }

    private static func isSafeCSSValue(_ value: String, for property: String) -> Bool {
        let normalized = value.lowercased()
        switch property {
        case "color", "background-color":
            return normalized.range(of: #"^(?:[a-z]{1,20}|#[0-9a-f]{3,8}|rgba?\(\s*[0-9]{1,3}\s*,\s*[0-9]{1,3}\s*,\s*[0-9]{1,3}(?:\s*,\s*(?:0|1|0?\.\d+))?\s*\)|transparent)$"#, options: .regularExpression) != nil
        case "font-size", "line-height", "text-indent", "letter-spacing":
            return normalized.range(of: #"^(?:[0-9]{1,2}(?:\.\d+)?)(?:px|pt|em|rem|%)?$|^(?:xx-small|x-small|small|medium|large|x-large|xx-large|smaller|larger)$"#, options: .regularExpression) != nil
        case "font-weight":
            return ["normal", "bold", "bolder", "lighter", "100", "200", "300", "400", "500", "600", "700", "800", "900"].contains(normalized)
        case "font-style":
            return ["normal", "italic", "oblique"].contains(normalized)
        case "text-decoration":
            return ["none", "underline", "overline", "line-through"].contains(normalized)
        case "text-align":
            return ["left", "right", "center", "justify", "start", "end"].contains(normalized)
        case "white-space":
            return ["normal", "pre", "pre-wrap", "pre-line", "nowrap"].contains(normalized)
        case "vertical-align":
            return ["baseline", "sub", "super", "text-top", "text-bottom", "middle", "top", "bottom"].contains(normalized)
        case "font-family":
            return value.count <= 120 && value.range(of: #"^[A-Za-z0-9 ,_'\-]+$"#, options: .regularExpression) != nil
        default:
            return false
        }
    }

    private static func isAllowedLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "magnet" { return true }
        return ["http", "https"].contains(scheme) && url.host != nil
    }

    private static func isAllowedImage(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil,
              url.user == nil,
              url.password == nil
        else { return false }
        return true
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
            (#"(?i)\[img\](.*?)\[/img\]"#, "<img src=\"$1\">"),
            (#"(?i)\[b\](.*?)\[/b\]"#, "<strong>$1</strong>"),
            (#"(?i)\[i\](.*?)\[/i\]"#, "<em>$1</em>"),
            (#"(?i)\[u\](.*?)\[/u\]"#, "<u>$1</u>"),
            (#"(?i)\[s\](.*?)\[/s\]"#, "<s>$1</s>")
        ] {
            text = replacing(pattern, in: text, with: replacement)
        }
        text = replacingBBCodeTags(#"(?is)\[url=(.*?)\](.*?)\[/url\]"#, in: text) { value, body in
            let url = value.replacingOccurrences(of: "&quot;", with: "")
            return "<a href=\"\(url)\">\(body)</a>"
        }
        text = replacingBBCodeTags(#"(?is)\[color=(.*?)\](.*?)\[/color\]"#, in: text) { value, body in
            let color = value.replacingOccurrences(of: "&quot;", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard color.range(of: #"^(?:[A-Za-z]{1,20}|#[0-9A-Fa-f]{3,8})$"#, options: .regularExpression) != nil else { return body }
            return "<font color=\"\(color)\">\(body)</font>"
        }
        text = replacingBBCodeTags(#"(?is)\[size=(.*?)\](.*?)\[/size\]"#, in: text) { value, body in
            let sizeText = value.replacingOccurrences(of: "&quot;", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let size = Int(sizeText) else { return body }
            return "<font size=\"\(min(max(size, 1), 72))\">\(body)</font>"
        }
        return "<pre>\(text)</pre>"
    }

    private static func replacingBBCodeTags(
        _ pattern: String,
        in source: String,
        makeMarkup: (String, String) -> String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return source }
        let matches = expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
        var result = source
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result),
                  let valueRange = Range(match.range(at: 1), in: result),
                  let bodyRange = Range(match.range(at: 2), in: result)
            else { continue }
            let value = String(result[valueRange])
            let body = String(result[bodyRange])
            result.replaceSubrange(matchRange, with: makeMarkup(value, body))
        }
        return result
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
