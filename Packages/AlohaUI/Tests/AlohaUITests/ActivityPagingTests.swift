// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import Foundation
import Testing

@testable import AlohaUI

private func group(
    _ key: String, newest: String, min: String? = nil, count: Int = 1
) -> NotificationGroup {
    NotificationGroup(
        groupKey: key, notificationsCount: count, type: .favourite,
        mostRecentNotificationID: newest, pageMinID: min)
}

private func note(_ id: String) -> MastodonNotification {
    MastodonNotification(
        id: id, type: .mention, account: Account(id: "a", username: "alice", acct: "alice"))
}

@Suite("Activity paging")
struct ActivityPagingTests {
    @Test("No chip asks for everything; a chip asks only for its own kinds")
    func types() {
        #expect(ActivityPaging.types(for: [], onAlohaSocial: false).isEmpty)
        #expect(
            ActivityPaging.types(for: [], onAlohaSocial: true)
                == Endpoint.notifications.everyType(onAlohaSocial: true))
        #expect(ActivityPaging.types(for: [.mention], onAlohaSocial: true) == ["mention"])
        // Follows has always included follow requests.
        #expect(
            ActivityPaging.types(for: [.follow], onAlohaSocial: false)
                == ["follow", "follow_request"])
    }

    @Test("The older page starts below the oldest notification any group shows")
    func groupedAnchor() {
        let groups = [
            group("a", newest: "120", min: "100"),
            group("b", newest: "99"),
            // Numeric order, not string order: "95" sorts after "100" as text.
            group("c", newest: "97", min: "95"),
        ]
        #expect(ActivityPaging.olderAnchor(groups: groups) == "95")
        #expect(ActivityPaging.olderAnchor(groups: []) == nil)
        #expect(ActivityPaging.olderAnchor(flat: [note("9"), note("10"), note("8")]) == "8")
    }

    @Test("A group spanning two pages stays where it was and reaches further back")
    func mergeGroups() {
        let first = [group("fav-1", newest: "50", min: "40", count: 7), group("x", newest: "39")]
        let older = [group("fav-1", newest: "30", min: "20", count: 7), group("y", newest: "19")]
        let merged = ActivityPaging.appending(older, to: first)
        #expect(merged.map(\.groupKey) == ["fav-1", "x", "y"])
        #expect(merged[0].mostRecentNotificationID == "50")
        #expect(merged[0].pageMinID == "20")
        #expect(merged[0].notificationsCount == 7)
        #expect(ActivityPaging.olderAnchor(groups: merged) == "19")
    }

    @Test("A flat page the server partly repeated adds only what is new")
    func mergeFlat() {
        let merged = ActivityPaging.appending([note("8"), note("7")], to: [note("9"), note("8")])
        #expect(merged.map(\.id) == ["9", "8", "7"])
    }

    @Test("Paging ends at an empty page, a missing next link, or a page that moved nothing")
    func end() {
        let none = LinkHeader()
        let next = LinkHeader(next: URL(string: "https://example.com/next"))
        #expect(
            ActivityPaging.mayHaveMore(
                link: none, receivedAny: true, previousAnchor: nil, nextAnchor: "10"))
        #expect(
            !ActivityPaging.mayHaveMore(
                link: none, receivedAny: false, previousAnchor: "10", nextAnchor: "10"))
        #expect(
            !ActivityPaging.mayHaveMore(
                link: LinkHeader(previous: URL(string: "https://example.com/prev")),
                receivedAny: true, previousAnchor: "10", nextAnchor: "5"))
        #expect(
            ActivityPaging.mayHaveMore(
                link: next, receivedAny: true, previousAnchor: "10", nextAnchor: "5"))
        // A server that ignores max_id sends the same page again.
        #expect(
            !ActivityPaging.mayHaveMore(
                link: next, receivedAny: true, previousAnchor: "10", nextAnchor: "10"))
    }
}
