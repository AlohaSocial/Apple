// SPDX-License-Identifier: MIT

import AlohaDesign
import SwiftUI

/// The language a post is written in, as a menu of the common ones plus
/// whatever the account already defaults to. Readers filter on it, so it is
/// worth a tap.
struct LanguagePicker: View {
    @Binding var language: String?
    /// The account default, offered first even when it is not in the list.
    let fallback: String?

    private static let common = [
        "en", "de", "fr", "es", "it", "nl", "pt", "pl", "sv", "da", "nb", "fi",
        "cs", "uk", "ru", "tr", "ar", "ja", "ko", "zh",
    ]

    private var options: [String] {
        var codes = Self.common
        for extra in [fallback, language].compactMap({ $0 }) where !codes.contains(extra) {
            codes.insert(extra, at: 0)
        }
        return codes
    }

    var body: some View {
        Picker(selection: $language) {
            Text("Not set", comment: "Language picker option").tag(String?.none)
            ForEach(options, id: \.self) { code in
                Text(Self.name(for: code)).tag(String?.some(code))
            }
        } label: {
            Text("Language", comment: "Composer picker")
        }
        .pickerStyle(.inline)
    }

    static func name(for code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }

    /// Short label for the toolbar glyph.
    static func short(for code: String?) -> String {
        (code ?? "").uppercased()
    }
}
