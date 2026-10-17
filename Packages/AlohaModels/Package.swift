// swift-tools-version: 6.2
// SPDX-License-Identifier: MIT

import PackageDescription

let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    // docs/12 §1: a warning fails the build, in every package.
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "AlohaModels",
    defaultLocalization: "en",
    platforms: [.iOS("27.0"), .macOS("27.0"), .visionOS("27.0"), .watchOS("27.0"), .tvOS("27.0")],
    products: [
        .library(name: "AlohaModels", targets: ["AlohaModels"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AlohaModels",
            dependencies: [],
            resources: [.process("Resources")],
            swiftSettings: settings
        ),
        .testTarget(
            name: "AlohaModelsTests",
            dependencies: ["AlohaModels"],
            swiftSettings: settings
        ),
    ]
)
