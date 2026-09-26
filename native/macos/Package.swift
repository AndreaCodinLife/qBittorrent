// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "qBitX",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "qBitX", targets: ["qBitX"])
    ],
    targets: [
        .executableTarget(name: "qBitX")
    ]
)
