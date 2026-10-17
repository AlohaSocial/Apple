// swift-tools-version: 6.2
// SPDX-License-Identifier: MIT

import PackageDescription

let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    // docs/12 §1: view code is main-actor code, and anything that is not
    // says so explicitly.
    .defaultIsolation(MainActor.self),
    // A warning fails the build, in every package.
    .treatAllWarnings(as: .error),
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
