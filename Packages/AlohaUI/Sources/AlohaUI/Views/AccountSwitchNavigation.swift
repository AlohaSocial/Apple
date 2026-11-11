// SPDX-License-Identifier: MIT

import Foundation

/// A destination opened in the same breath as a switch of account — a link,
/// a notification or a Spotlight result that belongs to another account.
///
/// Those callers switch the account and then open the route at once, which
/// pushed it onto the screen of the account being left; the shell's reset on
/// the switch, a moment later, then cleared every pushed screen, the new one
/// with them. The person landed on the right account and on its timeline,
/// never on the post. The shell now asks this first: while a switch is in
/// flight, the route is held, and handed back once the shell has reset for
/// the account it was meant for. An ordinary switch, with nothing opened,
/// still starts from the top.
struct AccountSwitchNavigation: Equatable {
    /// The account the shell is showing, as of its last reset. Nil until it
    /// has shown one, when nothing is in flight that a route could be lost to.
    private(set) var shownAccountID: UUID?
    private var pending: Pending?

    private struct Pending: Equatable {
        let accountID: UUID
        let route: Route
    }

    /// Whether `route` can be opened now. When the active account is not yet
    /// the one on screen, the route is held for it and this answers false.
    mutating func shouldOpenNow(_ route: Route, activeAccountID: UUID?) -> Bool {
        guard let shownAccountID, let activeAccountID, activeAccountID != shownAccountID
        else {
            // Nothing in flight; anything still held belonged to a switch
            // that never reached the screen.
            pending = nil
            return true
        }
        pending = Pending(accountID: activeAccountID, route: route)
        return false
    }

    /// The shell now shows `accountID` and has reset its screens for it.
    /// Returns the route held for this account, if one was; one held for
    /// another account is dropped, since its ids mean nothing here.
    mutating func didShow(_ accountID: UUID?) -> Route? {
        shownAccountID = accountID
        defer { pending = nil }
        guard let pending, pending.accountID == accountID else { return nil }
        return pending.route
    }
}
