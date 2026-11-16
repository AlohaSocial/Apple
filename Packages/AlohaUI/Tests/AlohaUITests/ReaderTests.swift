// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import SwiftUI
import Testing

@testable import AlohaUI

@Suite("The reader: when it is offered, how long a read takes, how large the text is")
struct ReaderTests {

    private let author = Account(id: "1", username: "alice", acct: "alice")

    @Test("Words are counted as words, not as spaces")
    func words() {
        #expect(ReadingTime.words(in: "") == 0)
        #expect(ReadingTime.words(in: "One, two — three.\n\nFour!") == 4)
    }

    @Test("Reading time is whole minutes and never zero")
    func minutes() {
        #expect(ReadingTime.minutes(forWords: 0) == 1)
        #expect(ReadingTime.minutes(forWords: 100) == 1)
        #expect(ReadingTime.minutes(forWords: 230) == 1)
        #expect(ReadingTime.minutes(forWords: 1150) == 5)
    }

    @Test("Offered for a long post or a link, not for a short post")
    func offered() {
        let short = Status(id: "1", content: "<p>hello</p>", account: author)
        #expect(!ReadingTime.suitsReader(short))
        let long = Status(
            id: "2", content: "<p>\(String(repeating: "word ", count: 200))</p>", account: author)
        #expect(ReadingTime.suitsReader(long))
        let linked = Status(
            id: "3", content: "<p>look</p>", account: author,
            card: Card(url: URL(string: "https://news.test/story"), title: "Story"))
        #expect(ReadingTime.suitsReader(linked))
    }

    @Test("A boost is judged by the post it boosts")
    func boost() {
        let long = Status(
            id: "2", content: "<p>\(String(repeating: "word ", count: 200))</p>", account: author)
        let wrapper = Status(id: "w", account: author, reblog: Box(long))
        #expect(ReadingTime.suitsReader(wrapper))
    }

    @Test("Text size moves in Dynamic Type's own steps, and stops at its ends")
    func textSize() {
        #expect(ReaderPreferences.size(.large, step: 0) == .large)
        #expect(ReaderPreferences.size(.large, step: 1) == .xLarge)
        #expect(ReaderPreferences.size(.large, step: -2) == .small)
        #expect(ReaderPreferences.size(.xSmall, step: -2) == .xSmall)
        #expect(ReaderPreferences.size(.accessibility5, step: 4) == .accessibility5)
    }
}
