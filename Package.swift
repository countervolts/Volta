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
    ],
    targets: [
        .target(
            name: "Volta",
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)