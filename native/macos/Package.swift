// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "qBitX",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "qBitX", targets: ["qBitX"]),
        .executable(name: "qBitXWidget", targets: ["qBitXWidget"]),
        .library(name: "QBitXWidgetSupport", targets: ["QBitXWidgetSupport"])
    ],
    targets: [
        .target(name: "TorrentSourceFileSupport"),
        .target(name: "TorrentLinkInput"),
        .target(name: "RSSArticleSupport"),
        .target(name: "RSSRuleSupport"),
        .target(name: "WebAPICompatibility"),
        .target(name: "QBitXThemeSupport"),
        .target(name: "QBitXWidgetSupport"),
        .executableTarget(name: "qBitX", dependencies: ["TorrentSourceFileSupport", "TorrentLinkInput", "RSSArticleSupport", "RSSRuleSupport", "WebAPICompatibility", "QBitXThemeSupport", "QBitXWidgetSupport"]),
        .executableTarget(name: "qBitXWidget", dependencies: ["QBitXWidgetSupport"]),
        .testTarget(name: "TorrentSourceFileSupportTests", dependencies: ["TorrentSourceFileSupport"]),
        .testTarget(name: "TorrentLinkInputTests", dependencies: ["TorrentLinkInput"]),
        .testTarget(name: "RSSArticleSupportTests", dependencies: ["RSSArticleSupport"]),
        .testTarget(name: "RSSRuleSupportTests", dependencies: ["RSSRuleSupport"]),
        .testTarget(name: "WebAPICompatibilityTests", dependencies: ["WebAPICompatibility"]),
        .testTarget(name: "QBitXThemeSupportTests", dependencies: ["QBitXThemeSupport"]),
        .testTarget(name: "qBitXTests", dependencies: ["qBitX"])
    ]
)
