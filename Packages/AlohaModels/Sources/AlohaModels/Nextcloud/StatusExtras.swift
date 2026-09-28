// SPDX-License-Identifier: MIT

import Foundation

// Entities behind Nextcloud Social's per-status extras: where a post got to,
// who quoted it, and albums (docs/02 §2).

/// `GET /api/v1/statuses/{nid}/delivery` — one row per server the post was
/// sent to, and the totals. Author only.
public struct DeliveryReport: Codable, Sendable, Hashable {
    @LenientInt public var total: Int
    @LenientInt public var delivered: Int
    @LenientInt public var sending: Int
    @LenientInt public var waiting: Int
    @LenientInt public var failing: Int
    @LenientInt public var abandoned: Int
    /// How long the server keeps the rows, in seconds.
    @LenientInt public var retention: Int
    public var instances: [DeliveryInstance]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _total = try c.decode(LenientInt.self, forKey: .total)
        _delivered = try c.decode(LenientInt.self, forKey: .delivered)
        _sending = try c.decode(LenientInt.self, forKey: .sending)
        _waiting = try c.decode(LenientInt.self, forKey: .waiting)
        _failing = try c.decode(LenientInt.self, forKey: .failing)
        _abandoned = try c.decode(LenientInt.self, forKey: .abandoned)
        _retention = try c.decode(LenientInt.self, forKey: .retention)
        instances =
            (try? c.decode(LossyArray<DeliveryInstance>.self, forKey: .instances))?.elements ?? []
    }

    public init(
        total: Int, delivered: Int, sending: Int = 0, waiting: Int = 0, failing: Int = 0,
        abandoned: Int = 0, retention: Int = 604_800, instances: [DeliveryInstance] = []
    ) {
        _total = .init(wrappedValue: total)
        _delivered = .init(wrappedValue: delivered)
        _sending = .init(wrappedValue: sending)
        _waiting = .init(wrappedValue: waiting)
        _failing = .init(wrappedValue: failing)
        _abandoned = .init(wrappedValue: abandoned)
        _retention = .init(wrappedValue: retention)
        self.instances = instances
    }
}

public struct DeliveryInstance: Codable, Sendable, Hashable, Identifiable {
    public var host: String
    public var state: State
    @LenientInt public var tries: Int
    public var last: Date?

    public var id: String { host }

    public enum State: String, Codable, Sendable, Hashable {
        case delivered, sending, waiting, failing, abandoned
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        let raw = try c.decodeIfPresent(String.self, forKey: .state) ?? "waiting"
        state = State(rawValue: raw) ?? .waiting
        _tries = try c.decode(LenientInt.self, forKey: .tries)
        // Seconds since the epoch or an ISO date; both have been seen.
        if let seconds = try? c.decodeIfPresent(Double.self, forKey: .last) {
            last = Date(timeIntervalSince1970: seconds)
        } else {
            last = try? c.decodeIfPresent(Date.self, forKey: .last)
        }
    }

    public init(host: String, state: State, tries: Int = 1, last: Date? = nil) {
        self.host = host
        self.state = state
        _tries = .init(wrappedValue: tries)
        self.last = last
    }
}

/// Who may quote a post (`PUT /api/v1/statuses/{nid}/interaction_policy`).
public enum QuoteApprovalPolicy: String, Codable, Sendable, Hashable, CaseIterable {
    case `public`, followers, nobody
}

/// The body of `POST /api/v1/collections`, and of `PUT` on one.
public struct CollectionDraft: Sendable, Hashable {
    public var title: String
    public var description: String
    /// `public`, `private` or `draft`, as Pixelfed names them.
    public var visibility: String

    public init(title: String, description: String = "", visibility: String = "public") {
        self.title = title
        self.description = description
        self.visibility = visibility
    }
}
