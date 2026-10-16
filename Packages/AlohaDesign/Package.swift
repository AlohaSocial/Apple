// swift-tools-version: 6.2
// SPDX-License-Identifier: MIT

import PackageDescription

let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6)
]

let package = Package(
    name: "AlohaDesign",
    defaultLocalization: "en",
    platforms: [.iOS("27.0"), .macOS("27.0"), .visionOS("27.0"), .watchOS("27.0"), .tvOS("27.0")],
    products: [
        .library(name: "AlohaDesign", targets: ["AlohaDesign"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AlohaDesign",
            dependencies: [],
            resources: [.process("Resources")],
            swiftSettings: settings
        ),
        .testTarget(
            name: "AlohaDesignTests",
            dependencies: ["AlohaDesign"],
            swiftSettings: settings
        ),
    ]
)
