// SPDX-License-Identifier: MIT
import AlohaModels
import Testing
@testable import AlohaUI

@Suite("Activity filtering")
struct ActivityFilteringTests {
    @Test("Follows includes pending follow requests, not unrelated activities")
    func followRequests() {
        #expect(NotificationsView.matches(.follow, selected: [.follow]))
        #expect(NotificationsView.matches(.followRequest, selected: [.follow]))
        #expect(!NotificationsView.matches(.favourite, selected: [.follow]))
    }

    @Test("All includes unknown types and combined filters include only their categories")
    func combinedFilters() {
        #expect(NotificationsView.matches(.unknownCase, selected: []))
        #expect(NotificationsView.matches(.mention, selected: [.mention, .poll]))
        #expect(NotificationsView.matches(.poll, selected: [.mention, .poll]))
        #expect(!NotificationsView.matches(.followRequest, selected: [.mention, .poll]))
    }
}
