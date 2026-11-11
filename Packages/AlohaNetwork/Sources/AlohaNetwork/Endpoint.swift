// SPDX-License-Identifier: MIT

import Foundation

public enum HTTPMethod: String, Sendable, Hashable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// A request described relative to an account's API base.
///
/// No string concatenation at call sites: endpoints are declared as static
/// factory methods grouped by area (`Endpoint.timelines`, `.statuses`, …).
public struct Endpoint: Sendable, Hashable {
    /// Which credential the route accepts.
    ///
    /// Almost everything here is the Social app's own client API and takes the
    /// OAuth bearer token. A handful of routes are Nextcloud's rather than
    /// Mastodon's — they carry `#[NoAdminRequired]` on the server, which means
    /// a Nextcloud session and not a bearer token — and those need the app
    /// password as HTTP Basic instead (docs/03 §5).
    public enum Authentication: Sendable, Hashable {
        /// The Social OAuth token.
        case bearer
        /// The Nextcloud app password, as HTTP Basic. Refused before it leaves
        /// the device when no app password has been granted.
        case nextcloudSession
    }

    public var method: HTTPMethod
    /// Relative to the resolved API base, with no leading slash. Written as
    /// it reads, not percent-encoded: `url(base:)` encodes it exactly once,
    /// so a tag, an emoji or a user name goes in as it is. One encoded here
    /// first would arrive as `%25…`.
    public var path: String
    public var query: [URLQueryItem]
    public var body: Body?
    /// Requires a credential. A request for a viewer-only route without one
    /// is refused before it leaves the device.
    public var requiresAuthentication: Bool
    /// Which credential, when one is required.
    public var authentication: Authentication
    /// Sent as `Idempotency-Key`. What makes retry-on-timeout safe for a post.
    public var idempotencyKey: String?

    public enum Body: Sendable, Hashable {
        case form([URLQueryItem])
        case json(Data)
        case multipart(Multipart)
        case empty
    }

    public init(
        method: HTTPMethod = .get,
        path: String,
        query: [URLQueryItem] = [],
        body: Body? = nil,
        requiresAuthentication: Bool = true,
        authentication: Authentication = .bearer,
        idempotencyKey: String? = nil
    ) {
        self.method = method
        self.path = path.hasPrefix("/") ? String(path.dropFirst()) : path
        self.query = query
        self.body = body
        self.requiresAuthentication = requiresAuthentication
        self.authentication = authentication
        self.idempotencyKey = idempotencyKey
    }

    public func adding(_ items: [URLQueryItem]) -> Endpoint {
        var copy = self
        copy.query.append(contentsOf: items.filter { $0.value != nil })
        return copy
    }

    public func url(base: URL) -> URL? {
        guard
            var components = URLComponents(
                url: base.appending(path: path), resolvingAgainstBaseURL: false)
        else { return nil }
        // The form encoder's escaping, not `queryItems`: that leaves `+` bare,
        // and a server reads a bare `+` in a query as a space.
        let encoded = FormEncoding.encode(query)
        if !encoded.isEmpty {
            if let existing = components.percentEncodedQuery, !existing.isEmpty {
                components.percentEncodedQuery = existing + "&" + encoded
            } else {
                components.percentEncodedQuery = encoded
            }
        }
        return components.url
    }
}

public struct Multipart: Sendable, Hashable {
    public var boundary: String
    public var parts: [Part]

    public struct Part: Sendable, Hashable {
        public var name: String
        public var filename: String?
        public var mimeType: String?
        public var data: Data

        public init(name: String, filename: String? = nil, mimeType: String? = nil, data: Data) {
            self.name = name
            self.filename = filename
            self.mimeType = mimeType
            self.data = data
        }

        public static func field(_ name: String, _ value: String) -> Part {
            Part(name: name, data: Data(value.utf8))
        }
    }

    public init(parts: [Part], boundary: String = "aloha-\(UUID().uuidString)") {
        self.parts = parts
        self.boundary = boundary
    }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public func encoded() -> Data {
        var data = Data()
        forEachChunk { data.append($0) }
        return data
    }

    /// The same bytes as `encoded()`, written to `file` a part at a time. What
    /// an upload streams from: a video is already in memory once, as its
    /// part's data, and the body is never assembled into a second copy.
    public func write(to file: URL) throws {
        guard FileManager.default.createFile(atPath: file.path(), contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: file])
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try forEachChunk { try handle.write(contentsOf: $0) }
    }

    private func forEachChunk(_ body: (Data) throws -> Void) rethrows {
        for part in parts {
            try body(Data("--\(boundary)\r\n".utf8))
            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let filename = part.filename { disposition += "; filename=\"\(filename)\"" }
            try body(Data("\(disposition)\r\n".utf8))
            if let mimeType = part.mimeType {
                try body(Data("Content-Type: \(mimeType)\r\n".utf8))
            }
            try body(Data("\r\n".utf8))
            try body(part.data)
            try body(Data("\r\n".utf8))
        }
        try body(Data("--\(boundary)--\r\n".utf8))
    }
}

extension Array where Element == URLQueryItem {
    /// Mastodon's array parameters are `types[]=mention&types[]=follow`.
    public static func repeated(_ name: String, _ values: [String]) -> [URLQueryItem] {
        values.map { URLQueryItem(name: "\(name)[]", value: $0) }
    }

    public static func optional(_ name: String, _ value: String?) -> [URLQueryItem] {
        value.map { [URLQueryItem(name: name, value: $0)] } ?? []
    }

    /// A flag is sent only when true: an explicit `only_video=false` is noise,
    /// and some forks parse any presence as truth.
    public static func flag(_ name: String, _ value: Bool) -> [URLQueryItem] {
        value ? [URLQueryItem(name: name, value: "true")] : []
    }
}
