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
        .executableTarget(name: "qBitX", dependencies: ["TorrentSourceFileSupport"]),
        .testTarget(name: "TorrentSourceFileSupportTests", dependencies: ["TorrentSourceFileSupport"])
    ]
)
