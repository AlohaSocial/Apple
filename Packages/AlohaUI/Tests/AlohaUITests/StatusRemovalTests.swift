// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaStore
import Foundation
import Testing

@testable import AlohaUI

/// Deleting, blocking and muting used to change the store and nothing on
/// screen; these hold the rows to what the store now says.
@Suite("Removed posts leave the screen")
struct StatusRemovalTests {
    private let alice = Account(id: "a", username: "alice", acct: "alice")
    private let bob = Account(id: "b", username: "bob", acct: "bob")

    @Test("A removal reaches the UI on the main actor", .timeLimit(.minutes(1)))
    @MainActor
    func backgroundRemoval() async {
        let accountID = UUID()
        var subscription: AnyObject?
        let received: TimelineStatusRemoval = await withCheckedContinuation { continuation in
            subscription = StatusRemovals.observe { removal in
                guard removal.accountID == accountID else { return }
                MainActor.assertIsolated()
                continuation.resume(returning: removal)
            }
            Task.detached {
                NotificationCenter.default.post(
                    name: TimelineStatusRemoval.notification,
                    object: TimelineStatusRemoval(accountID: accountID, statusIDs: ["1"]))
            }
        }
        withExtendedLifetime(subscription) {}
        #expect(received.statusIDs == ["1"])
    }

    @Test("A deleted post leaves the timeline, and so does a boost of it")
    func deletedPostAndItsBoosts() {
        let original = Status(id: "post", account: alice)
        let boost = Status(id: "boost", account: bob, reblog: Box(original))
        let other = Status(id: "other", account: alice)
        let rows = TimelineModel.removing(
            TimelineStatusRemoval(accountID: UUID(), statusIDs: ["post"]),
            from: [.status(original), .status(boost), .gap(id: "gap"), .status(other)])
        #expect(rows.map(\.id) == ["gap", "other"])
    }

    @Test("A block takes everything the person wrote or boosted")
    func blockTakesAuthor() {
        let theirs = Status(id: "1", account: bob)
        let theirBoost = Status(
            id: "2", account: bob, reblog: Box(Status(id: "x", account: alice)))
        let boostOfThem = Status(
            id: "3", account: alice, reblog: Box(Status(id: "y", account: bob)))
        let unrelated = Status(id: "4", account: alice)
        let rows = TimelineModel.removing(
            TimelineStatusRemoval(accountID: UUID(), authorID: "b"),
            from: [
                .status(theirs), .status(theirBoost), .status(boostOfThem),
                .caughtUpDivider(after: "1"), .status(unrelated),
            ])
        // The divider marks a place in the list, not a post, and stays.
        #expect(rows.map(\.id) == ["caughtUp-1", "4"])
    }

    @Test("An activity goes with its post and with the person blocked")
    func activitiesFollow() {
        let removal = TimelineStatusRemoval(accountID: UUID(), statusIDs: ["gone"], authorID: "b")
        let mine = Status(id: "mine", account: alice)
        let favouriteFromBob = MastodonNotification(
            id: "1", type: .favourite, account: bob, status: mine)
        let favouriteFromCarol = MastodonNotification(
            id: "2", type: .favourite,
            account: Account(id: "c", username: "carol", acct: "carol"), status: mine)
        let onDeleted = MastodonNotification(
            id: "3", type: .favourite,
            account: Account(id: "c", username: "carol", acct: "carol"),
            status: Status(id: "gone", account: alice))

        #expect(NotificationsView.isRemoved(favouriteFromBob, by: removal))
        #expect(!NotificationsView.isRemoved(favouriteFromCarol, by: removal))
        #expect(NotificationsView.isRemoved(onDeleted, by: removal))
    }

    @Test("A group stays while somebody other than the person blocked is in it")
    func groupsFollow() {
        let removal = TimelineStatusRemoval(accountID: UUID(), authorID: "b")
        func group(_ samples: [String], status: String? = "mine") -> NotificationGroup {
            NotificationGroup(
                groupKey: samples.joined(), notificationsCount: samples.count, type: .favourite,
                mostRecentNotificationID: "1", sampleAccountIDs: samples, statusID: status)
        }
        let statuses = ["mine": Status(id: "mine", account: alice)]

        #expect(NotificationsView.isRemoved(group(["b"]), statuses: statuses, by: removal))
        #expect(!NotificationsView.isRemoved(group(["b", "c"]), statuses: statuses, by: removal))
        #expect(
            NotificationsView.isRemoved(
                group(["c"]), statuses: statuses,
                by: TimelineStatusRemoval(accountID: UUID(), statusIDs: ["mine"])))
    }
}
