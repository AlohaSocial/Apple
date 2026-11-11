// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaUI

/// The shell's half of opening a link, a notification or a Spotlight result
/// that belongs to another account: the switch resets the screens, and the
/// route opened with it has to survive that reset.
@Suite("Opening a route for another account")
struct AccountSwitchNavigationTests {
    private let alice = UUID()
    private let bob = UUID()
    private let post = Route.thread(statusID: "109")

    @Test("A route opened as the account switches waits for the reset, then opens")
    func heldAcrossTheSwitch() {
        var navigation = AccountSwitchNavigation()
        _ = navigation.didShow(alice)

        // The caller has just made Bob active; the shell still shows Alice.
        let opensNow = navigation.shouldOpenNow(post, activeAccountID: bob)
        let afterReset = navigation.didShow(bob)
        #expect(!opensNow)
        #expect(afterReset == post)

        // Handed back once, not again on the next switch.
        _ = navigation.didShow(alice)
        let later = navigation.didShow(bob)
        #expect(later == nil)
    }

    @Test("An ordinary switch has nothing to open and starts from the top")
    func ordinarySwitch() {
        var navigation = AccountSwitchNavigation()
        _ = navigation.didShow(alice)
        let afterReset = navigation.didShow(bob)
        #expect(afterReset == nil)
    }

    @Test("A route meant for one account is never opened on another")
    func onlyForItsAccount() {
        let carol = UUID()
        var navigation = AccountSwitchNavigation()
        _ = navigation.didShow(alice)
        let opensNow = navigation.shouldOpenNow(post, activeAccountID: bob)
        // A second switch overtook the first before the screen caught up.
        let afterReset = navigation.didShow(carol)
        #expect(!opensNow)
        #expect(afterReset == nil)
    }

    @Test("Without a switch in flight a route opens at once")
    func noSwitch() {
        var navigation = AccountSwitchNavigation()
        // Before the shell has shown any account — launch, loading.
        let beforeAnyAccount = navigation.shouldOpenNow(post, activeAccountID: alice)
        _ = navigation.didShow(alice)
        let sameAccount = navigation.shouldOpenNow(post, activeAccountID: alice)
        let signedOut = navigation.shouldOpenNow(post, activeAccountID: nil)
        #expect(beforeAnyAccount)
        #expect(sameAccount)
        #expect(signedOut)
    }

    @Test("A switch that never reached the screen leaves nothing behind")
    func abandonedSwitch() {
        var navigation = AccountSwitchNavigation()
        _ = navigation.didShow(alice)
        let heldForBob = navigation.shouldOpenNow(post, activeAccountID: bob)
        // Switched straight back before the shell redrew: the next route on
        // Alice opens, and a later switch to Bob brings nothing with it.
        let backOnAlice = navigation.shouldOpenNow(.notifications, activeAccountID: alice)
        let laterBob = navigation.didShow(bob)
        #expect(!heldForBob)
        #expect(backOnAlice)
        #expect(laterBob == nil)
    }
}
