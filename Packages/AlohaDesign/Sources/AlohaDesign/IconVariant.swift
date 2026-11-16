// SPDX-License-Identifier: MIT

import SwiftUI

/// Which mark sits on the Home Screen.
///
/// Only the icon. The app's accent is never chosen in here: it is the colour
/// of the Nextcloud the account is on, read from its `theming` capability,
/// which is the colour its people already know the server by. The icon stays a
/// choice, because an icon is about finding the app on a crowded Home Screen
/// rather than about the server.
///
/// Each name matches an icon set in the asset catalogue, so renaming a case
/// renames an asset.
public nonisolated enum AlohaIconVariant: String, CaseIterable, Sendable, Codable, Identifiable {
    case aloha
    /// The primary's own dark appearance, chosen for every appearance.
    case midnight
    /// The colours turned inside out: a coral tile, a sand flower.
    case coral
    case ocean
    case forest
    case grape
    case rose
    case slate
    /// Graphite and paper, nothing else.
    case mono

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .aloha: String(localized: "Aloha", comment: "App icon name")
        case .midnight: String(localized: "Midnight", comment: "App icon name: the dark icon")
        case .coral: String(localized: "Coral", comment: "App icon name: coral tile, pale flower")
        case .ocean: String(localized: "Ocean", comment: "App icon name")
        case .forest: String(localized: "Forest", comment: "App icon name")
        case .grape: String(localized: "Grape", comment: "App icon name")
        case .rose: String(localized: "Rose", comment: "App icon name")
        case .slate: String(localized: "Slate", comment: "App icon name")
        case .mono: String(localized: "Mono", comment: "App icon name: black and white icon")
        }
    }

    /// The name of its icon set and of its preview image in the app's asset
    /// catalogue (`AlohaIcon-Ocean`, `AppIconPreview-Ocean`); `nil` for the
    /// primary icon, which `setAlternateIconName` calls `nil` too.
    public var alternateIconName: String? {
        self == .aloha ? nil : "AlohaIcon-\(assetSuffix)"
    }

    public var previewImageName: String { "AppIconPreview-\(assetSuffix)" }

    private var assetSuffix: String { rawValue.capitalized }

    /// The flower's colour in this icon, for drawing its preview. The same
    /// colours `tools/make-icons.sh` recolours the icons with.
    public var swatch: Color {
        switch self {
        case .aloha, .midnight: Color(red: 0.910, green: 0.376, blue: 0.298)
        case .coral: Color(red: 0.984, green: 0.957, blue: 0.918)
        case .ocean: Color(red: 0.11, green: 0.47, blue: 0.78)
        case .forest: Color(red: 0.13, green: 0.50, blue: 0.33)
        case .grape: Color(red: 0.47, green: 0.29, blue: 0.75)
        case .rose: Color(red: 0.82, green: 0.24, blue: 0.45)
        case .slate: Color(red: 0.33, green: 0.38, blue: 0.45)
        case .mono: Color(red: 0.12, green: 0.12, blue: 0.13)
        }
    }

    /// The tile's colour, for the same drawn preview.
    public var ground: Color {
        switch self {
        case .midnight: Color(red: 0.031, green: 0.165, blue: 0.2)
        case .coral: Color(red: 0.910, green: 0.376, blue: 0.298)
        case .mono: Color(red: 0.957, green: 0.957, blue: 0.949)
        default: Color(red: 0.984, green: 0.957, blue: 0.918)
        }
    }
}
