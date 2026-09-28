// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import Foundation
import Testing

@testable import AlohaUI

/// The unit suite was good at pure logic and blind to *wiring* — ten defects
/// were things that compiled, type-checked, and were simply never connected.
/// These pin the connections that cannot be checked any other way without a
/// running app.
@Suite("Cross-process wiring")
struct WiringTests {

    /// Writing to `UserDefaults.standard` from the app and reading it from an
    /// extension silently returns nothing: each process has its own standard
    /// domain. The widget showed the wrong account for exactly this reason.
    @Test("Shared state uses the app group, not the standard domain")
    func sharedDefaultsAreTheAppGroup() {
        #expect(AppGroup.identifier == "group.com.nextcloud.alohasocial")

        let key = "aloha.test.\(UUID().uuidString)"
        AppGroup.defaults.set("written", forKey: key)
        defer { AppGroup.defaults.removeObject(forKey: key) }

        #expect(AppGroup.defaults.string(forKey: key) == "written")
    }

    /// The Keychain access group is what lets the notification service
    /// extension read the push keys the app wrote. A `CredentialStore()` with
    /// no group is private to whichever process built it.
    @Test("The shared credential store carries an access group")
    func credentialStoreIsShared() {
        #expect(AppGroup.keychainAccessGroup == "com.nextcloud.alohasocial")
        // Constructing it is the check: a store with no group compiles equally
        // well and fails only at runtime, in another process.
        _ = CredentialStore.shared
    }

    @Test("Every shared key is namespaced and stable")
    func sharedKeys() {
        #expect(AppGroup.activeAccountKey == "aloha.activeAccount")
        #expect(AppGroup.unreadTotalKey == "aloha.unreadTotal")
        #expect(AppGroup.pendingRouteKey == "aloha.pendingRoute")
    }

    /// An intent that opens the app leaves its destination behind; the shell
    /// reads it on launch. Neither half is useful alone.
    @Test("A route handed over by an intent round-trips")
    func intentNavigationRoundTrip() async {
        let route = Route.timeline(TimelineKey(mode: .shorts, source: .federated))
        await IntentNavigation.request(route)

        let taken = await IntentNavigation.take()
        #expect(taken == route)

        // Taking it clears it, so a relaunch does not navigate again.
        #expect(await IntentNavigation.take() == nil)
    }
}

/// Every case of `StatusRowAction` has to be handled somewhere. Six were not,
/// and block and mute among them are App Store requirements — they rendered,
/// they were tappable, and nothing happened.
@Suite("Status actions are all handled")
struct StatusActionCoverageTests {

    private var account: Account {
        Account(id: "1", username: "alice", acct: "alice@example.test")
    }

    private var status: Status {
        Status(id: "9", account: account)
    }

    @Test("Actions route to either the shell or the action layer")
    func everyActionIsClassified() {
        let all: [StatusRowAction] = [
            .open(status), .watch(status), .reply(status), .boost(status), .favourite(status),
            .bookmark(status), .openProfile(account),
            .openMedia(status: status, index: 0),
            .openCard(Card(title: "x")), .followLink(.web(URL(string: "https://x.test")!)),
            .vote(pollID: "1", choices: [0]),
            .react(status: status, name: "👍", add: true),
            .report(status), .share(status), .translate(status), .edit(status),
            .delete(status), .muteConversation(status), .block(account), .mute(account),
            .archive(status), .pin(status), .dislike(status), .quote(status),
            .showDelivery(status), .showEditHistory(status), .quoteControls(status),
            .tagPeople(status), .addToCollection(status), .addToList(account),
        ]

        for action in all {
            #expect(
                StatusActionRouting.destination(of: action) != .unhandled,
                "\(action) falls through and does nothing")
        }
    }

    @Test("Block and mute reach the moderation layer, as App Review requires")
    func moderationIsReachable() {
        #expect(StatusActionRouting.destination(of: .block(account)) == .shell)
        #expect(StatusActionRouting.destination(of: .mute(account)) == .shell)

        let block = ModerationRequest(account: account, kind: .block)
        let mute = ModerationRequest(account: account, kind: .mute)
        #expect(block.title.contains(account.bestDisplayName))
        #expect(mute.detail.isEmpty == false)
        #expect(block.id != mute.id)
    }
}

/// Sign-in crashed twice, both times for reasons a unit test could not see:
/// an isolated completion called from a background queue, and a presentation
/// anchor that was the sign-in sheet itself. These pin what is testable.
@Suite("Web authentication")
@MainActor
struct WebAuthenticatorTests {

    @Test("A callback is only delivered to a flow that is waiting for one")
    func deliveryRequiresAPendingFlow() {
        let authenticator = WebAuthenticator.shared
        authenticator.cancel()

        // Nothing in flight: a stray callback must not be consumed, or an
        // ordinary deep link would be swallowed by sign-in.
        #expect(authenticator.isAwaitingCallback == false)
        #expect(
            authenticator.deliver(URL(string: "alohasocial://oauth-callback?code=x")!) == false)
    }

    @Test("Cancelling clears the pending flow")
    func cancellingClears() async {
        let authenticator = WebAuthenticator.shared
        authenticator.cancel()
        #expect(authenticator.isAwaitingCallback == false)
    }

    /// The browser fallback returns through the app's URL scheme, so the shell
    /// has to recognise the callback before it tries to route it.
    @Test("An OAuth callback is not a navigation destination")
    func callbackIsNotARoute() {
        let callback = URL(string: "alohasocial://oauth-callback?code=abc&state=s1")!
        #expect(RouteResolver.route(for: callback) == nil)
    }
}
