// swift-tools-version: 6.2
// SPDX-License-Identifier: MIT

import PackageDescription

let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
]

let package = Package(
    name: "AlohaHTML",
    defaultLocalization: "en",
    platforms: [.iOS("27.0"), .macOS("27.0"), .visionOS("27.0"), .watchOS("27.0"), .tvOS("27.0")],
    products: [
        .library(name: "AlohaHTML", targets: ["AlohaHTML"])
    ],
    dependencies: [
        .package(path: "../AlohaModels"),
    ],
    targets: [
        .target(
            name: "AlohaHTML",
            dependencies: [
                .product(name: "AlohaModels", package: "AlohaModels"),
            ],
            resources: [.process("Resources")],
            swiftSettings: settings
        ),
        .testTarget(
            name: "AlohaHTMLTests",
            dependencies: ["AlohaHTML"],
            swiftSettings: settings
        ),
    ]
)
