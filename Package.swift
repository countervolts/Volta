// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Volta",
    platforms: [
        .iOS("17.0"),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Volta",
            targets: ["Volta"]
        ),
    ],
    targets: [
        .target(
            name: "Volta",
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                // swift 5 mode keeps strict concurrency from blocking the build
                // while we still use async/await throughout.
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-platform_version",
                    "-Xlinker", "ios",
                    "-Xlinker", "17.0",
                    "-Xlinker", "26.5",
                ]),
            ]
        ),
    ]
)
