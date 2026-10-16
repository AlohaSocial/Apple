// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaUI

@Suite("Focus filter")
struct FocusFilterTests {
    private let work = UUID()
    private let personal = UUID()

    @Test("No Focus lets everything through")
    func noFocusAllowsAll() {
        #expect(FocusFilterState.none.allows(kind: .favourite, accountID: work))
    }

    @Test("A Focus on one account holds the other account's notifications")
    func accountFocus() {
        let focus = FocusFilterState(accountID: work)
        #expect(focus.allows(kind: .mention, accountID: work))
        #expect(!focus.allows(kind: .mention, accountID: personal))
    }

    @Test("Mentions only holds everything that is not a mention")
    func mentionsOnly() {
        let focus = FocusFilterState(mentionsOnly: true)
        #expect(focus.allows(kind: .mention, accountID: personal))
        #expect(!focus.allows(kind: .favourite, accountID: personal))
        #expect(!focus.allows(kind: .follow, accountID: personal))
    }

    @Test("The stored filter round-trips, and the empty one is stored as nothing")
    func storage() {
        let focus = FocusFilterState(accountID: work, mode: .photos, mentionsOnly: true)
        FocusFilterState.store(focus)
        #expect(FocusFilterState.current == focus)
        FocusFilterState.store(.none)
        #expect(FocusFilterState.current == .none)
    }
}
