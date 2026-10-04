import AlohaModels
import AlohaStore
import Testing
@testable import AlohaUI

@Suite("Live status reconciliation")
struct LiveStatusTests {
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
