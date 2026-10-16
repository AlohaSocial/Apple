// SPDX-License-Identifier: MIT

import AlohaNetwork
import AlohaStore
import Foundation

/// What an account leaves outside the store and the Keychain, and signing out
/// has to find: the push registration, the widgets' snapshots and taps, and a
/// Focus that was set up for it.
///
/// Kept apart from `AppEnvironment.removeAccount` so the list can be tested
/// against a scratch `UserDefaults` and scratch folders — a teardown that
/// forgets one place is a signed-out account still on the Home Screen.
enum AccountTeardown {
    static func pushRegistrationKey(for id: UUID) -> String {
        "aloha.ncPush.\(id.uuidString)"
    }

    static func removeSharedState(
        for id: UUID, in defaults: UserDefaults,
        memories: MemoriesSnapshotStore? = .shared,
        topShelf: TopShelfSnapshotStore? = .shared
    ) {
        defaults.removeObject(forKey: pushRegistrationKey(for: id))
        WidgetFavourites.removeAll(accountID: id, in: defaults)
        if let memories, memories.read()?.accountID == id { memories.remove() }
        if let topShelf, topShelf.read()?.accountID == id { topShelf.remove() }
        if let data = defaults.data(forKey: FocusFilterState.key),
            let focus = try? JSONDecoder().decode(FocusFilterState.self, from: data),
            focus.accountID == id
        {
            // A Focus kept for an account that is gone would hold the app on
            // nothing; it falls back to "any account" until it is set again.
            var kept = focus
            kept.accountID = nil
            if kept == .none {
                defaults.removeObject(forKey: FocusFilterState.key)
            } else if let encoded = try? JSONEncoder().encode(kept) {
                defaults.set(encoded, forKey: FocusFilterState.key)
            }
        }
    }
}
