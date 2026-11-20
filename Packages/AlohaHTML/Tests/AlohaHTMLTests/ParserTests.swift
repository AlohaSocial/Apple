// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaHTML

private let parser = StatusHTMLParser()

@Suite("Status HTML")
struct StatusHTMLTests {

    @Test("A plain paragraph becomes text")
    func paragraph() {
        let result = parser.parse("<p>Hello, world.</p>")
        #expect(result.plainText == "Hello, world.")
        #expect(result.blocks.count == 1)
    }

    @Test("Paragraphs are separated in the plain projection")
    func paragraphSeparation() {
        let result = parser.parse("<p>One</p><p>Two</p>")
        #expect(result.plainText == "One\nTwo")
        #expect(result.blocks.count == 2)
    }

    @Test("A line break is a newline, not a lost character")
    func lineBreaks() {
        #expect(parser.parse("<p>One<br>Two</p>").plainText == "One\nTwo")
        #expect(parser.parse("<p>One<br />Two</p>").plainText == "One\nTwo")
    }

    @Test("Nested formatting composes rather than replacing")
    func nestedFormatting() {
        let result = parser.parse("<p><strong>Bold <em>and italic</em></strong></p>")
        let italicRun = result.runs.first { $0.text.contains("and italic") }
        #expect(italicRun?.style.contains(.bold) == true)
        #expect(italicRun?.style.contains(.italic) == true)
    }

    @Test("Unsupported tags are stripped to their text content")
    func unsupportedTagsStripped() {
        let result = parser.parse("<p>Before <script>evil()</script><marquee>After</marquee></p>")
        #expect(result.plainText.contains("Before"))
        #expect(result.plainText.contains("After"))
        // The tags are gone; their text is not.
        #expect(result.plainText.contains("<script>") == false)
    }

    @Test("Comments and doctypes vanish")
    func commentsRemoved() {
        let result = parser.parse("<!DOCTYPE html><p>Kept<!-- dropped --></p>")
        #expect(result.plainText == "Kept")
    }

    @Test("Malformed markup does not hang or throw")
    func malformedMarkup() {
        // Every one of these must terminate: the tokenizer consumes at least one
        // character per iteration whatever it meets.
        for input in [
            "<p>Unclosed", "<<<>>>", "<p class=", "<a href='unterminated>text</a>",
            "5 < 6 and 7 > 3", "<p>a</p></div></div>", "<",
        ] {
            _ = parser.parse(input)
        }
    }

    @Test("Entities decode, including numeric and hex forms")
    func entities() {
        #expect(parser.parse("<p>Tom &amp; Jerry</p>").plainText == "Tom & Jerry")
        #expect(parser.parse("<p>&lt;tag&gt;</p>").plainText == "<tag>")
        #expect(parser.parse("<p>caf&#233;</p>").plainText == "café")
        #expect(parser.parse("<p>caf&#xe9;</p>").plainText == "café")
        #expect(parser.parse("<p>&hellip;</p>").plainText == "…")
        // A bare ampersand stays a bare ampersand.
        #expect(parser.parse("<p>R&D</p>").plainText == "R&D")
        #expect(parser.parse("<p>&notanentity;</p>").plainText == "&notanentity;")
    }

    @Test("Lists produce blocks with their ordinal")
    func lists() {
        let result = parser.parse("<ul><li>One</li><li>Two</li></ul>")
        #expect(result.plainText.contains("One"))
        #expect(result.plainText.contains("Two"))

        let ordered = parser.parse("<ol><li>First</li><li>Second</li></ol>")
        let indices = ordered.blocks.compactMap { block -> Int? in
            if case .listItem(let isOrdered, let index) = block.kind, isOrdered { return index }
            return nil
        }
        #expect(indices == [1, 2])
    }

    @Test("Blockquotes and code carry their style")
    func quotesAndCode() {
        let quoted = parser.parse("<blockquote><p>Quoted</p></blockquote>")
        #expect(quoted.runs.contains { $0.style.contains(.quote) })

        let code = parser.parse("<p>Use <code>swift build</code></p>")
        #expect(code.runs.contains { $0.text == "swift build" && $0.style.contains(.code) })
    }
}

@Suite("Link classification")
struct LinkTests {

    private let mentions = [
        Status.Mention(
            id: "42", username: "bob", acct: "bob@other.test",
            url: URL(string: "https://other.test/@bob"))
    ]
    private let tags = [
        Status.StatusTag(name: "NextCloud", url: URL(string: "https://cloud.test/tags/nextcloud"))
    ]

    @Test("A mention resolves to the account it names, by href")
    func mentionByHref() throws {
        let html =
            #"<p><a href="https://other.test/@bob" class="u-url mention">@<span>bob</span></a></p>"#
        let result = parser.parse(html, mentions: mentions)

        let link = try #require(result.runs.compactMap(\.link).first)
        guard case .mention(let accountID, let acct, _) = link else {
            Issue.record("expected a mention")
            return
        }
        #expect(accountID == "42")
        #expect(acct == "bob@other.test")
    }

