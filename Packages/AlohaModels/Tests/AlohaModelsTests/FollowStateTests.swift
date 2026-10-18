// SPDX-License-Identifier: MIT

import Testing

@testable import AlohaModels

@Suite("Follow button state")
struct FollowStateTests {
    @Test("A pending follow of an open account reads as following")
    func openAccountPending() {
        let pending = Relationship(id: "1", requested: true)
        #expect(pending.followState(locked: false) == .following)
        #expect(pending.awaitsAutomaticAccept(locked: false))
    }

    @Test("Only a locked account reads as requested")
    func lockedAccountPending() {
        let pending = Relationship(id: "1", requested: true)
        #expect(pending.followState(locked: true) == .requested)
        #expect(!pending.awaitsAutomaticAccept(locked: true))
    }

    @Test("An accepted follow reads as following whether locked or not")
    func accepted() {
        let following = Relationship(id: "1", following: true)
        #expect(following.followState(locked: false) == .following)
        #expect(following.followState(locked: true) == .following)
        #expect(!following.awaitsAutomaticAccept(locked: false))
    }

    @Test("No follow reads as not following")
    func none() {
        let none = Relationship(id: "1")
        #expect(none.followState(locked: false) == .notFollowing)
        #expect(none.followState(locked: true) == .notFollowing)
        #expect(!none.isFollowingOrRequested)
    }

    @Test("Following and requested both count as something to undo")
    func undo() {
        #expect(Relationship(id: "1", following: true).isFollowingOrRequested)
        #expect(Relationship(id: "1", requested: true).isFollowingOrRequested)
    }
}
