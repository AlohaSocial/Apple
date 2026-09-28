// SPDX-License-Identifier: MIT

import Foundation

/// The one decoder the whole app uses for server payloads.
///
/// Date handling covers the forms the fediverse actually sends: ISO 8601 with
/// fractional seconds, ISO 8601 without them, a bare `yyyy-MM-dd` (which is what
/// a `Filter` expiry and an announcement `scheduled_at` can be), and a Unix
/// timestamp — `/api/v1/instance/activity` keys each week by the unix time its
/// Monday began, as a string.
///
/// `Date.ISO8601FormatStyle` rather than `ISO8601DateFormatter`: the formatter
/// is a non-`Sendable` class and would need a lock or an unsafe global to be
/// shared, and the format style is a value type that needs neither.
public enum AlohaJSON {
    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()

            if let raw = try? container.decode(String.self) {
                if let date = DateParsing.parse(raw) { return date }
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "unrecognised date \(raw)")
            }
            if let seconds = try? container.decode(TimeInterval.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "date was neither string nor number")
        }
        return decoder
    }()

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(DateParsing.format(date))
        }
        return encoder
    }()
}

public enum DateParsing {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle()
    private static let dateOnly = Date.ISO8601FormatStyle(
        dateSeparator: .dash, dateTimeSeparator: .standard, timeSeparator: .colon
    ).year().month().day()

    public static func parse(_ raw: String) -> Date? {
        if let date = try? fractional.parse(raw) { return date }
        if let date = try? plain.parse(raw) { return date }
        if let date = try? dateOnly.parse(raw) { return date }
        if let seconds = TimeInterval(raw) { return Date(timeIntervalSince1970: seconds) }
        return nil
    }

    public static func format(_ date: Date) -> String {
        date.formatted(fractional)
    }
}
