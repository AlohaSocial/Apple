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
public enum AlohaIconVariant: String, CaseIterable, Sendable, Codable, Identifiable {
    case aloha
    case ocean
    case forest
    case grape
    case rose
    case slate

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .aloha: String(localized: "Aloha", comment: "App icon name")
        case .ocean: String(localized: "Ocean", comment: "App icon name")
        case .forest: String(localized: "Forest", comment: "App icon name")
        case .grape: String(localized: "Grape", comment: "App icon name")
        case .rose: String(localized: "Rose", comment: "App icon name")
        case .slate: String(localized: "Slate", comment: "App icon name")
        }
    }

    /// The flower's colour in this icon, for drawing its preview. The same
    /// colours `tools/make-icons.sh` recolours the icons with.
    public var swatch: Color {
        switch self {
        case .aloha: Color(red: 0.910, green: 0.376, blue: 0.298)
        case .ocean: Color(red: 0.11, green: 0.47, blue: 0.78)
        case .forest: Color(red: 0.13, green: 0.50, blue: 0.33)
        case .grape: Color(red: 0.47, green: 0.29, blue: 0.75)
        case .rose: Color(red: 0.82, green: 0.24, blue: 0.45)
        case .slate: Color(red: 0.33, green: 0.38, blue: 0.45)
        }
    }
}
