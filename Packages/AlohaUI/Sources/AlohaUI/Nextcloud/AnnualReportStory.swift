// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// The year in review as a sequence of cards, worked out once from the report
/// rather than in the body, so the player, the share renderer and the tests
/// all read the same list.
///
/// A card is only made for something the year actually holds: a year without
/// hashtags has no hashtag card, rather than a card that says "none". The
/// opening and closing cards are always there, so even a quiet year has a
/// beginning and an end.
nonisolated enum AnnualReportStory {
    /// One of the three posts that travelled furthest, and which way it did.
    struct BestPost: Hashable, Sendable {
        enum Kind: Hashable, Sendable { case boosted, replied, favourited }
        var kind: Kind
        var status: Status
    }

    enum Card: Hashable, Sendable, Identifiable {
        /// The year and the archetype in a sentence.
        case opening
        /// Posts written, new followers (when numbers are shown) and the
        /// busiest month.
        case numbers
        /// The month-by-month chart.
        case months
        /// The hashtags the account used most, at most five.
        case hashtags([AnnualHashtag])
        /// The posts that went furthest.
        case bestPosts([BestPost])
        /// "That was the year."
        case closing

        var id: String {
            switch self {
            case .opening: "opening"
            case .numbers: "numbers"
            case .months: "months"
            case .hashtags: "hashtags"
            case .bestPosts: "best"
            case .closing: "closing"
            }
        }
    }

    /// How long a card stays before the next one, when cards advance on
    /// their own. Long enough to read a sentence and a number twice.
    static let cardDuration: Duration = .seconds(6)

    /// More than five hashtags no longer fits a phone-sized card at the
    /// larger text sizes, and the sixth is rarely the interesting one.
    static let hashtagLimit = 5

    static func cards(
        for report: AnnualReport, in wrapped: WrappedAnnualReports?
    ) -> [Card] {
        var cards: [Card] = [.opening]
        let data = report.data
        if data.totalStatuses > 0 || data.totalFollowers > 0 { cards.append(.numbers) }
        if data.timeSeries.contains(where: { $0.statuses > 0 }) { cards.append(.months) }
        if !data.topHashtags.isEmpty {
            let top = data.topHashtags.sorted { $0.count > $1.count }
            cards.append(.hashtags(Array(top.prefix(hashtagLimit))))
        }
        let best = bestPosts(data.topStatuses, in: wrapped)
        if !best.isEmpty { cards.append(.bestPosts(best)) }
        cards.append(.closing)
        return cards
    }

    /// The three posts, each once: a post that was both the most boosted and
    /// the most favourited is shown under the first heading only, rather
    /// than twice on one card.
    static func bestPosts(
        _ top: AnnualTopStatuses, in wrapped: WrappedAnnualReports?
    ) -> [BestPost] {
        guard let wrapped else { return [] }
        var seen: Set<String> = []
        let entries: [(BestPost.Kind, String?)] = [
            (.boosted, top.byReblogs), (.replied, top.byReplies), (.favourited, top.byFavourites),
        ]
        return entries.compactMap { kind, id in
            guard let status = wrapped.status(id), seen.insert(status.id).inserted else {
                return nil
            }
            return BestPost(kind: kind, status: status)
        }
    }

    /// Where a tap on a card goes: the first third of the width goes back,
    /// the rest goes forward — the convention every story player shares,
    /// mirrored for a right-to-left layout so "back" stays on the side the
    /// reader came from.
    static func tapGoesBack(atX x: CGFloat, width: CGFloat, rightToLeft: Bool) -> Bool {
        guard width > 0 else { return false }
        let fraction = x / width
        return rightToLeft ? fraction > 2.0 / 3.0 : fraction < 1.0 / 3.0
    }

    /// Whether the cards move on by themselves. Not under Reduce Motion — the
    /// same rule as Shorts' auto-advance (docs/12 §3) — and not with VoiceOver
    /// running, where a card that changes while it is being read aloud is a
    /// card nobody hears the end of. Paging by hand works in every case.
    static func advancesAutomatically(reduceMotion: Bool, voiceOver: Bool) -> Bool {
        !reduceMotion && !voiceOver
    }
}
