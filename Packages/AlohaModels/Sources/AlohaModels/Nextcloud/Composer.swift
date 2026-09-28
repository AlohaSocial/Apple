// SPDX-License-Identifier: MIT

import Foundation

// Entities behind the composer's Nextcloud Social extras: places, the GIF
// library and team accounts. Decoded leniently, like everything else here
// (docs/04 §2).

/// A place a post can be tagged with. A name and a country; never a map pin
/// unless the server had one.
public struct Place: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var name: String
    public var country: String?
    public var latitude: Double?
    public var longitude: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, country
        case latitude = "lat"
        case longitude = "lon"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        country = try? c.decodeIfPresent(String.self, forKey: .country)
        latitude = Self.number(c, .latitude)
        longitude = Self.number(c, .longitude)
    }

    /// Coordinates arrive as numbers or as strings, depending on who stored
    /// the place.
    private static func number(
        _ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
    ) -> Double? {
        if let value = try? c.decodeIfPresent(Double.self, forKey: key) { return value }
        if let text = try? c.decodeIfPresent(String.self, forKey: key) { return Double(text) }
        return nil
    }

    public init(
        id: String, name: String, country: String? = nil,
        latitude: Double? = nil, longitude: Double? = nil
    ) {
        _id = .init(wrappedValue: id)
        self.name = name
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
    }

    /// "Berlin, Germany", or just the name when the country is unknown.
    public var displayName: String {
        guard let country, !country.isEmpty else { return name }
        return "\(name), \(country)"
    }
}

/// One animated picture from the instance's library.
public struct GIFEntry: Codable, Sendable, Hashable, Identifiable {
    public var slug: String
    public var title: String
    @LenientURL public var url: URL?
    @LenientURL public var previewURL: URL?
    public var width: Int?
    public var height: Int?

    public var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, title, name, url, width, height
        case previewURL = "preview_url"
        case preview
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = (try? c.decode(String.self, forKey: .slug)) ?? ""
        title =
            (try? c.decodeIfPresent(String.self, forKey: .title))
            ?? (try? c.decodeIfPresent(String.self, forKey: .name)) ?? slug
        _url = (try? c.decode(LenientURL.self, forKey: .url)) ?? LenientURL(wrappedValue: nil)
        _previewURL =
            (try? c.decode(LenientURL.self, forKey: .previewURL))
            ?? (try? c.decode(LenientURL.self, forKey: .preview))
            ?? LenientURL(wrappedValue: nil)
        width = try? c.decodeIfPresent(Int.self, forKey: .width)
        height = try? c.decodeIfPresent(Int.self, forKey: .height)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(slug, forKey: .slug)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(previewURL, forKey: .previewURL)
        try c.encodeIfPresent(width, forKey: .width)
        try c.encodeIfPresent(height, forKey: .height)
    }

    public init(
        slug: String, title: String, url: URL?, previewURL: URL? = nil, width: Int? = nil,
        height: Int? = nil
    ) {
        self.slug = slug
        self.title = title
        _url = .init(wrappedValue: url)
        _previewURL = .init(wrappedValue: previewURL)
        self.width = width
        self.height = height
    }

    public var aspectRatio: Double {
        guard let width, let height, height > 0 else { return 1 }
        return Double(width) / Double(height)
    }
}

/// A page of the library, with the credit the server asks to be shown.
public struct GIFLibrary: Codable, Sendable, Hashable {
    public var gifs: [GIFEntry]
    @LenientInt public var total: Int
    public var attribution: String?

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gifs = (try? c.decode(LossyArray<GIFEntry>.self, forKey: .gifs))?.elements ?? []
        _total =
            (try? c.decode(LenientInt.self, forKey: .total)) ?? LenientInt(wrappedValue: gifs.count)
        attribution = try? c.decodeIfPresent(String.self, forKey: .attribution)
    }

    public init(gifs: [GIFEntry], total: Int, attribution: String? = nil) {
        self.gifs = gifs
        _total = .init(wrappedValue: total)
        self.attribution = attribution
    }
}

/// A group account the viewer may post as.
public struct TeamAccount: Codable, Sendable, Hashable, Identifiable {
    public var handle: String
    public var name: String
    @LenientURL public var avatar: URL?

    public var id: String { handle }

    enum CodingKeys: String, CodingKey {
        case handle, acct, name, avatar
        case displayName = "display_name"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        handle =
            (try? c.decodeIfPresent(String.self, forKey: .handle))
            ?? (try? c.decodeIfPresent(String.self, forKey: .acct)) ?? ""
        name =
            (try? c.decodeIfPresent(String.self, forKey: .name))
            ?? (try? c.decodeIfPresent(String.self, forKey: .displayName)) ?? handle
        _avatar = (try? c.decode(LenientURL.self, forKey: .avatar)) ?? LenientURL(wrappedValue: nil)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(handle, forKey: .handle)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(avatar, forKey: .avatar)
    }

    public init(handle: String, name: String, avatar: URL? = nil) {
        self.handle = handle
        self.name = name
        _avatar = .init(wrappedValue: avatar)
    }
}

/// The wrapper `GET /api/v1.1/teams` answers with.
public struct TeamList: Codable, Sendable, Hashable {
    public var teams: [TeamAccount]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        teams = (try? c.decode(LossyArray<TeamAccount>.self, forKey: .teams))?.elements ?? []
    }

    public init(teams: [TeamAccount]) { self.teams = teams }
}
