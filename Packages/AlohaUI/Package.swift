// swift-tools-version: 6.2
// SPDX-License-Identifier: MIT

import PackageDescription

let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
]

let package = Package(
    name: "AlohaUI",
    defaultLocalization: "en",
    platforms: [.iOS("27.0"), .macOS("27.0"), .visionOS("27.0"), .watchOS("27.0"), .tvOS("27.0")],
    products: [
        .library(name: "AlohaUI", targets: ["AlohaUI"])
    ],
    dependencies: [
        .package(path: "../AlohaModels"),
        .package(path: "../AlohaHTML"),
        .package(path: "../AlohaNetwork"),
        .package(path: "../AlohaStore"),
        .package(path: "../AlohaMedia"),
        .package(path: "../AlohaIntelligence"),
        .package(path: "../AlohaDesign"),
    ],
    targets: [
        .target(
            name: "AlohaUI",
            dependencies: [
                .product(name: "AlohaModels", package: "AlohaModels"),
                .product(name: "AlohaNetwork", package: "AlohaNetwork"),
                .product(name: "AlohaHTML", package: "AlohaHTML"),
                .product(name: "AlohaStore", package: "AlohaStore"),
                .product(name: "AlohaMedia", package: "AlohaMedia"),
                .product(name: "AlohaIntelligence", package: "AlohaIntelligence"),
                .product(name: "AlohaDesign", package: "AlohaDesign"),
            ],
            resources: [.process("Resources")],
            swiftSettings: settings
        ),
        .testTarget(
            name: "AlohaUITests",
            dependencies: [
                "AlohaUI",
                .product(name: "AlohaModels", package: "AlohaModels"),
                .product(name: "AlohaNetwork", package: "AlohaNetwork"),
            ],
            swiftSettings: settings
        ),
    ]
)
