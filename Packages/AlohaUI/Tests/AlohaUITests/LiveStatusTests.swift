// SPDX-License-Identifier: MIT
import AlohaModels
import AlohaStore
import Testing
import Foundation
@testable import AlohaUI

@Suite("Live status reconciliation")
struct LiveStatusTests {
    @Test("Background store notifications reach the UI on the main actor", .timeLimit(.minutes(1)))
    @MainActor
    func backgroundNotification() async {
        let accountID = UUID()
        let account = Account(id: "a", username: "alice", acct: "alice")
        let status = Status(id: "post", account: account, favourited: true)
        var subscription: AnyObject?
        let received: Status = await withCheckedContinuation { continuation in
            subscription = TimelineModel.observeStatusUpdates { update in
                guard update.accountID == accountID else { return }
                MainActor.assertIsolated()
                continuation.resume(returning: update.status)
            }
            Task.detached {
                NotificationCenter.default.post(name: TimelineStatusUpdate.notification,
                    object: TimelineStatusUpdate(accountID: accountID, status: status))
            }
        }
        withExtendedLifetime(subscription) {}
        #expect(received == status)
    }

    @Test("Confirmed counts and interaction flags update original and boosted rows")
    func updatesEveryVisibleCopy() {
        let account = Account(id: "a", username: "alice", acct: "alice")
        let original = Status(id: "post", account: account)
        let wrapper = Status(id: "boost", account: account, reblog: Box(original))
        let unrelated = Status(id: "other", account: account)
        let confirmed = Status(id: "post", account: account, repliesCount: 8,
            reblogsCount: 4, favouritesCount: 12, favourited: true, reblogged: true)
        let rows = TimelineModel.replacing(confirmed,
            in: [.status(original), .status(wrapper), .status(unrelated)])
        #expect(rows[0].status == confirmed)
        #expect(rows[1].status?.id == "boost")
        #expect(rows[1].status?.displayed == confirmed)
        #expect(rows[2].status == unrelated)
    }
}
