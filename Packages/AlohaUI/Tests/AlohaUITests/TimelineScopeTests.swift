// SPDX-License-Identifier: MIT

import AlohaModels
import Testing

@testable import AlohaUI

/// The scopes follow Nextcloud Social's own switcher: My Feed, For you,
/// Local, Global — For you only where the server has it.
@Suite("Timeline scopes")
struct TimelineScopeTests {
    @Test("For you is offered second, and only on Nextcloud Social")
    func sourceMenu() {
        #expect(
            TimelineSourceMenu.options(offersForYou: true).map(\.source) == [
                .home, .interests, .local, .federated,
            ])
        #expect(
            TimelineSourceMenu.options(offersForYou: false).map(\.source) == [
                .home, .local, .federated,
            ])
    }

    @Test("Shorts offer the same scopes and start on For you where it exists")
    func shorts() {
        #expect(
            ShortsView.Feed.options(offersForYou: true).map(\.source) == [
                .home, .interests, .local, .federated,
            ])
        #expect(!ShortsView.Feed.options(offersForYou: false).contains(.interests))
        #expect(ShortsView.Feed.initial(offersForYou: true) == .interests)
        #expect(ShortsView.Feed.initial(offersForYou: false) == .home)
    }
}
