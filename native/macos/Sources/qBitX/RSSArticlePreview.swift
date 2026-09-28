import AppKit
import ImageIO
import RSSArticleSupport
import SwiftUI
import WebKit

private struct RSSImageLoadResult: Sendable {
    let url: URL
    let image: RSSLoadedImage?
}

private struct RSSLoadedImage: Sendable {
    let data: Data
    let mimeType: String
}

private enum RSSPreviewImageDecoder {
    static func downsample(_ image: RSSLoadedImage) -> RSSLoadedImage? {
        guard let source = CGImageSourceCreateWithData(image.data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0,
              width <= 100_000,
              height <= 100_000,
              Int64(width) * Int64(height) <= 40_000_000
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 600,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return RSSLoadedImage(data: output as Data, mimeType: "image/png")
    }
}

private actor RSSRemoteImageLoader {
    static let shared = RSSRemoteImageLoader()

    private let session: URLSession

    private init() {
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
        session = URLSession(configuration: configuration)
    }

    func load(_ url: URL) async -> RSSLoadedImage? {
        do {
            var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 15)
            request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            let (responseBytes, response) = try await session.bytes(for: request)
            let mimeType = response.mimeType?.lowercased() ?? ""
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  Self.allowedImageMIMETypes.contains(mimeType),
                  response.expectedContentLength <= 20 * 1024 * 1024
            else { return nil }

            var data = Data()
            for try await byte in responseBytes {
                guard !Task.isCancelled else { return nil }
                data.append(byte)
                guard data.count <= 20 * 1024 * 1024 else { return nil }
            }
            return RSSLoadedImage(data: data, mimeType: mimeType)
        } catch {
            return nil
        }
    }

    private static let allowedImageMIMETypes: Set<String> = [
        "image/avif", "image/apng", "image/bmp", "image/gif", "image/jpeg", "image/png", "image/tiff", "image/webp"
    ]
}

struct RSSArticlePreview: View {
    let article: RSSArticle?
    let onOpenURL: (URL) -> Void
    @State private var loadedImages: [URL: RSSLoadedImage] = [:]
    @State private var failedImageURLs = Set<URL>()

    private var previewContent: RSSArticlePreviewContent {
        guard let article else { return RSSArticlePreviewContent(htmlBody: "", imageURLs: []) }
        return RSSArticleMarkup.previewContent(article.description, baseURL: article.link)
    }

    private var imageLoadKey: String {
        previewContent.imageURLs.map(\.absoluteString).joined(separator: "\u{0}")
    }

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
                        RSSArticleHTMLView(
                            html: Self.renderedHTML(
                                previewContent,
                                images: loadedImages,
                                failedImageURLs: failedImageURLs
                            ),
                            onOpenURL: onOpenURL
                        )
                        .accessibilityLabel("RSS article content")
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

        let urlsToLoad = urls.filter { loadedImages[$0] == nil && !failedImageURLs.contains($0) }
        var newlyLoadedImages: [URL: RSSLoadedImage] = [:]
        var newlyFailedImageURLs = Set<URL>()
        await withTaskGroup(of: RSSImageLoadResult.self) { group in
            let initialLoadCount = min(3, urlsToLoad.count)
            for url in urlsToLoad.prefix(initialLoadCount) {
                group.addTask {
                    let loadedImage = await RSSRemoteImageLoader.shared.load(url)
                    let previewImage = loadedImage.flatMap(RSSPreviewImageDecoder.downsample)
                    return RSSImageLoadResult(url: url, image: previewImage)
                }
            }
            var nextURLIndex = initialLoadCount
            while let result = await group.next() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                if nextURLIndex < urlsToLoad.count {
                    let url = urlsToLoad[nextURLIndex]
                    nextURLIndex += 1
                    group.addTask {
                        let loadedImage = await RSSRemoteImageLoader.shared.load(url)
                        let previewImage = loadedImage.flatMap(RSSPreviewImageDecoder.downsample)
                        return RSSImageLoadResult(url: url, image: previewImage)
                    }
                }
                guard let loadedImage = result.image else {
                    newlyFailedImageURLs.insert(result.url)
                    continue
                }
                newlyLoadedImages[result.url] = loadedImage
            }
        }
        guard !Task.isCancelled else { return }
        loadedImages.merge(newlyLoadedImages) { _, updated in updated }
        failedImageURLs.formUnion(newlyFailedImageURLs)
    }

    private static func renderedHTML(
        _ content: RSSArticlePreviewContent,
        images: [URL: RSSLoadedImage],
        failedImageURLs: Set<URL>
    ) -> String {
        let color = NSColor.labelColor.usingColorSpace(.deviceRGB) ?? .labelColor
        let foreground = String(
            format: "#%02x%02x%02x",
            Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255)
        )
        var body = content.htmlBody
        for (index, url) in content.imageURLs.enumerated() {
            let marker = "[QBITX_RSS_IMAGE_\(index)]"
            let replacement: String
            if let image = images[url] {
                replacement = "<img src=\"data:\(image.mimeType);base64,\(image.data.base64EncodedString())\" alt=\"Article image\" style=\"max-width:100%;max-height:600px;height:auto\">"
            } else {
                replacement = failedImageURLs.contains(url) ? "[Image unavailable]" : "[Loading image…]"
            }
            body = body.replacingOccurrences(of: marker, with: replacement)
        }
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'none'; connect-src 'none'; object-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html { color-scheme: light dark; }
            body { background: transparent; color: \(foreground); font-family: -apple-system, sans-serif; font-size: 13px; line-height: 1.45; margin: 0; padding: 16px; overflow-wrap: anywhere; }
            img { max-width: 100%; max-height: 600px; height: auto; }
            pre { white-space: pre-wrap; overflow-wrap: anywhere; }
            table { max-width: 100%; }
          </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    private static func safeURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "magnet"].contains(scheme),
              scheme == "magnet" || url.host != nil
        else { return nil }
        return url
    }
}

private struct RSSArticleHTMLView: NSViewRepresentable {
    let html: String
    let onOpenURL: (URL) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = .clear
        context.coordinator.load(html, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onOpenURL = onOpenURL
        context.coordinator.load(html, in: webView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenURL: onOpenURL)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var onOpenURL: (URL) -> Void
        private var currentHTML = ""

        init(onOpenURL: @escaping (URL) -> Void) {
            self.onOpenURL = onOpenURL
        }

        func load(_ html: String, in webView: WKWebView) {
            guard html != currentHTML else { return }
            currentHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated else {
                decisionHandler(.allow)
                return
            }
            if let url = navigationAction.request.url, Self.isAllowedLink(url) {
                onOpenURL(url)
            }
            decisionHandler(.cancel)
        }

        private static func isAllowedLink(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else { return false }
            if scheme == "magnet" { return true }
            return ["http", "https"].contains(scheme) && url.host != nil
        }
    }
}
