// SPDX-License-Identifier: MIT
import Testing
@testable import AlohaUI

@Suite("Channel form submission")
struct ChannelDraftTests {
    @Test("Submitted names and handles use the trimmed values accepted by validation")
    func normalizedSubmission() {
        var draft = ChannelDraft()
        draft.handle = "  my_channel\n"
        draft.name = "\n My channel  "
        draft.description = "First paragraph\n\nSecond paragraph"
        let submitted = draft.normalized
        #expect(submitted.handle == "my_channel")
        #expect(submitted.name == "My channel")
        #expect(submitted.description == draft.description)
        #expect(draft.handle == "  my_channel\n")
    }

    @Test("Normalizing an existing channel preserves its identity")
    func existingChannel() {
        var draft = ChannelDraft()
        draft.existingID = "channel-1"
        draft.name = " Updated name "
        #expect(draft.normalized.id == "channel-1")
        #expect(draft.normalized.existingID == draft.existingID)
    }
}
