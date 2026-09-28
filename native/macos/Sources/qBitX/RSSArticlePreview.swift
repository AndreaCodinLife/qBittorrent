import AppKit
import RSSArticleSupport
import SwiftUI

struct RSSArticlePreview: View {
    let article: RSSArticle?
    let onOpenURL: (URL) -> Void

    var body: some View {
        Group {
            if let article {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(article.title)
                            .font(.title3.weight(.semibold))
                            .textSelection(.enabled)
                        HStack(spacing: 8) {
                            Text(article.feedTitle)
                            if !article.author.isEmpty { Text("·"); Text(article.author) }
                            if !article.date.isEmpty { Text("·"); Text(article.date) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if let url = Self.safeURL(article.link) {
                            Button {
                                onOpenURL(url)
                            } label: {
                                Label("Open Article", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.link)
                        }
                    }
                    .padding(16)
                    Divider()
                    if article.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView("No Article Description", systemImage: "text.alignleft")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            Text(Self.attributedDescription(article.description, baseURL: article.link))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(16)
                        }
                        .environment(\.openURL, OpenURLAction { url in
                            onOpenURL(url)
                            return .handled
                        })
                    }
                }
            } else {
                ContentUnavailableView("No Article Selected", systemImage: "newspaper", description: Text("Select an article to preview its details."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func attributedDescription(_ source: String, baseURL: String) -> AttributedString {
        let preparedBody = RSSArticleMarkup.sanitizedHTMLBody(source, baseURL: baseURL)
        let color = NSColor.labelColor.usingColorSpace(.deviceRGB) ?? .labelColor
        let foreground = String(
            format: "#%02x%02x%02x",
            Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255)
        )
        let html = "<html><head><meta charset=\"utf-8\"></head><body><div style=\"font-family: -apple-system; font-size: 13px; color: \(foreground);\">\(preparedBody)</div></body></html>"
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let imported = try? NSAttributedString(
            data: Data(html.utf8), options: options, documentAttributes: nil
        ) else {
            return AttributedString(plainText(from: source))
        }
        return AttributedString(imported)
    }

    private static func safeURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "magnet"].contains(scheme),
              scheme == "magnet" || url.host != nil
        else { return nil }
        return url
    }

    private static func plainText(from source: String) -> String {
        let tagsRemoved = replacing(#"(?is)<[^>]+>"#, in: source, with: " ")
        return tagsRemoved
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func replacing(_ pattern: String, in source: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return source }
        let range = NSRange(source.startIndex..., in: source)
        return expression.stringByReplacingMatches(in: source, range: range, withTemplate: replacement)
    }
}
