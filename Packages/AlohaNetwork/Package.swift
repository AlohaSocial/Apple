// swift-tools-version: 6.2
// SPDX-License-Identifier: MIT

import PackageDescription

let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6)
]

let package = Package(
    name: "AlohaNetwork",
    defaultLocalization: "en",
    platforms: [.iOS("27.0"), .macOS("27.0"), .visionOS("27.0"), .watchOS("27.0"), .tvOS("27.0")],
    products: [
        .library(name: "AlohaNetwork", targets: ["AlohaNetwork"])
    ],
    dependencies: [
        .package(path: "../AlohaModels")
    ],
    targets: [
        .target(
            name: "AlohaNetwork",
            dependencies: [
                .product(name: "AlohaModels", package: "AlohaModels")
            ],
            resources: [.process("Resources")],
            swiftSettings: settings
        ),
        .testTarget(
            name: "AlohaNetworkTests",
            dependencies: ["AlohaNetwork"],
            swiftSettings: settings
        ),
    ]
)
