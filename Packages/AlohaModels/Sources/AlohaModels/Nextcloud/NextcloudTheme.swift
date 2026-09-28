// SPDX-License-Identifier: MIT

import Foundation

/// The colour a Nextcloud is wearing.
///
/// Read from Nextcloud's own `theming` capability rather than from the Social
/// app, which serves no colour of its own: `GET /ocs/v2.php/cloud/capabilities`
/// at the **Nextcloud root**, not the Mastodon API base. Public, because it is
/// what themes a client's sign-in screen before anybody has signed in.
///
/// An administrator who has themed their Nextcloud has already chosen the
/// colour their people know the server by; asking them to choose it a second
/// time in this app is asking the same question twice and getting two answers
/// (docs/05 §2).
public struct NextcloudTheme: Codable, Sendable, Hashable {
    /// What the instance calls itself.
    public var name: String
    public var slogan: String
    /// `#rrggbb`, the raw primary colour.
    public var colourHex: String?
    /// The primary adjusted to stay legible **on a light background**.
    public var elementBrightHex: String?
    /// The primary adjusted to stay legible **on a dark background**.
    public var elementDarkHex: String?
    /// What Nextcloud puts *on* the primary colour: `#ffffff` or `#000000`.
    public var textHex: String?

    public init(
        name: String = "", slogan: String = "", colourHex: String? = nil,
        elementBrightHex: String? = nil, elementDarkHex: String? = nil, textHex: String? = nil
    ) {
        self.name = name
        self.slogan = slogan
        self.colourHex = colourHex
        self.elementBrightHex = elementBrightHex
        self.elementDarkHex = elementDarkHex
        self.textHex = textHex
    }

    enum CodingKeys: String, CodingKey {
        case name, slogan, color
        case colorElementBright = "color-element-bright"
        case colorElementDark = "color-element-dark"
        case colorText = "color-text"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        slogan = (try? c.decode(String.self, forKey: .slogan)) ?? ""
        colourHex = Self.normalised(try? c.decode(String.self, forKey: .color))
        elementBrightHex = Self.normalised(try? c.decode(String.self, forKey: .colorElementBright))
        elementDarkHex = Self.normalised(try? c.decode(String.self, forKey: .colorElementDark))
        textHex = Self.normalised(try? c.decode(String.self, forKey: .colorText))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(slogan, forKey: .slogan)
        try c.encodeIfPresent(colourHex, forKey: .color)
        try c.encodeIfPresent(elementBrightHex, forKey: .colorElementBright)
        try c.encodeIfPresent(elementDarkHex, forKey: .colorElementDark)
        try c.encodeIfPresent(textHex, forKey: .colorText)
    }

    /// Whether this says anything about a colour at all. A Nextcloud with the
    /// Theming app disabled answers with the keys absent.
    public var hasColour: Bool { colourHex != nil }

    /// The variant to use against a background of this kind.
    ///
    /// Nextcloud computes both: `color-element-bright` is the primary darkened
    /// far enough to read on a light background, `color-element-dark` is it
    /// lightened to read on a dark one. Falling back to the raw colour where a
    /// server sends neither is the honest thing — it is still the colour the
    /// administrator chose, and the contrast guard in `AlohaDesign` will move
    /// it if it has to.
    public func hex(onDarkBackground dark: Bool) -> String? {
        (dark ? elementDarkHex : elementBrightHex) ?? colourHex
    }

    /// `#abc` and `abcdef` both become `#aabbcc`-style six-digit hex; anything
    /// else becomes `nil` rather than a colour nobody chose.
    static func normalised(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !text.isEmpty
        else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }

        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        guard text.count == 6, text.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + text
    }
}

/// Nextcloud's OCS envelope, unwrapped far enough to reach `theming`.
///
/// Everything else in `capabilities` is somebody else's business, and decoding
/// it would mean tracking a schema this app does not use.
public struct OCSCapabilities: Decodable, Sendable {
    public var theming: NextcloudTheme?

    enum Outer: String, CodingKey { case ocs }
    enum Envelope: String, CodingKey { case data }
    enum Data: String, CodingKey { case capabilities }
    enum Capabilities: String, CodingKey { case theming }

    public init(from decoder: any Decoder) throws {
        let outer = try decoder.container(keyedBy: Outer.self)
        let ocs = try outer.nestedContainer(keyedBy: Envelope.self, forKey: .ocs)
        let data = try ocs.nestedContainer(keyedBy: Data.self, forKey: .data)
        let capabilities = try data.nestedContainer(
            keyedBy: Capabilities.self, forKey: .capabilities)
        theming = try? capabilities.decode(NextcloudTheme.self, forKey: .theming)
    }
}
