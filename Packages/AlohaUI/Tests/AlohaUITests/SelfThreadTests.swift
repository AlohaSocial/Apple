// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaUI

@Suite("Unrolling a self-thread")
struct SelfThreadTests {
    private let alice = Account(id: "a", username: "alice", acct: "alice")
    private let bob = Account(id: "b", username: "bob", acct: "bob")

    private func post(
        _ id: String, by account: Account, to parent: String? = nil, at minute: Double = 0
    ) -> Status {
        Status(
            id: id, createdAt: Date(timeIntervalSince1970: minute * 60), account: account,
            inReplyToID: parent, inReplyToAccountID: nil)
    }

    @Test("Opened at the first post: the author's chain, other people's replies left out")
    func fromTheTop() {
        let root = post("1", by: alice)
        let run = SelfThread.unroll(
            ancestors: [], focused: root,
            descendants: [
                post("2", by: alice, to: "1", at: 1),
                post("x", by: bob, to: "1", at: 2),
                post("3", by: alice, to: "2", at: 3),
                post("y", by: bob, to: "3", at: 4),
                post("4", by: alice, to: "3", at: 5),
            ])
        #expect(run.map(\.id) == ["1", "2", "3", "4"])
        #expect(SelfThread.isLongEnough(run))
    }

    @Test("Opened in the middle: walks up to where the author started")
    func fromTheMiddle() {
        let run = SelfThread.unroll(
            ancestors: [post("1", by: alice), post("2", by: alice, to: "1", at: 1)],
            focused: post("3", by: alice, to: "2", at: 2),
            descendants: [post("4", by: alice, to: "3", at: 3)])
        #expect(run.map(\.id) == ["1", "2", "3", "4"])
    }

    @Test("Opened at somebody else's reply: the thread's author's chain still unrolls")
    func fromAReply() {
        let run = SelfThread.unroll(
            ancestors: [
                post("1", by: alice), post("2", by: alice, to: "1", at: 1),
                post("3", by: alice, to: "2", at: 2),
            ],
            focused: post("x", by: bob, to: "3", at: 3), descendants: [])
        #expect(run.map(\.id) == ["1", "2", "3"])
    }

    @Test("Two answers to one post: the earlier one carries the thread on")
    func earliestBranch() {
        let run = SelfThread.unroll(
            ancestors: [], focused: post("1", by: alice),
            descendants: [
                post("late", by: alice, to: "1", at: 9),
                post("2", by: alice, to: "1", at: 1),
                post("3", by: alice, to: "2", at: 2),
            ])
        #expect(run.map(\.id) == ["1", "2", "3"])
    }

    @Test("A post and an afterthought is not a thread worth an article")
    func tooShort() {
        let run = SelfThread.unroll(
            ancestors: [], focused: post("1", by: alice),
            descendants: [post("2", by: alice, to: "1", at: 1), post("x", by: bob, to: "2")])
        #expect(run.count == 2)
        #expect(!SelfThread.isLongEnough(run))
    }

    @Test("A self-reply on the timeline is recognised; a reply to someone else is not")
    func timelineHint() {
        var own = post("2", by: alice, to: "1")
        own.inReplyToAccountID = "a"
        var other = post("3", by: alice, to: "1")
        other.inReplyToAccountID = "b"
        #expect(SelfThread.continuesOwnThread(own))
        #expect(!SelfThread.continuesOwnThread(other))
        #expect(!SelfThread.continuesOwnThread(post("1", by: alice)))
    }
}
