// SPDX-License-Identifier: MIT

import Foundation

/// The `Link` header is the only cursor this app reads (docs/02 §5).
///
/// ```
/// Link: <…/timelines/home?limit=20&max_id=41>; rel="next",
///       <…/timelines/home?limit=20&min_id=60>; rel="prev"
/// ```
///
/// Every filter the caller sent survives into both links — so following `next`
/// preserves `only_video` and friends automatically. **Follow the URL; do not
/// rebuild it.**
public struct LinkHeader: Sendable, Hashable {
    public var next: URL?
    public var previous: URL?

    public init(next: URL? = nil, previous: URL? = nil) {
        self.next = next
        self.previous = previous
    }

    public var isEmpty: Bool { next == nil && previous == nil }

    public init(parsing raw: String?) {
        guard let raw, !raw.isEmpty else {
            self.init()
            return
        }

        var next: URL?
        var previous: URL?

        for segment in Self.splitEntries(raw) {
            guard let opening = segment.firstIndex(of: "<"),
                let closing = segment.firstIndex(of: ">"),
                opening < closing
            else { continue }

            let urlText = String(segment[segment.index(after: opening)..<closing])
            guard let url = URL(string: urlText.trimmingCharacters(in: .whitespaces)) else {
                continue
            }

            let parameters = segment[segment.index(after: closing)...]
            guard let rel = Self.relation(in: String(parameters)) else { continue }

            switch rel {
            case "next": next = url
            case "prev", "previous": previous = url
            default: break
            }
        }

        self.init(next: next, previous: previous)
    }

    /// Entries are comma-separated, but a URL may itself contain a comma inside
    /// a query value — so the split has to respect the angle brackets rather
    /// than naively splitting on `,`.
    private static func splitEntries(_ raw: String) -> [String] {
        var entries: [String] = []
        var current = ""
        var insideBrackets = false

        for character in raw {
            switch character {
            case "<":
                insideBrackets = true
                current.append(character)
            case ">":
                insideBrackets = false
                current.append(character)
            case "," where !insideBrackets:
                entries.append(current)
                current = ""
            default: current.append(character)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { entries.append(current) }
        return entries
    }

    private static func relation(in parameters: String) -> String? {
        for parameter in parameters.split(separator: ";") {
            let trimmed = parameter.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("rel") else { continue }
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            var value = String(trimmed[trimmed.index(after: equals)...])
                .trimmingCharacters(in: .whitespaces)
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.lowercased()
        }
        return nil
    }
}
