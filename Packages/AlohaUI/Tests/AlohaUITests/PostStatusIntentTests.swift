// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaUI

@Suite("Post from a Shortcut")
struct PostStatusIntentTests {
    private let account = UUID()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("A retry of the same post carries the same key")
    func retryKeepsTheKey() {
        let first = PostStatusIntent.idempotencyKey(
            accountID: account, text: "Aloha", visibility: .public, now: now)
        let retry = PostStatusIntent.idempotencyKey(
            accountID: account, text: "Aloha", visibility: .public,
            now: now.addingTimeInterval(30))
        #expect(first == retry)
    }

    @Test("Different words, visibility, account or window are different posts")
    func differencesChangeTheKey() {
        let base = PostStatusIntent.idempotencyKey(
            accountID: account, text: "Aloha", visibility: .public, now: now)
        #expect(
            base
                != PostStatusIntent.idempotencyKey(
                    accountID: account, text: "Aloha!", visibility: .public, now: now))
        #expect(
            base
                != PostStatusIntent.idempotencyKey(
                    accountID: account, text: "Aloha", visibility: .unlisted, now: now))
        #expect(
            base
                != PostStatusIntent.idempotencyKey(
                    accountID: UUID(), text: "Aloha", visibility: .public, now: now))
        #expect(
            base
                != PostStatusIntent.idempotencyKey(
                    accountID: account, text: "Aloha", visibility: .public,
                    now: now.addingTimeInterval(601)))
    }

    @Test("The key is one opaque hex token, not the post's text")
    func keyShape() {
        let key = PostStatusIntent.idempotencyKey(
            accountID: account, text: "a private thought", visibility: .direct, now: now)
        #expect(key.count == 64)
        #expect(key.allSatisfy { $0.isHexDigit })
        #expect(!key.contains("private"))
    }

    @Test("The confirmation shows the start of a long post")
    func preview() {
        #expect(PostStatusIntent.preview(of: "  Short  ") == "Short")
        let long = String(repeating: "word ", count: 40)
        let shown = PostStatusIntent.preview(of: long)
        #expect(shown.hasSuffix("…"))
        #expect(shown.count == 81)
    }
}
