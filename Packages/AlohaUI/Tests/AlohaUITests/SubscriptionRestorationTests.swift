import AlohaModels
import Testing
@testable import AlohaUI

@Suite("Subscription removal recovery")
struct SubscriptionRestorationTests {
    @Test("A failed removal does not restore successful removals or discard new feeds")
    func partialFailure() {
        let removed = SubscriptionFeed(id: "removed")
        let refused = SubscriptionFeed(id: "refused")
        let retained = SubscriptionFeed(id: "retained")
        let added = SubscriptionFeed(id: "added")
        let result = SubscriptionsView.restoring(refused,
            in: [retained, added], previous: [removed, refused, retained])
        #expect(result.map(\.id) == ["retained", "refused", "added"])
        #expect(!result.contains { $0.id == removed.id })
    }

    @Test("A refreshed entry wins over the older rollback snapshot")
    func noDuplicateAfterRefresh() {
        let original = SubscriptionFeed(id: "feed", title: "Old title")
        let refreshed = SubscriptionFeed(id: "feed", title: "Updated title")
        #expect(SubscriptionsView.restoring(original,
            in: [refreshed], previous: [original]) == [refreshed])
    }
}