    @Test("The domain inside a span is kept, so two Alices stay distinguishable")
    func mentionKeepsDomain() {
        let html = """
            <p><a href="https://other.test/@bob" class="u-url mention">@<span>bob</span>\
            <span class="invisible">@other.test</span></a></p>
            """
        let result = parser.parse(html, mentions: mentions)
        #expect(result.plainText.contains("other.test"))
    }

    @Test("A mention the status did not declare still routes by handle")
    func undeclaredMention() throws {
        let html = #"<p><a href="https://elsewhere.test/@carol" class="mention">@carol</a></p>"#
        let result = parser.parse(html)

        let link = try #require(result.runs.compactMap(\.link).first)
        guard case .mention(let accountID, let acct, _) = link else {
            Issue.record("expected a mention")
            return
        }
        #expect(accountID == nil)
        #expect(acct == "carol@elsewhere.test")
    }

    @Test("A hashtag takes the status's own spelling, not the URL's")
    func hashtagCanonicalisation() throws {
        let html =
            #"<p><a href="https://cloud.test/tags/nextcloud" class="hashtag">#<span>NextCloud</span></a></p>"#
        let result = parser.parse(html, tags: tags)

        let link = try #require(result.runs.compactMap(\.link).first)
        guard case .hashtag(let name, _) = link else {
            Issue.record("expected a hashtag")
            return
        }
        #expect(name == "NextCloud")
    }

    /// Mastodon writes a hashtag as `class="mention hashtag"`. Read as a
    /// mention first, `/tags/swift` became the handle `swift@host` and a tap
    /// opened a profile that does not exist.
    @Test("Mastodon's hashtag markup is a hashtag, not a mention")
    func mastodonHashtag() throws {
        let html =
            #"<p><a href="https://mastodon.test/tags/swift" class="mention hashtag" rel="tag">#<span>swift</span></a></p>"#
        let result = parser.parse(html)

        let link = try #require(result.runs.compactMap(\.link).first)
        guard case .hashtag(let name, _) = link else {
            Issue.record("expected a hashtag, got \(link)")
            return
        }
        #expect(name == "swift")
        #expect(result.mentions.isEmpty)
    }

    @Test("An ordinary link is a web link")
    func webLink() {
        let html = #"<p>See <a href="https://example.test/page">this</a></p>"#
        let result = parser.parse(html)
        #expect(result.webLinks.map(\.absoluteString) == ["https://example.test/page"])
        #expect(result.mentions.isEmpty)
    }
}

@Suite("Custom emoji")
struct EmojiTests {

    private let emojis = [
        CustomEmoji(shortcode: "nextcloud", url: URL(string: "https://cloud.test/e/nextcloud.png")),
        CustomEmoji(shortcode: "wave", url: URL(string: "https://cloud.test/e/wave.png")),
    ]

    @Test("A known shortcode becomes an emoji run")
    func knownShortcode() {
        let result = parser.parse("<p>Hello :wave: from :nextcloud:</p>", emojis: emojis)
        let codes = result.runs.compactMap(\.emoji).map(\.shortcode)
        #expect(codes == ["wave", "nextcloud"])
    }

    @Test("An unknown shortcode stays literal text")
    func unknownShortcode() {
        let result = parser.parse("<p>:unknown_thing:</p>", emojis: emojis)
        #expect(result.runs.allSatisfy { $0.emoji == nil })
        #expect(result.plainText == ":unknown_thing:")
    }

    @Test("Prose with colons is not mistaken for emoji")
    func proseWithColons() {
        let result = parser.parse("<p>Note: this is fine. Ratio 3:1 here.</p>", emojis: emojis)
        #expect(result.runs.allSatisfy { $0.emoji == nil })
        #expect(result.plainText.contains("3:1"))
    }

    @Test("A hidden emoji typed by hand still renders")
    func hiddenEmojiStillRenders() {
        // Only emojis marked visible are listed in a picker, but a hidden
        // shortcode written by hand renders wherever it appears.
        let hidden = [
            CustomEmoji(
                shortcode: "secret", url: URL(string: "https://x.test/s.png"),
                visibleInPicker: false)
        ]
        let result = parser.parse("<p>:secret:</p>", emojis: hidden)
        #expect(result.runs.compactMap(\.emoji).map(\.shortcode) == ["secret"])
    }
}

@Suite("Parser performance")
struct PerformanceTests {

    @Test("A 50 KB pathological input parses within a bound")
    func pathologicalInput() {
        let nested = String(repeating: "<span><strong><em>x</em></strong></span>", count: 1200)
        let html = "<p>\(nested)</p>"
        #expect(html.count > 45_000)

        let started = ContinuousClock.now
        let result = parser.parse(html)
        let elapsed = ContinuousClock.now - started

        #expect(result.plainText.isEmpty == false)
        #expect(elapsed < .seconds(1))
    }

    @Test("A long run of entities does not degrade badly")
    func manyEntities() {
        let html = "<p>" + String(repeating: "&amp;&lt;&gt;&#233;", count: 3000) + "</p>"
        let started = ContinuousClock.now
        _ = parser.parse(html)
        #expect(ContinuousClock.now - started < .seconds(1))
    }
}

