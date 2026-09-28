// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "qBitX",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "qBitX", targets: ["qBitX"])
    ],
    targets: [
        .target(name: "TorrentSourceFileSupport"),
        .target(name: "QBitXThemeSupport"),
        .executableTarget(name: "qBitX", dependencies: ["TorrentSourceFileSupport", "QBitXThemeSupport"]),
        .testTarget(name: "TorrentSourceFileSupportTests", dependencies: ["TorrentSourceFileSupport"]),
        .testTarget(name: "QBitXThemeSupportTests", dependencies: ["QBitXThemeSupport"])
    ]
)
