// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaDesign

@Suite("Every app icon the picker offers is one the build ships")
struct IconVariantTests {

    /// The repository root, from this file's own path.
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // AlohaDesignTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // AlohaDesign
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()
    }

    private func listedAlternates() throws -> Set<String> {
        let config = try String(
            contentsOf: root.appending(path: "Supporting/Aloha.xcconfig"), encoding: .utf8)
        let line = try #require(
            config.split(separator: "\n").first { $0.hasPrefix("ALOHA_ALTERNATE_APP_ICONS") })
        let value = try #require(line.split(separator: "=", maxSplits: 1).last)
        return Set(value.split(separator: " ").map(String.init))
    }

    @Test("The primary icon has no alternate name; every other one has its own")
    func names() {
        #expect(AlohaIconVariant.aloha.alternateIconName == nil)
        let names = AlohaIconVariant.allCases.compactMap(\.alternateIconName)
        #expect(names.count == AlohaIconVariant.allCases.count - 1)
        #expect(Set(names).count == names.count)
        #expect(AlohaIconVariant.midnight.alternateIconName == "AlohaIcon-Midnight")
    }

    @Test("The build setting lists exactly the icons the picker offers")
    func buildSettingMatches() throws {
        let offered = Set(AlohaIconVariant.allCases.compactMap(\.alternateIconName))
        #expect(try listedAlternates() == offered)
    }

    @Test("Every offered icon has an icon set and a preview in the catalog")
    func assetsExist() {
        let catalog = root.appending(path: "AlohaSocial/Assets.xcassets")
        for variant in AlohaIconVariant.allCases {
            if let name = variant.alternateIconName {
                let set = catalog.appending(path: "\(name).appiconset/icon-1024.png")
                #expect(FileManager.default.fileExists(atPath: set.path), "\(name)")
                for appearance in ["dark", "tinted"] {
                    let file = catalog.appending(
                        path: "\(name).appiconset/icon-1024-\(appearance).png")
                    #expect(
                        FileManager.default.fileExists(atPath: file.path), "\(name) \(appearance)")
                }
            }
            let preview = catalog.appending(
                path:
                    "AppIconPreviews/\(variant.previewImageName).imageset/\(variant.previewImageName).png"
            )
            #expect(FileManager.default.fileExists(atPath: preview.path), "\(variant)")
        }
    }
}
