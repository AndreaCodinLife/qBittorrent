import AppKit
import RSSArticleSupport
import SwiftUI

struct RSSArticlePreview: View {
    let article: RSSArticle?
    let onOpenURL: (URL) -> Void
    @State private var loadedImages: [URL: NSImage] = [:]
    @State private var failedImageURLs = Set<URL>()

    private var previewContent: RSSArticlePreviewContent {
        guard let article else { return RSSArticlePreviewContent(htmlBody: "", imageURLs: []) }
        return RSSArticleMarkup.previewContent(article.description, baseURL: article.link)
    }

    private var imageLoadKey: String {
        previewContent.imageURLs.map(\.absoluteString).joined(separator: "\u{0}")
    }

    private static let imageSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = URLCache(
            memoryCapacity: 10 * 1024 * 1024,
            diskCapacity: 50 * 1024 * 1024,
            diskPath: "qBitX-RSS"
        )
        return URLSession(configuration: configuration)
    }()

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
                            Text(Self.attributedDescription(
                                article.description,
                                baseURL: article.link,
                                images: loadedImages,
                                failedImageURLs: failedImageURLs
                            ))
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
        .task(id: imageLoadKey) {
            await loadRemoteImages(previewContent.imageURLs)
        }
    }

    private func loadRemoteImages(_ urls: [URL]) async {
        let currentURLs = Set(urls)
        loadedImages = loadedImages.filter { currentURLs.contains($0.key) }
        failedImageURLs.formIntersection(currentURLs)

        for url in urls where loadedImages[url] == nil && !failedImageURLs.contains(url) {
            guard !Task.isCancelled else { return }
            do {
                var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 15)
                request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
                let (responseBytes, response) = try await Self.imageSession.bytes(for: request)
                guard !Task.isCancelled,
                      let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode),
                      let mimeType = httpResponse.mimeType?.lowercased(),
                      mimeType.hasPrefix("image/"),
                      mimeType != "image/svg+xml",
                      response.expectedContentLength <= 20 * 1024 * 1024
                else {
                    failedImageURLs.insert(url)
                    continue
                }
                var data = Data()
                var imageTooLarge = false
                for try await byte in responseBytes {
                    guard !Task.isCancelled else { return }
                    data.append(byte)
                    if data.count > 20 * 1024 * 1024 {
                        imageTooLarge = true
                        break
                    }
                }
                guard !imageTooLarge,
                      !Task.isCancelled,
                      let image = NSImage(data: data),
                      image.size.width > 0,
                      image.size.height > 0
                else {
                    failedImageURLs.insert(url)
                    continue
                }
                loadedImages[url] = image
            } catch {
                if !Task.isCancelled { failedImageURLs.insert(url) }
            }
        }
    }

    private static func attributedDescription(
        _ source: String,
        baseURL: String,
        images: [URL: NSImage],
        failedImageURLs: Set<URL>
    ) -> AttributedString {
        let content = RSSArticleMarkup.previewContent(source, baseURL: baseURL)
        let color = NSColor.labelColor.usingColorSpace(.deviceRGB) ?? .labelColor
        let foreground = String(
            format: "#%02x%02x%02x",
            Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255)
        )
        let html = "<html><head><meta charset=\"utf-8\"></head><body><div style=\"font-family: -apple-system; font-size: 13px; color: \(foreground);\">\(content.htmlBody)</div></body></html>"
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let imported = try? NSAttributedString(
            data: Data(html.utf8), options: options, documentAttributes: nil
        ) else {
            return AttributedString(plainText(from: source))
        }
        let result = NSMutableAttributedString(attributedString: imported)
        for (index, url) in content.imageURLs.enumerated() {
            let marker = "[QBITX_RSS_IMAGE_\(index)]"
            let replacement: NSAttributedString
            if let image = images[url] {
                let attachment = NSTextAttachment()
                attachment.image = image
                let maxDimension: CGFloat = 600
                let scale = min(1, maxDimension / max(image.size.width, image.size.height))
                let width = image.size.width * scale
                let height = image.size.height * scale
                attachment.bounds = CGRect(x: 0, y: -height, width: width, height: height)
                replacement = NSAttributedString(attachment: attachment)
            } else {
                replacement = NSAttributedString(string: failedImageURLs.contains(url) ? "[Image unavailable]" : "[Loading image…]")
            }
            var searchLocation = 0
            while searchLocation < result.length {
                let searchRange = NSRange(location: searchLocation, length: result.length - searchLocation)
                let markerRange = result.mutableString.range(of: marker, options: [], range: searchRange)
                guard markerRange.location != NSNotFound else { break }
                result.replaceCharacters(in: markerRange, with: replacement)
                searchLocation = markerRange.location + replacement.length
            }
        }
        return AttributedString(result)
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
