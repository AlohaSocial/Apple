// SPDX-License-Identifier: MIT

import AlohaModels
import Testing

@testable import AlohaUI

private func reply(_ id: String, to parent: String) -> Status {
    Status(
        id: id, account: Account(id: "a", username: "alice", acct: "alice"),
        inReplyToID: parent)
}

@Suite("Thread layout")
struct ThreadLayoutTests {
    @Test("Depth follows the reply chain below the opened post, not the ancestors")
    func depths() {
        let layout = ThreadLayout(
            focusedID: "f",
            descendants: [
                reply("a", to: "f"), reply("b", to: "a"), reply("c", to: "b"),
                reply("d", to: "f"),
                // Its parent was filtered out: a branch of its own, not lost.
                reply("e", to: "gone"),
            ])
        #expect(layout.depths == ["a": 1, "b": 2, "c": 3, "d": 1, "e": 1])
        let rows = layout.rows(expanded: [])
        #expect(
            rows == [
                .reply(index: 0, indent: 0, depth: 1), .reply(index: 1, indent: 1, depth: 2),
                .reply(index: 2, indent: 2, depth: 3), .reply(index: 3, indent: 0, depth: 1),
                .reply(index: 4, indent: 0, depth: 1),
            ])
    }

    @Test("Replies are laid out depth first, each under the post it answers")
    func depthFirst() {
        // Sent breadth first: the layout still puts "b" under "a".
        let layout = ThreadLayout(
            focusedID: "f",
            descendants: [reply("a", to: "f"), reply("c", to: "f"), reply("b", to: "a")])
        #expect(layout.rows(expanded: []).map(\.id) == ["reply-0", "reply-2", "reply-1"])
    }

    @Test("A chain past the indentation cap folds behind one row, and opens flat")
    func deepFold() {
        var chain = [reply("r1", to: "f")]
        for level in 2...9 { chain.append(reply("r\(level)", to: "r\(level - 1)")) }
        let layout = ThreadLayout(focusedID: "f", descendants: chain)

        let closed = layout.rows(expanded: [])
        // Six levels show (indent 0 to 5); the three deeper fold away.
        #expect(closed.count == 7)
        #expect(closed.last == .more(anchorID: "deep-r6", count: 3, indent: 5))

        let open = layout.rows(expanded: ["deep-r6"])
        #expect(open.count == 9)
        #expect(open.last == .reply(index: 8, indent: 5, depth: 9))
    }

    @Test("A long branch shows its first replies and folds the rest")
    func longBranch() {
        var replies = [reply("top", to: "f")]
        for index in 0..<12 { replies.append(reply("x\(index)", to: "top")) }
        replies.append(reply("next", to: "f"))
        let layout = ThreadLayout(focusedID: "f", descendants: replies)

        let rows = layout.rows(expanded: [])
        #expect(rows.count == 1 + ThreadLayout.branchPreview + 1 + 1)
        #expect(
            rows[ThreadLayout.branchPreview + 1]
                == .more(anchorID: "branch-top", count: 9, indent: 1))
        #expect(rows.last == .reply(index: 13, indent: 0, depth: 1))
        #expect(layout.rows(expanded: ["branch-top"]).count == replies.count)
    }

    @Test("A reply cycle in what the server sent does not hang or repeat rows")
    func cycle() {
        let layout = ThreadLayout(
            focusedID: "f", descendants: [reply("a", to: "b"), reply("b", to: "a")])
        // Neither is reachable from the opened post; both still show, once.
        #expect(layout.rows(expanded: []).count == 2)
        #expect(layout.count == 2)
    }

    @Test("A thousand-deep chain is laid out without recursion")
    func veryDeep() {
        var chain = [reply("0", to: "f")]
        for index in 1..<1_000 { chain.append(reply("\(index)", to: "\(index - 1)")) }
        let layout = ThreadLayout(focusedID: "f", descendants: chain)
        #expect(layout.depths["999"] == 1_000)
        // A long branch first: the opening replies, then one fold.
        #expect(layout.rows(expanded: []).count == 1 + ThreadLayout.branchPreview + 1)
        // Opened, the depth cap still folds what lies below it.
        let opened = layout.rows(expanded: ["branch-0"])
        #expect(opened.count == 7)
        #expect(opened.last == .more(anchorID: "deep-5", count: 994, indent: 5))
    }
}
