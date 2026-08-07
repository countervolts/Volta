// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Volta",
    platforms: [
        .iOS("16.0"),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Volta",
            targets: ["Volta"]
        ),
        .library(
            name: "VoltaLiveLyricsWidget",
            targets: ["VoltaLiveLyricsWidget"]
        ),
    ],
    targets: [
        .target(
            name: "VoltaLiveActivitySupport",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .target(
            name: "Volta",
            dependencies: ["VoltaLiveActivitySupport"],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-platform_version",
                    "-Xlinker", "ios",
                    "-Xlinker", "16.0",
                    "-Xlinker", "26.5",
                ], .when(platforms: [.iOS])),
            ]
        ),
        .target(
            name: "VoltaLiveLyricsWidget",
            dependencies: ["VoltaLiveActivitySupport"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "VoltaTests",
            dependencies: ["Volta"]
        ),
    ]
)
