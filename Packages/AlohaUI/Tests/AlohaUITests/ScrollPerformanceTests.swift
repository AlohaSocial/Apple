// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaStore
import CoreGraphics
import Foundation
import Testing

@testable import AlohaUI

private let alice = Account(
    id: "1", username: "alice", acct: "alice",
    avatar: URL(string: "https://example.test/alice.png"))

private func post(
    _ id: String, content: String = "<p>hello</p>", spoiler: String = "",
    media: [MediaAttachment] = [], filtered: [Status.FilterResult]? = nil
) -> Status {
    Status(
        id: id, content: content, spoilerText: spoiler, account: alice,
        mediaAttachments: media, filtered: filtered)
}

/// `FilterResult` is decoded, never built, outside its module — as here.
private func result(_ filter: Filter) throws -> Status.FilterResult {
    let data = try JSONEncoder().encode(["filter": filter])
    return try JSONDecoder().decode(Status.FilterResult.self, from: data)
}

private func image(_ id: String) -> MediaAttachment {
    MediaAttachment(id: id, type: .image, url: URL(string: "https://example.test/\(id).jpg"))
}

@Suite("Keyword filters read the post, not its markup")
struct FilterPlainTextTests {

    private func keyword(_ word: String, wholeWord: Bool = false) -> Filter {
        Filter(
            id: "f", title: "Words", context: [.home], filterAction: .hide,
            keywords: [Filter.Keyword(id: "k", keyword: word, wholeWord: wholeWord)])
    }

    @Test("A keyword that only appears in the HTML does not match")
    func markupIsNotText() {
        let linked = post(
            "1",
            content:
                #"<p>look <a href="https://x.test" class="u-url"><span class="invisible">https://</span>x.test</a></p>"#
        )
        for word in ["span", "href", "invisible", "class"] {
            #expect(
                FilterEvaluator.decision(for: linked, filters: [keyword(word)], context: .home)
                    == .show, "\(word) is markup, not something anyone wrote")
        }
    }

    @Test("Entities are matched as the characters they stand for")
    func entitiesAreDecoded() {
        let status = post("1", content: "<p>Tom &amp; Jerry</p>")
        #expect(
            FilterEvaluator.decision(
                for: status, filters: [keyword("tom & jerry")], context: .home) == .hide)
        #expect(
            FilterEvaluator.decision(
                for: status, filters: [keyword("tom & jerry", wholeWord: true)], context: .home)
                == .hide)
    }

    @Test("Text the caller already parsed is what is searched")
    func suppliedTextIsUsed() {
        let status = post("1", content: "<p>nothing to see</p>")
        #expect(
            FilterEvaluator.decision(
                for: status, filters: [keyword("secret")], context: .home,
                text: "a secret after all") == .hide)
    }

    @Test("The server's own verdict hides a post the app has no filter for")
    func serverHide() throws {
        let serverFilter = Filter(id: "s", title: "Server", context: [.home], filterAction: .hide)
        let status = post("1", filtered: [try result(serverFilter)])
        #expect(FilterEvaluator.decision(for: status, filters: [], context: .home) == .hide)
    }

    @Test("A server warning collapses, and a local hide still wins over it")
    func serverWarnAndLocalHide() throws {
        let serverFilter = Filter(id: "s", title: "Server", context: [.home], filterAction: .warn)
        let status = post(
            "1", content: "<p>spoilers</p>", filtered: [try result(serverFilter)])
        #expect(
            FilterEvaluator.decision(for: status, filters: [], context: .home)
                == .warn(title: "Server"))
        #expect(
            FilterEvaluator.decision(for: status, filters: [keyword("spoilers")], context: .home)
                == .hide)
    }

    @Test("An expired server verdict no longer applies")
    func expiredServerVerdict() throws {
        let now = Date()
        let lapsed = Filter(
            id: "s", title: "Server", context: [.home], expiresAt: now.addingTimeInterval(-1),
            filterAction: .hide)
        let status = post("1", filtered: [try result(lapsed)])
        #expect(
            FilterEvaluator.decision(for: status, filters: [], context: .home, now: now) == .show)
    }

    @Test("The next expiry is the soonest one still ahead")
    func nextExpiry() {
        let now = Date()
        let filters = [
            Filter(id: "a", title: "A", expiresAt: now.addingTimeInterval(-60)),
            Filter(id: "b", title: "B", expiresAt: now.addingTimeInterval(600)),
            Filter(id: "c", title: "C", expiresAt: now.addingTimeInterval(60)),
            Filter(id: "d", title: "D"),
        ]
        #expect(FilterEvaluator.nextExpiry(of: filters, after: now) == now.addingTimeInterval(60))
    }

    @Test("An edit gives a post a new filter verdict")
    func cacheKeyFollowsContent() {
        let before = post("1", content: "<p>one</p>")
        let after = post("1", content: "<p>two</p>")
        #expect(FilterCacheKey(before) == FilterCacheKey(post("1", content: "<p>one</p>")))
        #expect(FilterCacheKey(before) != FilterCacheKey(after))
    }
}

