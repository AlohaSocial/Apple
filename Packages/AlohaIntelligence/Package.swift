// swift-tools-version: 6.2
// SPDX-License-Identifier: MIT

import PackageDescription

let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    // docs/12 §1: a warning fails the build, in every package.
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "AlohaIntelligence",
    defaultLocalization: "en",
    platforms: [.iOS("27.0"), .macOS("27.0"), .visionOS("27.0"), .watchOS("27.0"), .tvOS("27.0")],
    products: [
        .library(name: "AlohaIntelligence", targets: ["AlohaIntelligence"])
    ],
    dependencies: [
        .package(path: "../AlohaModels"),
        .package(path: "../AlohaHTML"),
    ],
    targets: [
        .target(
            name: "AlohaIntelligence",
            dependencies: [
                .product(name: "AlohaModels", package: "AlohaModels"),
                .product(name: "AlohaHTML", package: "AlohaHTML"),
            ],
            resources: [.process("Resources")],
            swiftSettings: settings
        ),
        .testTarget(
            name: "AlohaIntelligenceTests",
            dependencies: ["AlohaIntelligence"],
            swiftSettings: settings
        ),
    ]
)
