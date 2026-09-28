// SPDX-License-Identifier: MIT

import Foundation

public struct CustomEmoji: Codable, Sendable, Hashable, Identifiable {
    public var shortcode: String
    @LenientURL public var url: URL?
    /// Nextcloud Social serves the same URL here as in `url`: a second, still
    /// rendering of every upload does not exist, and a `static_url` pointing at
    /// nothing would be worse than one pointing at the picture.
    @LenientURL public var staticURL: URL?
    @LenientBool public var visibleInPicker: Bool
    /// Omitted rather than null when there is none, which is how a picker groups.
    public var category: String?

    public var id: String { shortcode }

    enum CodingKeys: String, CodingKey {
        case shortcode, url, category
        case staticURL = "static_url"
        case visibleInPicker = "visible_in_picker"
    }

    public init(
        shortcode: String, url: URL? = nil, staticURL: URL? = nil,
        visibleInPicker: Bool = true, category: String? = nil
    ) {
        self.shortcode = shortcode
        _url = .init(wrappedValue: url)
        _staticURL = .init(wrappedValue: staticURL)
        _visibleInPicker = .init(wrappedValue: visibleInPicker)
        self.category = category
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shortcode = try c.decode(String.self, forKey: .shortcode)
        _url = try c.decode(LenientURL.self, forKey: .url)
        _staticURL = try c.decode(LenientURL.self, forKey: .staticURL)
        _visibleInPicker =
            try c.decodeIfPresent(LenientBool.self, forKey: .visibleInPicker)
            ?? LenientBool(wrappedValue: true)
        category = try c.decodeIfPresent(String.self, forKey: .category)
    }

    /// The still image where one genuinely differs, for a Reduce Motion reader.
    /// Falls back to `url`, because on Nextcloud Social they are the same file.
    public var stillURL: URL? { staticURL ?? url }
}
