// swift-tools-version: 6.2
// SPDX-License-Identifier: MIT

import PackageDescription

let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6)
]

let package = Package(
    name: "AlohaStore",
    defaultLocalization: "en",
    platforms: [.iOS("27.0"), .macOS("27.0"), .visionOS("27.0"), .watchOS("27.0"), .tvOS("27.0")],
    products: [
        .library(name: "AlohaStore", targets: ["AlohaStore"])
    ],
    dependencies: [
        .package(path: "../AlohaModels"),
        .package(path: "../AlohaHTML"),
        .package(path: "../AlohaNetwork"),
    ],
    targets: [
        .target(
            name: "AlohaStore",
            dependencies: [
                .product(name: "AlohaModels", package: "AlohaModels"),
                .product(name: "AlohaHTML", package: "AlohaHTML"),
                .product(name: "AlohaNetwork", package: "AlohaNetwork"),
            ],
            resources: [.process("Resources")],
            swiftSettings: settings
        ),
        .testTarget(
            name: "AlohaStoreTests",
            dependencies: ["AlohaStore"],
            swiftSettings: settings
        ),
    ]
)
