// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// The feeds' models, kept by the window's shell rather than by the screens
/// that show them.
///
/// Every feed screen held its `TimelineModel` in `@State`, which lives as
/// long as the view's identity. Folding or unfolding an iPhone Duo swaps the
/// whole shell — tab bar for sidebar — so every feed was built again from
/// nothing: the pages it had loaded, where the reader was in it, and the
/// short that was playing were all gone. A screen now asks the shell for its
/// model by timeline, and one built again gets the same one back, with its
/// rows and its `readingAnchorID`.
///
/// Per window, not per account: two iPad windows showing the same feed each
/// keep their own place in it. Only the account on show is kept — switching
/// accounts starts the new one's feeds afresh, as the shell's identity does
/// (docs/03 §6) — and only the few most recently used feeds, so a reader who
/// visits every feed and every source does not keep them all in memory.
typealias FeedModels = KeyedModelCache<TimelineModel>

@MainActor
final class KeyedModelCache<Model: AnyObject> {
    /// Feeds and their sources: four feeds in three sources each is twelve,
    /// and a reader moves between a handful.
    nonisolated static var defaultCapacity: Int { 8 }

    private let capacity: Int
    private var accountID: UUID?
    private var models: [TimelineKey: Model] = [:]
    /// Least recently asked for first.
    private var recency: [TimelineKey] = []

    /// The feed Shorts' own switch was on. Shorts chooses its source along
    /// its top rather than through the shell's source menu, so the shell has
    /// nowhere else to keep it.
    var shortsSource: TimelineSource?

    init(capacity: Int = KeyedModelCache.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    /// The model for this timeline of this account: the one already kept, or
    /// a new one from `make`, kept from now on.
    func model(for key: TimelineKey, accountID: UUID, make: () -> Model) -> Model {
        if self.accountID != accountID {
            models.removeAll()
            recency.removeAll()
            shortsSource = nil
            self.accountID = accountID
        }
        recency.removeAll { $0 == key }
        recency.append(key)
        if let kept = models[key] { return kept }
        let made = make()
        models[key] = made
        if recency.count > capacity {
            models[recency.removeFirst()] = nil
        }
        return made
    }

    /// The model if one is kept, without making or touching one.
    func existing(for key: TimelineKey, accountID: UUID) -> Model? {
        guard self.accountID == accountID else { return nil }
        return models[key]
    }
}

extension KeyedModelCache where Model == TimelineModel {
    func model(for key: TimelineKey, session: AccountSession) -> TimelineModel {
        model(for: key, accountID: session.id) { TimelineModel(key: key, session: session) }
    }
}

extension TimelineModel {
    /// The shell's model for this feed when it keeps one, or a model of the
    /// screen's own for a timeline nobody keeps (a hashtag, a list).
    static func kept(
        for key: TimelineKey, session: AccountSession, in models: FeedModels?
    ) -> TimelineModel {
        models?.model(for: key, session: session) ?? TimelineModel(key: key, session: session)
    }
}
