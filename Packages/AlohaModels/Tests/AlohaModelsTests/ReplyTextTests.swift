// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaModels

@Suite("A reply written without the composer")
struct ReplyTextTests {
    private let status = Status(
        id: "s1",
        account: Account(id: "1", username: "ana", acct: "ana@example.test", displayName: "Ana"),
        mentions: [
            Status.Mention(id: "2", username: "ben", acct: "ben"),
            Status.Mention(id: "3", username: "me", acct: "me"),
        ])

    @Test("The author and the other people mentioned come first, without the replier")
    func prefixesEveryone() {
        #expect(
            status.replyText("  Sounds good  ", excluding: "me")
                == "@ana@example.test @ben Sounds good")
    }

    @Test("A handle the person already dictated is not added twice")
    func keepsWhatWasWritten() {
        #expect(
            status.replyText("@Ana@example.test, sounds good", excluding: "me")
                == "@ben @Ana@example.test, sounds good")
    }

    @Test("Nobody to address leaves the text as written")
    func nothingToAdd() {
        let own = Status(
            id: "s2",
            account: Account(id: "3", username: "me", acct: "me", displayName: "Me"))
        #expect(own.replyText("Note to self", excluding: "me") == "Note to self")
    }

    @Test("An underscore belongs to the handle, not to the sentence")
    func underscoreIsPartOfHandle() {
        let status = Status(
            id: "s3",
            account: Account(id: "4", username: "bob_", acct: "bob_", displayName: "Bob"))
        #expect(status.replyText("@bob yes", excluding: nil) == "@bob_ @bob yes")
    }
}
