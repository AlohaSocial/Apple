// SPDX-License-Identifier: MIT

import Foundation

/// A `RawRepresentable` enum that keeps what it did not recognise.
///
/// Rule from docs/04 §2: an unknown enum case decodes to `.unknown(String)` and
/// never throws. A notification kind the app does not know renders as a generic
/// row; it never crashes and never vanishes without a log line.
public protocol UnknownPreserving: RawRepresentable, Codable, Hashable, Sendable
where RawValue == String {
    static func unknown(_ raw: String) -> Self
    var isUnknown: Bool { get }
}

extension UnknownPreserving {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.unknown(raw)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
