// SPDX-License-Identifier: MIT

import Foundation

/// A decoded page plus its cursors.
public struct Paginated<Value: Sendable>: Sendable {
    public var value: Value
    public var link: LinkHeader
    /// How many rows the *query* returned, before any filtering the controller
    /// then did. This is what decides "a page shorter than `limit` is the last
    /// one" — counting filtered rows out would make a filtered page look like
    /// the end of the list (docs/02 §5).
    public var rawCount: Int
    public var requestedLimit: Int

    public init(value: Value, link: LinkHeader, rawCount: Int, requestedLimit: Int) {
        self.value = value
        self.link = link
        self.rawCount = rawCount
        self.requestedLimit = requestedLimit
    }

    /// Trust the header first; fall back to the count only where the server
    /// sends no header at all (`/blocks`, `/mutes`, `/scheduled_statuses`).
    public var mayHaveMore: Bool {
        if !link.isEmpty { return link.next != nil }
        return rawCount >= requestedLimit
    }

    public func map<Other>(_ transform: (Value) throws -> Other) rethrows -> Paginated<Other> {
        Paginated<Other>(
            value: try transform(value), link: link,
            rawCount: rawCount, requestedLimit: requestedLimit)
    }
}

/// Where a page request starts from. A fetch is always anchored: `min_id` from
/// the newest cached entry, `max_id` from the oldest, a `Link` URL, or a cold
/// load. Anything else risks an invisible gap (docs/08 §8).
public enum PageAnchor: Sendable, Hashable {
    case cold
    case olderThan(String)
    case newerThan(String)
    case immediatelyAfter(String)
    case url(URL)

    var queryItems: [URLQueryItem] {
        switch self {
        case .cold, .url: []
        case .olderThan(let id): [URLQueryItem(name: "max_id", value: id)]
        case .newerThan(let id): [URLQueryItem(name: "min_id", value: id)]
        case .immediatelyAfter(let id): [URLQueryItem(name: "since_id", value: id)]
        }
    }
}
