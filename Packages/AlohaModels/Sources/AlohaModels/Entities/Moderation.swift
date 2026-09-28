// SPDX-License-Identifier: MIT

import Foundation

/// An account as a moderator sees it. Mastodon's `Admin::Account`, which
/// Nextcloud Social serves at `/api/v1/admin/accounts` (`AdminAccount.php`).
///
/// Most of Mastodon's fields are about a login this server does not hold — an
/// account here is a Nextcloud user or a cached remote actor — so `email`,
/// `ip`, `locale` and `role` come back empty and are not shown.
public struct AdminAccount: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var username: String
    /// `nil` for a local account.
    public var domain: String?
    public var createdAt: Date?
    public var confirmed: Bool
    public var approved: Bool
    public var disabled: Bool
    public var silenced: Bool
    public var suspended: Bool
    public var sensitized: Bool
    /// The public account entity, which is what the row actually draws.
    public var account: Account?

    public var isLocal: Bool { domain == nil || domain?.isEmpty == true }

    /// The one word that describes the account's standing, for a badge.
    public var standing: Standing {
        if suspended { return .suspended }
        if silenced { return .silenced }
        if sensitized { return .sensitized }
        return .active
    }

    public enum Standing: Sendable, Hashable {
        case active, silenced, suspended, sensitized
    }

    enum CodingKeys: String, CodingKey {
        case id, username, domain, confirmed, approved, disabled, silenced, suspended, sensitized
        case createdAt = "created_at"
        case account
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        username = (try? c.decode(String.self, forKey: .username)) ?? ""
        let rawDomain = (try? c.decode(String.self, forKey: .domain)) ?? ""
        domain = rawDomain.isEmpty ? nil : rawDomain
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        confirmed = (try? c.decode(LenientBool.self, forKey: .confirmed).wrappedValue) ?? false
        approved = (try? c.decode(LenientBool.self, forKey: .approved).wrappedValue) ?? false
        disabled = (try? c.decode(LenientBool.self, forKey: .disabled).wrappedValue) ?? false
        silenced = (try? c.decode(LenientBool.self, forKey: .silenced).wrappedValue) ?? false
        suspended = (try? c.decode(LenientBool.self, forKey: .suspended).wrappedValue) ?? false
        sensitized = (try? c.decode(LenientBool.self, forKey: .sensitized).wrappedValue) ?? false
        account = try? c.decodeIfPresent(Account.self, forKey: .account)
    }

    public init(
        id: String, username: String, domain: String? = nil, createdAt: Date? = nil,
        confirmed: Bool = true, approved: Bool = true, disabled: Bool = false,
        silenced: Bool = false, suspended: Bool = false, sensitized: Bool = false,
        account: Account? = nil
    ) {
        _id = .init(wrappedValue: id)
        self.username = username
        self.domain = domain
        self.createdAt = createdAt
        self.confirmed = confirmed
        self.approved = approved
        self.disabled = disabled
        self.silenced = silenced
        self.suspended = suspended
        self.sensitized = sensitized
        self.account = account
    }

    /// `@user@host`, the way a moderator reads an account.
    public var handle: String {
        guard let domain, !domain.isEmpty else { return "@\(username)" }
        return "@\(username)@\(domain)"
    }
}

/// What a moderator can do to an account. Mastodon's `type` on
/// `POST /api/v1/admin/accounts/{id}/action`; this server acts on three of them
/// (`AdminApiService::act`).
public enum AdminAccountAction: String, Sendable, Hashable, CaseIterable, Identifiable {
    /// Record the decision and change nothing.
    case none
    /// The account's posts stop reaching people who do not follow it.
    case silence
    /// Nothing of the account is delivered or shown.
    case suspend

    public var id: String { rawValue }
}

