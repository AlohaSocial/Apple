// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import Foundation

/// What the search screen shows: the shape of the whole answer, or one kind
/// of result paged as far as the server goes.
///
/// `/api/v2/search` answers at most `limit` of each kind and honours
/// `offset` only once `type` names a single kind, so "All" can never reach
/// the twenty-first account. A scope can (docs/05 §7).
nonisolated enum SearchScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case accounts
    case hashtags
    case statuses

    var id: String { rawValue }

    /// How many of each kind "All" asks for.
    static let allLimit = 20
    /// How many people and hashtags "All" shows before "See all": the
    /// posts are what most searches are for, and twenty people above them
    /// pushed them off the screen.
    static let allPreview = 5
    /// One page of a single scope. Mastodon caps a search page at forty.
    static let pageSize = 20

    /// The `type` a scope sends; "All" sends none.
    var resultType: Endpoint.search.ResultType? {
        switch self {
        case .all: nil
        case .accounts: .accounts
        case .hashtags: .hashtags
        case .statuses: .statuses
        }
    }

    /// Whether this scope shows results of `type`.
    func shows(_ type: Endpoint.search.ResultType) -> Bool {
        resultType == nil || resultType == type
    }

    var title: String {
        switch self {
        case .all: String(localized: "All", comment: "Search scope")
        case .accounts: String(localized: "People", comment: "Search scope")
        case .hashtags: String(localized: "Hashtags", comment: "Search scope")
        case .statuses: String(localized: "Posts", comment: "Search scope")
        }
    }

    /// Whether "All" holds back results of `type` that its own scope would
    /// show: more than it previews, or a full page, which may have more
    /// behind it.
    static func hasMore(than count: Int, of type: Endpoint.search.ResultType) -> Bool {
        let preview = type == .statuses ? allLimit : allPreview
        return count > preview || count >= allLimit
    }
}

/// Paging one scope of a search.
nonisolated enum SearchPaging {
    /// Search sends no `Link` header, so a full page is the only sign of
    /// another; a short or empty one is the end.
    static func mayHaveMore(received: Int, limit: Int = SearchScope.pageSize) -> Bool {
        received > 0 && received >= limit
    }

    /// The next page of one kind added under what is shown, leaving out what
    /// the server sent again — an index that changed between two pages
    /// shifts the offsets.
    static func appending(
        _ page: SearchResults, to results: SearchResults, type: Endpoint.search.ResultType
    ) -> SearchResults {
        var merged = results
        switch type {
        case .accounts:
            var seen = Set(merged.accounts.map(\.id))
            merged.accounts += page.accounts.filter { seen.insert($0.id).inserted }
        case .hashtags:
            var seen = Set(merged.hashtags.map { $0.name.lowercased() })
            merged.hashtags += page.hashtags.filter { seen.insert($0.name.lowercased()).inserted }
        case .statuses:
            var seen = Set(merged.statuses.map(\.id))
            merged.statuses += page.statuses.filter { seen.insert($0.id).inserted }
        }
        return merged
    }
}

extension SearchResults {
    /// How many results of one kind came back.
    nonisolated func count(of type: Endpoint.search.ResultType) -> Int {
        switch type {
        case .accounts: accounts.count
        case .hashtags: hashtags.count
        case .statuses: statuses.count
        }
    }
}
