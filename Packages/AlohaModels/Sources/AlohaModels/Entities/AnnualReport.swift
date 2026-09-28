// SPDX-License-Identifier: MIT

import Foundation

/// How an account was used over a year, in one word. Mastodon's archetypes,
/// which Nextcloud Social serves verbatim (`AnnualReportService::archetype`).
public enum AnnualArchetype: String, UnknownPreserving {
    /// Wrote almost nothing.
    case lurker
    /// Mostly boosted other people.
    case booster
    /// Mostly asked questions.
    case pollster
    /// Mostly answered other people.
    case replier
    /// Mostly wrote their own posts, and was read.
    case oracle
    case unknownCase = "__unknown"

    public static func unknown(_ raw: String) -> AnnualArchetype { .unknownCase }
    public var isUnknown: Bool { self == .unknownCase }
}

/// One month of the year: what was written in it, and who arrived.
public struct AnnualMonth: Codable, Sendable, Hashable, Identifiable {
    /// 1–12.
    public var month: Int
    public var statuses: Int
    public var followers: Int

    public var id: Int { month }

    enum CodingKeys: String, CodingKey { case month, statuses, followers }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        month = (try? c.decode(LenientInt.self, forKey: .month).wrappedValue) ?? 0
        statuses = (try? c.decode(LenientInt.self, forKey: .statuses).wrappedValue) ?? 0
        followers = (try? c.decode(LenientInt.self, forKey: .followers).wrappedValue) ?? 0
    }

    public init(month: Int, statuses: Int = 0, followers: Int = 0) {
        self.month = month
        self.statuses = statuses
        self.followers = followers
    }
}

/// A hashtag the account used, and how often.
public struct AnnualHashtag: Codable, Sendable, Hashable, Identifiable {
    public var name: String
    public var count: Int

    public var id: String { name }

    enum CodingKeys: String, CodingKey { case name, count }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        count = (try? c.decode(LenientInt.self, forKey: .count).wrappedValue) ?? 0
    }

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

/// The three posts of the year, each named by the status id the wrapper's
/// `statuses` list is keyed by. Any of them may be absent — a year with no
/// boosted post has no `by_reblogs`.
public struct AnnualTopStatuses: Codable, Sendable, Hashable {
    public var byReblogs: String?
    public var byReplies: String?
    public var byFavourites: String?

    enum CodingKeys: String, CodingKey {
        case byReblogs = "by_reblogs"
        case byReplies = "by_replies"
        case byFavourites = "by_favourites"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        byReblogs = (try? c.decode(FlexibleOptionalID.self, forKey: .byReblogs))?.wrappedValue
        byReplies = (try? c.decode(FlexibleOptionalID.self, forKey: .byReplies))?.wrappedValue
        byFavourites = (try? c.decode(FlexibleOptionalID.self, forKey: .byFavourites))?.wrappedValue
    }

    public init(byReblogs: String? = nil, byReplies: String? = nil, byFavourites: String? = nil) {
        self.byReblogs = byReblogs
        self.byReplies = byReplies
        self.byFavourites = byFavourites
    }

    /// The distinct ids, in the order the report presents them.
    public var ids: [String] {
        var seen: Set<String> = []
        return [byReblogs, byReplies, byFavourites].compactMap { $0 }.filter {
            seen.insert($0).inserted
        }
    }
}

/// What the year held.
public struct AnnualReportData: Codable, Sendable, Hashable {
    public var archetype: AnnualArchetype
    public var timeSeries: [AnnualMonth]
    public var topHashtags: [AnnualHashtag]
    public var topStatuses: AnnualTopStatuses

    enum CodingKeys: String, CodingKey {
        case archetype
        case timeSeries = "time_series"
        case topHashtags = "top_hashtags"
        case topStatuses = "top_statuses"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        archetype = (try? c.decode(AnnualArchetype.self, forKey: .archetype)) ?? .unknownCase
        timeSeries =
            (try? c.decode(LossyArray<AnnualMonth>.self, forKey: .timeSeries))?.elements ?? []
        topHashtags =
            (try? c.decode(LossyArray<AnnualHashtag>.self, forKey: .topHashtags))?.elements ?? []
        topStatuses = (try? c.decode(AnnualTopStatuses.self, forKey: .topStatuses)) ?? .init()
    }

