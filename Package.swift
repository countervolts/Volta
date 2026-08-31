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
    dependencies: [
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", from: "9.26.0"),
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
            dependencies: [
                "VoltaLiveActivitySupport",
                .product(name: "Sentry-Dynamic", package: "sentry-cocoa"),
            ],
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