@Suite("Rich text cache")
struct CacheTests {

    @Test("The same status parses once and is served from cache after")
    func cacheHit() async {
        let cache = RichTextCache()
        let account = Account(id: "1", username: "a", acct: "a")
        let status = Status(id: "1", content: "<p>Cached</p>", account: account)

        let first = await cache.richText(for: status)
        let second = await cache.richText(for: status)
        #expect(first == second)
        #expect(first.plainText == "Cached")
    }

    @Test("A boost is parsed from what it boosts")
    func boostUsesInnerContent() async {
        let cache = RichTextCache()
        let account = Account(id: "1", username: "a", acct: "a")
        let inner = Status(id: "1", content: "<p>Original</p>", account: account)
        let boost = Status(id: "2", content: "", account: account, reblog: Box(inner))

        #expect(await cache.richText(for: boost).plainText == "Original")
    }

    @Test("A row can ask synchronously, and a page warmed off the main actor is there")
    func synchronousLookupAfterWarm() async {
        let cache = RichTextCache()
        let account = Account(id: "1", username: "a", acct: "a")
        let status = Status(
            id: "1", content: #"<p>One</p><p>Two <a href="https://example.com/x">link</a></p>"#,
            account: account)

        #expect(cache.cachedEntry(for: status) == nil)
        let links = await cache.warm([status])
        #expect(links["1"]?.map(\.absoluteString) == ["https://example.com/x"])
        let entry = cache.cachedEntry(for: status)
        #expect(entry?.richText.plainText.contains("One") == true)
        // The layout comes with the parse, so a view has nothing left to do.
        #expect(entry?.layout == entry.map { RichTextLayout($0.richText) })
    }

    @Test("A small uncached body is parsed in place; a huge one is left for later")
    func immediateEntry() {
        let cache = RichTextCache()
        let account = Account(id: "1", username: "a", acct: "a")
        let small = Status(id: "1", content: "<p>Short</p>", account: account)
        let huge = Status(
            id: "2",
            content: "<p>" + String(repeating: "word ", count: RichTextCache.inlineParseLimit)
                + "</p>",
            account: account)

        #expect(cache.immediateEntry(for: small)?.richText.plainText == "Short")
        #expect(cache.cachedEntry(for: small) != nil)
        #expect(cache.immediateEntry(for: huge) == nil)
    }

    @Test("A launch-sized page is warmed whole, across slices")
    func warmManySlices() async {
        let cache = RichTextCache()
        let account = Account(id: "1", username: "a", acct: "a")
        let statuses = (0..<130).map {
            Status(
                id: "\($0)", content: #"<p>Post <a href="https://example.com/\#($0)">x</a></p>"#,
                account: account)
        }
        let links = await cache.warm(statuses)
        #expect(links.count == 130)
        #expect(statuses.allSatisfy { cache.cachedEntry(for: $0) != nil })
    }

    @Test("An edit is a different body, not the cached one")
    func editedContentIsReparsed() {
        let cache = RichTextCache()
        let account = Account(id: "1", username: "a", acct: "a")
        let original = Status(id: "1", content: "<p>Before</p>", account: account)
        var edited = original
        edited.content = "<p>After</p>"

        #expect(cache.entry(for: original).richText.plainText == "Before")
        #expect(cache.entry(for: edited).richText.plainText == "After")
    }

    @Test("The table stays within its capacity")
    func eviction() {
        let cache = RichTextCache(capacity: 10)
        let account = Account(id: "1", username: "a", acct: "a")
        let statuses = (0..<25).map {
            Status(id: "\($0)", content: "<p>Post \($0)</p>", account: account)
        }
        for status in statuses { _ = cache.entry(for: status) }

        let kept = statuses.filter { cache.cachedEntry(for: $0) != nil }
        #expect(kept.count <= 10)
        // The newest is never the one evicted.
        #expect(cache.cachedEntry(for: statuses[24]) != nil)
        #expect(cache.cachedEntry(for: statuses[0]) == nil)
    }

    @Test("A typical post parses quickly enough to do in a view's first layout")
    func inlineParseIsCheap() {
        let cache = RichTextCache()
        let account = Account(id: "1", username: "a", acct: "a")
        let paragraph =
            #"<p>Hello <span class="h-card"><a href="https://example.com/@b" class="u-url mention">@<span>b</span></a></span>, "#
            + #"see <a href="https://example.com/a/long/path">example.com/a/long/path</a> and "#
            + #"<a href="https://example.com/tags/swift" class="mention hashtag">#<span>swift</span></a>.</p>"#
        let html = String(repeating: paragraph, count: 8)
        #expect(html.utf8.count < RichTextCache.inlineParseLimit)
        let statuses = (0..<100).map {
            Status(id: "\($0)", content: html + "\($0)", account: account)
        }

        let started = ContinuousClock.now
        for status in statuses { _ = cache.immediateEntry(for: status) }
        let perPost = (ContinuousClock.now - started) / 100
        // Generous for a debug build on a loaded CI machine; in a release
        // build this is a few tens of microseconds.
        #expect(perPost < .milliseconds(4))
    }
}
