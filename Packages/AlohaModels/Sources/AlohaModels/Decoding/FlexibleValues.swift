// SPDX-License-Identifier: MIT

import Foundation

/// A server id, always carried as a `String`.
///
/// Rule from docs/04 §2: ids are `String` everywhere, even where a server sends
/// a number. Nextcloud Social uses numeric `nid`s, Mastodon uses snowflake
/// strings. Never parse an id as an integer for ordering.
@propertyWrapper
public struct FlexibleID: Codable, Hashable, Sendable {
    public var wrappedValue: String

    public init(wrappedValue: String) { self.wrappedValue = wrappedValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            wrappedValue = string
        } else if let int = try? container.decode(Int64.self) {
            wrappedValue = String(int)
        } else if let double = try? container.decode(Double.self) {
            wrappedValue = String(Int64(double))
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "id was neither string nor number")
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

/// An optional id that also tolerates a number, and treats `""` as absent.
@propertyWrapper
public struct FlexibleOptionalID: Codable, Hashable, Sendable {
    public var wrappedValue: String?

    public init(wrappedValue: String?) { self.wrappedValue = wrappedValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            wrappedValue = nil
        } else if let string = try? container.decode(String.self) {
            wrappedValue = string.isEmpty ? nil : string
        } else if let int = try? container.decode(Int64.self) {
            wrappedValue = String(int)
        } else {
            wrappedValue = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

/// A URL field that tolerates `""`.
///
/// Nextcloud Social can send `"avatar": ""` — `Person::exportAsLocal()` falls
/// through to `getAvatar()`, which is the stored value and may be empty
/// (docs/Mastodon-Compatibility.md §3.6, still open at 0.19.95). Mastodon
/// declares the field a URL, so a decoder that insists on one fails the whole
/// account. Empty means "no image", not "malformed".
@propertyWrapper
public struct LenientURL: Codable, Hashable, Sendable {
    public var wrappedValue: URL?

    public init(wrappedValue: URL?) { self.wrappedValue = wrappedValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard !container.decodeNil(), let raw = try? container.decode(String.self) else {
            wrappedValue = nil
            return
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        wrappedValue = trimmed.isEmpty ? nil : URL(string: trimmed)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue?.absoluteString ?? "")
    }
}

/// A `Bool` that tolerates `0`/`1` and `"true"`/`"false"`.
@propertyWrapper
public struct LenientBool: Codable, Hashable, Sendable {
    public var wrappedValue: Bool

    public init(wrappedValue: Bool) { self.wrappedValue = wrappedValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            wrappedValue = value
        } else if let value = try? container.decode(Int.self) {
            wrappedValue = value != 0
        } else if let value = try? container.decode(String.self) {
            wrappedValue = ["true", "1", "yes"].contains(value.lowercased())
        } else {
            wrappedValue = false
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

/// An `Int` that tolerates a numeric string.
///
/// `/api/v1/instance/activity` sends every value as a string, and some forks do
/// the same for counts.
@propertyWrapper
public struct LenientInt: Codable, Hashable, Sendable {
    public var wrappedValue: Int

    public init(wrappedValue: Int) { self.wrappedValue = wrappedValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            wrappedValue = value
        } else if let value = try? container.decode(Double.self) {
            wrappedValue = Int(value)
        } else if let value = try? container.decode(String.self), let parsed = Int(value) {
            wrappedValue = parsed
        } else {
            wrappedValue = 0
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

// Absent keys decode as the wrapper's zero value rather than throwing, which is
// what lets a fork that omits a documented field still produce a usable entity.
extension KeyedDecodingContainer {
    public func decode(
        _ type: FlexibleOptionalID.Type, forKey key: Key
    ) throws -> FlexibleOptionalID {
        try decodeIfPresent(type, forKey: key) ?? FlexibleOptionalID(wrappedValue: nil)
    }
    public func decode(_ type: LenientURL.Type, forKey key: Key) throws -> LenientURL {
        try decodeIfPresent(type, forKey: key) ?? LenientURL(wrappedValue: nil)
    }
    public func decode(_ type: LenientBool.Type, forKey key: Key) throws -> LenientBool {
        try decodeIfPresent(type, forKey: key) ?? LenientBool(wrappedValue: false)
    }
    public func decode(_ type: LenientInt.Type, forKey key: Key) throws -> LenientInt {
        try decodeIfPresent(type, forKey: key) ?? LenientInt(wrappedValue: 0)
    }
}
