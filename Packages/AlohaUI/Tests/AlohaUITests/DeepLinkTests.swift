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

    @Test("Destinations and other schemes are not presentations")
    func notPresentations() throws {
        #expect(RouteResolver.presentation(for: try url("alohasocial://notifications")) == nil)
        #expect(RouteResolver.presentation(for: try url("https://example.com/compose")) == nil)
        #expect(RouteResolver.presentation(for: try url("other://story")) == nil)
    }
}
