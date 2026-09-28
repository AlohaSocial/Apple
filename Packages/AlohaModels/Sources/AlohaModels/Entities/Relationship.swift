// SPDX-License-Identifier: MIT

import Foundation

public struct Relationship: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    @LenientBool public var following: Bool
    @LenientBool public var followedBy: Bool
    @LenientBool public var blocking: Bool
    @LenientBool public var blockedBy: Bool
    @LenientBool public var muting: Bool
    @LenientBool public var mutingNotifications: Bool
    @LenientBool public var requested: Bool
    @LenientBool public var requestedBy: Bool
    @LenientBool public var domainBlocking: Bool
    @LenientBool public var endorsed: Bool
    @LenientBool public var notifying: Bool
    /// Nextcloud Social honours `reblogs` on follow and enforces it as a
    /// predicate of the timeline query rather than by filtering a page, so this
    /// is real rather than hardcoded (docs/Mastodon-Compatibility.md §3.6).
    @LenientBool public var showingReblogs: Bool
    public var note: String?
    public var languages: [String]?

    enum CodingKeys: String, CodingKey {
        case id, following, blocking, muting, requested, endorsed, notifying, note, languages
        case followedBy = "followed_by"
        case blockedBy = "blocked_by"
        case mutingNotifications = "muting_notifications"
        case requestedBy = "requested_by"
        case domainBlocking = "domain_blocking"
        case showingReblogs = "showing_reblogs"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        _following = try c.decode(LenientBool.self, forKey: .following)
        _followedBy = try c.decode(LenientBool.self, forKey: .followedBy)
        _blocking = try c.decode(LenientBool.self, forKey: .blocking)
        _blockedBy = try c.decode(LenientBool.self, forKey: .blockedBy)
        _muting = try c.decode(LenientBool.self, forKey: .muting)
        _mutingNotifications = try c.decode(LenientBool.self, forKey: .mutingNotifications)
        _requested = try c.decode(LenientBool.self, forKey: .requested)
        _requestedBy = try c.decode(LenientBool.self, forKey: .requestedBy)
        _domainBlocking = try c.decode(LenientBool.self, forKey: .domainBlocking)
        _endorsed = try c.decode(LenientBool.self, forKey: .endorsed)
        _notifying = try c.decode(LenientBool.self, forKey: .notifying)
        _showingReblogs =
            try c.decodeIfPresent(LenientBool.self, forKey: .showingReblogs)
            ?? LenientBool(wrappedValue: true)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        languages = try c.decodeIfPresent([String].self, forKey: .languages)
    }

    public init(
        id: String, following: Bool = false, followedBy: Bool = false, blocking: Bool = false,
        blockedBy: Bool = false, muting: Bool = false, mutingNotifications: Bool = false,
        requested: Bool = false, requestedBy: Bool = false, domainBlocking: Bool = false,
        endorsed: Bool = false, notifying: Bool = false, showingReblogs: Bool = true,
        note: String? = nil, languages: [String]? = nil
    ) {
        _id = .init(wrappedValue: id)
        _following = .init(wrappedValue: following)
        _followedBy = .init(wrappedValue: followedBy)
        _blocking = .init(wrappedValue: blocking)
        _blockedBy = .init(wrappedValue: blockedBy)
        _muting = .init(wrappedValue: muting)
        _mutingNotifications = .init(wrappedValue: mutingNotifications)
        _requested = .init(wrappedValue: requested)
        _requestedBy = .init(wrappedValue: requestedBy)
        _domainBlocking = .init(wrappedValue: domainBlocking)
        _endorsed = .init(wrappedValue: endorsed)
        _notifying = .init(wrappedValue: notifying)
        _showingReblogs = .init(wrappedValue: showingReblogs)
        self.note = note
        self.languages = languages
    }
}
