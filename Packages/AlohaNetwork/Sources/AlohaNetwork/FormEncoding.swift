// SPDX-License-Identifier: MIT

import Foundation

/// `application/x-www-form-urlencoded`, spelled the way a server reads it.
///
/// `URLComponents.percentEncodedQuery` is a *URL* encoder: it leaves `+`, `=`,
/// `&` inside a value only partly escaped, and `+` not at all. Every form
/// parser — PHP's included — reads a bare `+` as a space, so a post saying
/// "C++" arrived as "C  ", and the base64 keys and signatures of the Nextcloud
/// push registration arrived corrupted. Everything outside RFC 3986's
/// unreserved set is percent-encoded here instead; that is unambiguous to
/// every parser.
public enum FormEncoding {
    /// RFC 3986 §2.3: the only characters that never need escaping.
    static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// One name or value, percent-encoded.
    public static func escape(_ string: String) -> String {
        // Only fails on unpaired surrogates, which a Swift `String` cannot
        // hold; the fallback keeps the signature non-optional.
        string.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// `name=value&name=value`, skipping items without a value — the same
    /// rule `Endpoint.adding(_:)` applies to queries.
    public static func encode(_ items: [URLQueryItem]) -> String {
        items.compactMap { item in
            item.value.map { "\(escape(item.name))=\(escape($0))" }
        }
        .joined(separator: "&")
    }

    /// The body of a form request.
    public static func body(_ items: [URLQueryItem]) -> Data {
        Data(encode(items).utf8)
    }

    /// The Content-Type that goes with `body(_:)`.
    public static let contentType = "application/x-www-form-urlencoded; charset=utf-8"
}

extension URLComponents {
    /// Sets the query with the form encoder's escaping, so a `+` or `&` in a
    /// search term or a hashtag reaches the server as itself rather than as a
    /// space or a second parameter.
    mutating func setStrictQueryItems(_ items: [URLQueryItem]) {
        let encoded = FormEncoding.encode(items)
        percentEncodedQuery = encoded.isEmpty ? nil : encoded
    }
}
