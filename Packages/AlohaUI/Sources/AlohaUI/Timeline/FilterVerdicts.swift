// SPDX-License-Identifier: MIT

import AlohaHTML
import AlohaModels
import Foundation
import SwiftUI

/// The filters' verdicts for one list of posts, in the one context that list
/// is read in.
///
/// Home and profiles had this inside `TimelineModel`, and every other list —
/// a thread, For you, search, quotes, a shared link, a place — drew its posts
/// with no filtering at all: a post a hide filter was written for stayed on
/// screen there, and a warn filter never collapsed anything. Every list now
/// asks the same object, so a verdict reads the same wherever the post turns
/// up, and only the context differs (Mastodon's filters name the places they
/// apply: home, notifications, public, thread, account).
///
/// It decides with `FilterEvaluator`, which takes the server's own verdict
/// (`status.filtered`, sent with every status) together with the filters
/// synced to this device. Verdicts are cached per content and dropped when
/// the next filter expires, so one that expires stops hiding without a
/// refetch (docs/04 §6).
@MainActor
final class FilterVerdicts {
    let context: FilterContext

    var filters: [Filter] = [] {
        didSet {
            guard filters != oldValue else { return }
            decisions = [:]
            nextExpiry = FilterEvaluator.nextExpiry(of: filters, after: Date())
        }
    }

    private var decisions: [FilterCacheKey: FilterEvaluator.Decision] = [:]
    /// Plain text for keyword matching, parsed off the main actor before a
    /// page is filtered. Only collected while a keyword filter exists.
    private var texts: [FilterCacheKey: String] = [:]
    private var nextExpiry: Date?

    init(context: FilterContext) {
        self.context = context
    }

    /// The filters this account has synced, read again: a filter written in
    /// Settings since the list was first drawn applies on its next load.
    func load(from session: AccountSession) async {
        filters = (try? await session.supportStore.activeFilters(accountID: session.id)) ?? []
    }

    private var hasKeywordFilters: Bool {
        filters.contains { !$0.keywords.isEmpty }
    }

    /// Parses the text keyword filters search, off the main actor, so the
    /// verdicts that follow never parse HTML on it. The posts these quote are
    /// parsed too: a quote is filtered as a post of its own. Nothing to do —
    /// and nothing parsed — while no filter has a keyword.
    func warm(_ statuses: [Status]) async {
        guard hasKeywordFilters else { return }
        for status in statuses + statuses.compactMap(\.displayed.quotedStatus) {
            let key = FilterCacheKey(status)
            guard texts[key] == nil else { continue }
            let body = await RichTextCache.shared.plainText(for: status)
            texts[key] = body + " " + status.displayed.spoilerText
        }
    }

    func decision(for status: Status) -> FilterEvaluator.Decision {
        let now = Date()
        if let expiry = nextExpiry, now >= expiry {
            decisions = [:]
            nextExpiry = FilterEvaluator.nextExpiry(of: filters, after: now)
        }
        let key = FilterCacheKey(status)
        if let cached = decisions[key] { return cached }
        let decided = FilterEvaluator.decision(
            for: status, filters: filters, context: context, now: now, text: texts[key])
        decisions[key] = decided
        return decided
    }

    /// The title a row collapses behind, when a warn filter matched.
    func warning(for status: Status) -> String? {
        guard case .warn(let title) = decision(for: status) else { return nil }
        return title
    }

    func isHidden(_ status: Status) -> Bool {
        decision(for: status) == .hide
    }

    /// The filters read again and the posts' text parsed, ready for verdicts
    /// that cost nothing on the main actor.
    func prepare(_ statuses: [Status], session: AccountSession) async {
        await load(from: session)
        await warm(statuses)
    }

    /// What a hide filter matched, left out.
    func kept(_ statuses: [Status]) -> [Status] {
        statuses.filter { !isHidden($0) }
    }

    /// A fetched page as the list should hold it.
    func screened(_ statuses: [Status], session: AccountSession) async -> [Status] {
        await prepare(statuses, session: session)
        return kept(statuses)
    }

    /// The context Mastodon reads a timeline in, by where its posts come from.
    /// For you is public posts the server picked, not people followed, and is
    /// read as the public timelines are — here and in `InterestsView` alike.
    nonisolated static func context(for source: TimelineSource) -> FilterContext {
        switch source {
        case .home, .list: .home
        case .local, .federated, .hashtag, .trending, .interests: .public
        case .account, .profile: .account
        default: .home
        }
    }
}

extension EnvironmentValues {
    /// The verdicts of the list a row is drawn in, for the post a row quotes:
    /// the quote is fetched by the row, after the list has filtered its own
    /// posts, and is held to the same filters in the same context.
    @Entry var filterVerdicts: FilterVerdicts?
}
