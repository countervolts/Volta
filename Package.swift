// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "music",
    platforms: [
        .iOS("17.0"),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "music",
            targets: ["music"]
        ),
    ],
    targets: [
        .target(
            name: "music",
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                // swift 5 mode keeps strict concurrency from blocking the build
                // while we still use async/await throughout.
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