@Suite("Activity list rows keep their names")
struct ActivityListRowTests {

    private struct Item: Identifiable {
        let id: String
    }

    @Test("A row is named by what it shows, so an arrival renames nothing")
    func idsSurviveAnInsertAtTheTop() {
        let before = ActivityListRow.rows(
            [Item(id: "b"), Item(id: "c")], dividerAfter: 0, markerID: "b")
        let after = ActivityListRow.rows(
            [Item(id: "a"), Item(id: "b"), Item(id: "c")], dividerAfter: 1, markerID: "b")

        #expect(before.map(\.id) == ["item-b", "caughtUp-b", "item-c"])
        #expect(after.map(\.id) == ["item-a", "item-b", "caughtUp-b", "item-c"])
        // Every row that was there before keeps its identity.
        #expect(Set(before.map(\.id)).isSubset(of: Set(after.map(\.id))))
    }

    @Test("No marker, or one that is not in the list, means no divider")
    func noDivider() {
        let items = [Item(id: "a")]
        #expect(ActivityListRow.rows(items, dividerAfter: nil, markerID: nil).count == 1)
        #expect(ActivityListRow.rows(items, dividerAfter: 5, markerID: "x").count == 1)
    }

    @Test("Ids stay unique when the divider names a row in the list")
    func idsAreUnique() {
        let rows = ActivityListRow.rows(
            [Item(id: "a"), Item(id: "b")], dividerAfter: 0, markerID: "a")
        #expect(Set(rows.map(\.id)).count == rows.count)
    }
}

@Suite("Prefetch asks for what the rows ask for")
struct PrefetchGeometryTests {

    private let geometry = PrefetchGeometry(contentWidth: 300, avatarSize: 46, scale: 3)

    @Test("One picture spans the content width, capped at the row height")
    func singleImage() {
        let requests = TimelineModel.prefetchRequests(
            .status(post("1", media: [image("m")])), geometry)
        let media = requests.first { $0.url.lastPathComponent == "m.jpg" }
        #expect(media?.size == CGSize(width: 300, height: 300))
    }

    @Test("Two pictures share a 16:9 strip, more make squares")
    func gridSizes() {
        let two = TimelineModel.prefetchRequests(
            .status(post("1", media: [image("a"), image("b")])), geometry)
        #expect(two.first?.size == CGSize(width: 150, height: 300.0 * 9 / 16))

        let four = TimelineModel.prefetchRequests(
            .status(post("1", media: (1...5).map { image("p\($0)") })), geometry)
        #expect(four.filter { $0.url.pathExtension == "jpg" }.count == 4)
        #expect(four.first?.size == CGSize(width: 150, height: 150))
    }

    @Test("The avatar is asked for at the row's avatar size")
    func avatarSize() {
        let requests = TimelineModel.prefetchRequests(.status(post("1")), geometry)
        #expect(requests.map(\.size) == [CGSize(width: 46, height: 46)])
    }

    @Test("Requests are grouped by size, one prefetch call each")
    func grouping() {
        let urls = (1...3).map { URL(string: "https://example.test/\($0)")! }
        let groups = TimelineModel.groupedBySize([
            (urls[0], CGSize(width: 10, height: 10)),
            (urls[1], CGSize(width: 20, height: 20)),
            (urls[2], CGSize(width: 10, height: 10)),
        ])
        #expect(groups.count == 2)
        #expect(groups.first?.urls == [urls[0], urls[2]])
    }

    @Test("A divider or gap asks for nothing")
    func nonStatusRows() {
        #expect(TimelineModel.prefetchRequests(.gap(id: "g"), geometry).isEmpty)
    }
}

@Suite("Avatars grow with text, within reason")
struct AvatarScalingTests {

    @Test("Default text keeps the base size; large text grows it at most by half")
    func scaling() {
        #expect(AvatarView.dimension(base: 46, typeScale: 1) == 46)
        #expect(AvatarView.dimension(base: 46, typeScale: 1.2) == 55)
        #expect(AvatarView.dimension(base: 46, typeScale: 3) == 69)
        // Smaller-than-default text never shrinks a face below its size.
        #expect(AvatarView.dimension(base: 46, typeScale: 0.8) == 46)
    }
}