/// A report, as a moderator sees it. Mastodon's `Admin::Report`.
public struct AdminReport: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var actionTaken: Bool
    public var actionTakenAt: Date?
    public var category: String
    public var comment: String
    public var forwarded: Bool
    public var createdAt: Date?
    public var updatedAt: Date?
    /// Who reported.
    public var account: Account?
    /// Who was reported.
    public var targetAccount: Account?
    public var assignedAccount: Account?
    public var actionTakenByAccount: Account?
    public var statuses: [Status]

    enum CodingKeys: String, CodingKey {
        case id, category, comment, forwarded, account, statuses
        case actionTaken = "action_taken"
        case actionTakenAt = "action_taken_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case targetAccount = "target_account"
        case assignedAccount = "assigned_account"
        case actionTakenByAccount = "action_taken_by_account"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        actionTaken = (try? c.decode(LenientBool.self, forKey: .actionTaken).wrappedValue) ?? false
        actionTakenAt = try? c.decodeIfPresent(Date.self, forKey: .actionTakenAt)
        category = (try? c.decode(String.self, forKey: .category)) ?? ""
        comment = (try? c.decode(String.self, forKey: .comment)) ?? ""
        forwarded = (try? c.decode(LenientBool.self, forKey: .forwarded).wrappedValue) ?? false
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        account = try? c.decodeIfPresent(Account.self, forKey: .account)
        targetAccount = try? c.decodeIfPresent(Account.self, forKey: .targetAccount)
        assignedAccount = try? c.decodeIfPresent(Account.self, forKey: .assignedAccount)
        actionTakenByAccount = try? c.decodeIfPresent(Account.self, forKey: .actionTakenByAccount)
        statuses = (try? c.decode(LossyArray<Status>.self, forKey: .statuses))?.elements ?? []
    }

    public init(
        id: String, actionTaken: Bool = false, actionTakenAt: Date? = nil, category: String = "",
        comment: String = "", forwarded: Bool = false, createdAt: Date? = nil,
        updatedAt: Date? = nil, account: Account? = nil, targetAccount: Account? = nil,
        assignedAccount: Account? = nil, actionTakenByAccount: Account? = nil,
        statuses: [Status] = []
    ) {
        _id = .init(wrappedValue: id)
        self.actionTaken = actionTaken
        self.actionTakenAt = actionTakenAt
        self.category = category
        self.comment = comment
        self.forwarded = forwarded
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.account = account
        self.targetAccount = targetAccount
        self.assignedAccount = assignedAccount
        self.actionTakenByAccount = actionTakenByAccount
        self.statuses = statuses
    }

    public var isAssigned: Bool { assignedAccount != nil }
}

/// One week of the instance's activity. Mastodon's `/api/v1/instance/activity`,
/// whose every value is a string of seconds or a count (hence `LenientInt`).
///
/// `logins` and `registrations` are always zero here and say so in the server's
/// own docblock: an account is a Nextcloud user, so there is no registration
/// for this app to count.
public struct InstanceActivityWeek: Codable, Sendable, Hashable, Identifiable {
    /// Unix seconds at the Monday the week began.
    public var week: Int
    public var statuses: Int
    public var logins: Int
    public var registrations: Int

    public var id: Int { week }
    public var date: Date { Date(timeIntervalSince1970: TimeInterval(week)) }

    enum CodingKeys: String, CodingKey { case week, statuses, logins, registrations }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        week = (try? c.decode(LenientInt.self, forKey: .week).wrappedValue) ?? 0
        statuses = (try? c.decode(LenientInt.self, forKey: .statuses).wrappedValue) ?? 0
        logins = (try? c.decode(LenientInt.self, forKey: .logins).wrappedValue) ?? 0
        registrations = (try? c.decode(LenientInt.self, forKey: .registrations).wrappedValue) ?? 0
    }

    public init(week: Int, statuses: Int = 0, logins: Int = 0, registrations: Int = 0) {
        self.week = week
        self.statuses = statuses
        self.logins = logins
        self.registrations = registrations
    }
}

/// A server this instance refuses, as its own readers may see it.
/// `/api/v1/instance/domain_blocks` — empty unless the administrator publishes
/// the list.
public struct PublicDomainBlock: Codable, Sendable, Hashable, Identifiable {
    public var domain: String
    public var digest: String
    public var severity: String
    public var comment: String

    public var id: String { digest.isEmpty ? domain : digest }

    enum CodingKeys: String, CodingKey { case domain, digest, severity, comment }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        domain = (try? c.decode(String.self, forKey: .domain)) ?? ""
        digest = (try? c.decode(String.self, forKey: .digest)) ?? ""
        severity = (try? c.decode(String.self, forKey: .severity)) ?? "suspend"
        comment = (try? c.decode(String.self, forKey: .comment)) ?? ""
    }

    public init(
        domain: String, digest: String = "", severity: String = "suspend", comment: String = ""
    ) {
        self.domain = domain
        self.digest = digest
        self.severity = severity
        self.comment = comment
    }
}
