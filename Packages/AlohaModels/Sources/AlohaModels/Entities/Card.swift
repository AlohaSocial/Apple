// SPDX-License-Identifier: MIT

import Foundation

public struct Card: Codable, Sendable, Hashable {
    @LenientURL public var url: URL?
    public var title: String
    public var description: String
    public var type: String
    public var authorName: String?
    @LenientURL public var authorURL: URL?
    public var providerName: String?
    @LenientURL public var providerURL: URL?
    @LenientURL public var image: URL?
    public var blurhash: String?
    public var width: Int?
    public var height: Int?
    public var html: String?

    enum CodingKeys: String, CodingKey {
        case url, title, description, type, image, blurhash, width, height, html
        case authorName = "author_name"
        case authorURL = "author_url"
        case providerName = "provider_name"
        case providerURL = "provider_url"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _url = try c.decode(LenientURL.self, forKey: .url)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "link"
        authorName = try c.decodeIfPresent(String.self, forKey: .authorName)
        _authorURL = try c.decode(LenientURL.self, forKey: .authorURL)
        providerName = try c.decodeIfPresent(String.self, forKey: .providerName)
        _providerURL = try c.decode(LenientURL.self, forKey: .providerURL)
        _image = try c.decode(LenientURL.self, forKey: .image)
        blurhash = try c.decodeIfPresent(String.self, forKey: .blurhash)
        width = try c.decodeIfPresent(Int.self, forKey: .width)
        height = try c.decodeIfPresent(Int.self, forKey: .height)
        html = try c.decodeIfPresent(String.self, forKey: .html)
    }

    public init(
        url: URL? = nil, title: String = "", description: String = "", type: String = "link",
        authorName: String? = nil, authorURL: URL? = nil, providerName: String? = nil,
        providerURL: URL? = nil, image: URL? = nil, blurhash: String? = nil,
        width: Int? = nil, height: Int? = nil, html: String? = nil
    ) {
        _url = .init(wrappedValue: url)
        self.title = title
        self.description = description
        self.type = type
        self.authorName = authorName
        _authorURL = .init(wrappedValue: authorURL)
        self.providerName = providerName
        _providerURL = .init(wrappedValue: providerURL)
        _image = .init(wrappedValue: image)
        self.blurhash = blurhash
        self.width = width
        self.height = height
        self.html = html
    }

    /// What to print under the headline. The host is the honest fallback — a
    /// card with no provider name still tells a reader where the link goes.
    public var displayProvider: String {
        if let providerName, !providerName.isEmpty { return providerName }
        return url?.host() ?? ""
    }
}
