// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaUI

@Suite("Deep links that present a sheet")
struct DeepLinkTests {
    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    @Test("The compose and story links ask for a sheet, not a destination")
    func presentations() throws {
        let compose = try url("alohasocial://compose")
        let story = try url("alohasocial://story")
        #expect(RouteResolver.presentation(for: compose) == .composer)
        #expect(RouteResolver.presentation(for: story) == .storyComposer)
        #expect(RouteResolver.route(for: compose) == nil)
        #expect(RouteResolver.route(for: story) == nil)
    }

    @Test("Each presentation posts the notification its sheet watches for")
    func notifications() {
        #expect(RouteResolver.Presentation.composer.notification == RouteResolver.composeRequested)
        #expect(
            RouteResolver.Presentation.storyComposer.notification
                == RouteResolver.storyComposerRequested)
    }

    @Test("The story camera link opens the story composer on its camera")
    func storyCamera() throws {
        let camera = try url("alohasocial://story?camera=1")
        #expect(RouteResolver.presentation(for: camera) == .storyCamera)
        #expect(RouteResolver.route(for: camera) == nil)
        #expect(
            RouteResolver.Presentation.storyCamera.notification
                == RouteResolver.storyCameraRequested)
        // Anything else in the query is the ordinary story composer.
        #expect(
            RouteResolver.presentation(for: try url("alohasocial://story?camera=0"))
                == .storyComposer)
    }

    @Test("The scheduled posts and search controls open their screens")
    func controlDestinations() throws {
        #expect(RouteResolver.route(for: try url("alohasocial://scheduled")) == .scheduledPosts)
        #expect(RouteResolver.route(for: try url("alohasocial://search")) == .search(query: nil))
    }

    @Test("Destinations and other schemes are not presentations")
    func notPresentations() throws {
        #expect(RouteResolver.presentation(for: try url("alohasocial://notifications")) == nil)
        #expect(RouteResolver.presentation(for: try url("https://example.com/compose")) == nil)
        #expect(RouteResolver.presentation(for: try url("other://story")) == nil)
    }

    @Test("A widget's screen opens under the account its link names")
    func accountScopedScreens() throws {
        let id = UUID()
        let screens: [(String, Route)] = [
            ("conversations", .conversations), ("scheduled", .scheduledPosts),
            ("drafts", .drafts), ("follow-requests", .followRequests),
            ("notification-requests", .notificationRequests), ("statistics", .statistics),
            ("reports", .moderationReports), ("notifications", .notifications),
            ("explore", .explore), ("year", .annualReport),
        ]
        for (host, route) in screens {
            let scoped = RouteResolver.destination(
                for: try url("alohasocial://\(host)/\(id.uuidString)"))
            #expect(scoped == RouteDestination(accountID: id, route: route))
            let bare = RouteResolver.destination(for: try url("alohasocial://\(host)"))
            #expect(bare == RouteDestination(accountID: nil, route: route))
        }
    }

    @Test("A path that is not an account is no account")
    func malformedAccount() throws {
        let destination = RouteResolver.destination(
            for: try url("alohasocial://conversations/not-a-uuid"))
        #expect(destination == RouteDestination(accountID: nil, route: .conversations))
    }
}
