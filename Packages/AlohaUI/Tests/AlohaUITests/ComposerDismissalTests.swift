// SPDX-License-Identifier: MIT

import Testing

@testable import AlohaUI

@Suite("The composer is never swiped away with something in it")
struct ComposerDismissalTests {
    private func newPost(
        text: String = "", spoiler: String = "", attachments: Bool = false, poll: Bool = false,
        segments: [String] = []
    ) -> ComposerDismissal {
        ComposerDismissal(
            text: text, spoilerText: spoiler, hasAttachments: attachments, hasPoll: poll,
            threadSegments: segments, editBaseline: nil)
    }

    @Test("An empty composer goes on a swipe, like an empty Mail draft")
    func emptyIsNotGuarded() {
        #expect(!newPost().isGuarded)
        #expect(!newPost(text: "  \n ", segments: [" "]).isGuarded)
    }

    @Test(
        "Anything a draft would keep holds the composer",
        arguments: [
            ComposerDismissal(
                text: "Hello", spoilerText: "", hasAttachments: false, hasPoll: false,
                threadSegments: [], editBaseline: nil),
            ComposerDismissal(
                text: "", spoilerText: "Spoilers", hasAttachments: false, hasPoll: false,
                threadSegments: [], editBaseline: nil),
            ComposerDismissal(
                text: "", spoilerText: "", hasAttachments: true, hasPoll: false,
                threadSegments: [], editBaseline: nil),
            ComposerDismissal(
                text: "", spoilerText: "", hasAttachments: false, hasPoll: true,
                threadSegments: [], editBaseline: nil),
            ComposerDismissal(
                text: "", spoilerText: "", hasAttachments: false, hasPoll: false,
                threadSegments: ["and then"], editBaseline: nil),
        ])
    func contentIsGuarded(_ state: ComposerDismissal) {
        #expect(state.isGuarded)
    }

    @Test("An edit is held only once it has changed")
    func editGuardsOnChange() {
        var edit = ComposerDismissal(
            text: "Original", spoilerText: "", hasAttachments: true, hasPoll: false,
            threadSegments: [], editBaseline: "Original")
        #expect(!edit.isGuarded)
        edit.text = "Original, fixed"
        #expect(edit.isGuarded)
    }
}
