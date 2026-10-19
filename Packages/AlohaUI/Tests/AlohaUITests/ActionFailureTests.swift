// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import Foundation
import Testing

@testable import AlohaUI

@Suite("Failures of confirmed actions are said, not swallowed")
@MainActor
struct ActionFailureTests {
    private func scheduled(_ id: String, inHours hours: Double) throws -> ScheduledStatus {
        let date = Date(timeIntervalSince1970: 1_800_000_000 + hours * 3600)
        let json = """
            {"id": "\(id)", "scheduled_at": "\(date.ISO8601Format())",
             "media_attachments": [], "params": {"text": "post \(id)"}}
            """
        return try AlohaJSON.decoder.decode(ScheduledStatus.self, from: Data(json.utf8))
    }

    @Test("A refused cancel puts the post back in the order posts go out")
    func refusedCancelIsRestoredInOrder() throws {
        let first = try scheduled("1", inHours: 1)
        let second = try scheduled("2", inHours: 2)
        let third = try scheduled("3", inHours: 3)

        // 2 was swiped away, the server refused it.
        let restored = ScheduledPostsView.restoring([second], into: [first, third])
        #expect(restored.map(\.id) == ["1", "2", "3"])
    }

    @Test("Restoring never doubles a post that is still listed")
    func restoringDoesNotDuplicate() throws {
        let first = try scheduled("1", inHours: 1)
        let restored = ScheduledPostsView.restoring([first], into: [first])
        #expect(restored.map(\.id) == ["1"])
    }

    @Test("The message says what did not happen, then the server's reason")
    func failureMessageLeadsWithOutcome() {
        let fallback = "The block did not go through. They can still see and reach you."
        let withReason = StatusActions.failureMessage(
            APIError.forbidden(message: "Not allowed here"), fallback: fallback)
        #expect(withReason.hasPrefix(fallback))
        #expect(withReason.count > fallback.count)

        let withoutReason = StatusActions.failureMessage(URLError(.timedOut), fallback: fallback)
        #expect(withoutReason == fallback)
    }

    @Test("Block and mute go to the routes that block and mute")
    func moderationRoutes() {
        let block = StatusActions.moderationEndpoint(.block, account: "42")
        let mute = StatusActions.moderationEndpoint(.mute, account: "42")
        #expect(block.path.hasSuffix("accounts/42/block"))
        #expect(mute.path.hasSuffix("accounts/42/mute"))
    }
}