    public init(
        archetype: AnnualArchetype = .unknownCase, timeSeries: [AnnualMonth] = [],
        topHashtags: [AnnualHashtag] = [], topStatuses: AnnualTopStatuses = .init()
    ) {
        self.archetype = archetype
        self.timeSeries = timeSeries
        self.topHashtags = topHashtags
        self.topStatuses = topStatuses
    }

    /// The busiest month, for the one line that summarises the chart.
    public var busiestMonth: AnnualMonth? {
        timeSeries.filter { $0.statuses > 0 }.max { $0.statuses < $1.statuses }
    }

    public var totalStatuses: Int { timeSeries.reduce(0) { $0 + $1.statuses } }
    public var totalFollowers: Int { timeSeries.reduce(0) { $0 + $1.followers } }
}

/// One year's report. Mastodon's `#Wrapstodon`, which Nextcloud Social serves
/// at `/api/v1/annual_reports` and has no web page of its own for (docs/02 §2).
public struct AnnualReport: Codable, Sendable, Hashable, Identifiable {
    public var year: Int
    public var data: AnnualReportData
    public var schemaVersion: Int
    /// Mastodon's points at a public page; this server has none and sends null.
    public var shareURL: URL?
    public var accountID: String

    public var id: Int { year }

    enum CodingKeys: String, CodingKey {
        case year, data
        case schemaVersion = "schema_version"
        case shareURL = "share_url"
        case accountID = "account_id"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        year = (try? c.decode(LenientInt.self, forKey: .year).wrappedValue) ?? 0
        data = (try? c.decode(AnnualReportData.self, forKey: .data)) ?? .init()
        schemaVersion = (try? c.decode(LenientInt.self, forKey: .schemaVersion).wrappedValue) ?? 1
        shareURL = (try? c.decode(LenientURL.self, forKey: .shareURL))?.wrappedValue
        accountID = (try? c.decode(FlexibleID.self, forKey: .accountID).wrappedValue) ?? ""
    }

    public init(
        year: Int, data: AnnualReportData = .init(), schemaVersion: Int = 1,
        shareURL: URL? = nil, accountID: String = ""
    ) {
        self.year = year
        self.data = data
        self.schemaVersion = schemaVersion
        self.shareURL = shareURL
        self.accountID = accountID
    }
}

/// Mastodon's `WrappedAnnualReports`: the reports, plus the accounts and
/// statuses they name — so the three best posts draw without a second round of
/// requests.
public struct WrappedAnnualReports: Codable, Sendable, Hashable {
    public var annualReports: [AnnualReport]
    public var accounts: [Account]
    public var statuses: [Status]

    enum CodingKeys: String, CodingKey {
        case annualReports = "annual_reports"
        case accounts, statuses
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        annualReports =
            (try? c.decode(LossyArray<AnnualReport>.self, forKey: .annualReports))?.elements ?? []
        accounts = (try? c.decode(LossyArray<Account>.self, forKey: .accounts))?.elements ?? []
        statuses = (try? c.decode(LossyArray<Status>.self, forKey: .statuses))?.elements ?? []
    }

    public init(
        annualReports: [AnnualReport] = [], accounts: [Account] = [], statuses: [Status] = []
    ) {
        self.annualReports = annualReports
        self.accounts = accounts
        self.statuses = statuses
    }

    /// The status behind one of a report's `top_statuses` ids.
    public func status(_ id: String?) -> Status? {
        guard let id else { return nil }
        return statuses.first { $0.id == id }
    }
}

/// `GET /api/v1/annual_reports/{year}/state`. `generating` never comes back
/// from this server: the report is a query rather than a job.
public struct AnnualReportState: Codable, Sendable, Hashable {
    public enum State: String, UnknownPreserving {
        case available
        case pending
        case generating
        case ineligible
        case unknownCase = "__unknown"

        public static func unknown(_ raw: String) -> State { .unknownCase }
        public var isUnknown: Bool { self == .unknownCase }
    }

    public var state: State

    enum CodingKeys: String, CodingKey { case state }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = (try? c.decode(State.self, forKey: .state)) ?? .ineligible
    }

    public init(state: State) { self.state = state }
}
