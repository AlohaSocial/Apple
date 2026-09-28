// SPDX-License-Identifier: MIT

import Foundation

/// Mastodon's v1 notification: one row per event.
public struct MastodonNotification: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var type: NotificationKind
    public var createdAt: Date
    public var account: Account
    public var status: Status?

    enum CodingKeys: String, CodingKey {
        case id, type, account, status
        case createdAt = "created_at"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        type = try c.decodeIfPresent(NotificationKind.self, forKey: .type) ?? .unknownCase
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        account = try c.decode(Account.self, forKey: .account)
        status = try? c.decodeIfPresent(Status.self, forKey: .status)
    }

    public init(
        id: String, type: NotificationKind, createdAt: Date = Date(),
        account: Account, status: Status? = nil
    ) {
        _id = .init(wrappedValue: id)
        self.type = type
        self.createdAt = createdAt
        self.account = account
        self.status = status
    }
}

/// Mastodon 4.3's grouped notifications. A page of forty favourites of one post
/// is one group and one copy of the post here, where v1 sends forty rows and
/// forty copies.
public struct GroupedNotificationsResults: Codable, Sendable, Hashable {
    public var accounts: [Account]
    public var statuses: [Status]
    public var notificationGroups: [NotificationGroup]

    enum CodingKeys: String, CodingKey {
        case accounts, statuses
        case notificationGroups = "notification_groups"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accounts = (try? c.decode(LossyArray<Account>.self, forKey: .accounts))?.elements ?? []
        statuses = (try? c.decode(LossyArray<Status>.self, forKey: .statuses))?.elements ?? []
        notificationGroups =
            (try? c.decode(LossyArray<NotificationGroup>.self, forKey: .notificationGroups))?
            .elements ?? []
    }

    public init(
        accounts: [Account] = [], statuses: [Status] = [],
        notificationGroups: [NotificationGroup] = []
    ) {
        self.accounts = accounts
        self.statuses = statuses
        self.notificationGroups = notificationGroups
    }

    public func account(id: String) -> Account? { accounts.first { $0.id == id } }
    public func status(id: String) -> Status? { statuses.first { $0.id == id } }
}

public struct NotificationGroup: Codable, Sendable, Hashable, Identifiable {
    /// Built from what the group *is* (`favourite-{status id}`, `follow-all`)
    /// and never from the ids in it, so it still names the same group after
    /// more arrive. Ungrouped kinds are keyed `ungrouped-{id}`.
    public var groupKey: String
    @LenientInt public var notificationsCount: Int
    public var type: NotificationKind
    public var mostRecentNotificationID: String
    public var pageMinID: String?
    public var pageMaxID: String?
    public var latestPageNotificationAt: Date?
    public var sampleAccountIDs: [String]
    @FlexibleOptionalID public var statusID: String?

    public var id: String { groupKey }

    enum CodingKeys: String, CodingKey {
        case type
        case groupKey = "group_key"
        case notificationsCount = "notifications_count"
        case mostRecentNotificationID = "most_recent_notification_id"
        case pageMinID = "page_min_id"
        case pageMaxID = "page_max_id"
        case latestPageNotificationAt = "latest_page_notification_at"
        case sampleAccountIDs = "sample_account_ids"
        case statusID = "status_id"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groupKey = try c.decodeIfPresent(String.self, forKey: .groupKey) ?? ""
        _notificationsCount = try c.decode(LenientInt.self, forKey: .notificationsCount)
        type = try c.decodeIfPresent(NotificationKind.self, forKey: .type) ?? .unknownCase
        mostRecentNotificationID =
            (try? c.decode(FlexibleID.self, forKey: .mostRecentNotificationID).wrappedValue) ?? ""
        pageMinID = try? c.decode(FlexibleOptionalID.self, forKey: .pageMinID).wrappedValue
        pageMaxID = try? c.decode(FlexibleOptionalID.self, forKey: .pageMaxID).wrappedValue
        latestPageNotificationAt = try c.decodeIfPresent(
            Date.self, forKey: .latestPageNotificationAt)
        sampleAccountIDs =
            (try? c.decode(LossyArray<FlexibleID>.self, forKey: .sampleAccountIDs))?.elements.map(
                \.wrappedValue) ?? []
        _statusID = try c.decode(FlexibleOptionalID.self, forKey: .statusID)
    }

    public init(
        groupKey: String, notificationsCount: Int, type: NotificationKind,
        mostRecentNotificationID: String, pageMinID: String? = nil, pageMaxID: String? = nil,
        latestPageNotificationAt: Date? = nil, sampleAccountIDs: [String] = [],
        statusID: String? = nil
    ) {
        self.groupKey = groupKey
        _notificationsCount = .init(wrappedValue: notificationsCount)
        self.type = type
        self.mostRecentNotificationID = mostRecentNotificationID
        self.pageMinID = pageMinID
        self.pageMaxID = pageMaxID
        self.latestPageNotificationAt = latestPageNotificationAt
        self.sampleAccountIDs = sampleAccountIDs
        _statusID = .init(wrappedValue: statusID)
    }
}

extension FlexibleID: Identifiable {
    public var id: String { wrappedValue }
}
