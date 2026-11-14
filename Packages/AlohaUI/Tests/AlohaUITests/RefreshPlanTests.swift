// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AlohaStore
import Testing

@testable import AlohaUI

/// The four lines that decide how a refresh merges.
///
/// They cost two visible bugs. A freshly built model with a warm cache once
/// asked only for what was *newer*, got nothing, and left another source's
/// rows on screen under the wrong title — so every refresh now fetches the
/// head. Then the first refresh merged that head cold, keeping forty posts of
/// a five-hundred-post cache and losing the reader's place.
@Suite("Timeline refresh plan")
struct RefreshPlanTests {
    @Test("A first refresh with a cache keeps it, merging the head on top")
    func firstFetchWithCacheMerges() {
        let direction = TimelineModel.refreshDirection(
            hasRows: true, hasFetchedBefore: false, pagesOnlyByLink: false, replacesCache: false)
        #expect(direction == .newer)
    }

    @Test("A list with nothing to keep loads cold")
    func emptyListIsCold() {
        for hasFetched in [true, false] {
            let direction = TimelineModel.refreshDirection(
                hasRows: false, hasFetchedBefore: hasFetched, pagesOnlyByLink: false,
                replacesCache: false)
            #expect(direction == .cold)
        }
    }

    @Test("Later refreshes merge as newer")
    func laterRefreshesMerge() {
        let direction = TimelineModel.refreshDirection(
            hasRows: true, hasFetchedBefore: true, pagesOnlyByLink: false, replacesCache: false)
        #expect(direction == .newer)
    }

    /// Favourites and bookmarks page by a cursor only the server can name; a
    /// merged cache would leave none that reaches below it.
    @Test("A list that pages only by link starts cold, then merges")
    func linkPagedListStartsCold() {
        let first = TimelineModel.refreshDirection(
            hasRows: true, hasFetchedBefore: false, pagesOnlyByLink: true, replacesCache: false)
        #expect(first == .cold)
        let later = TimelineModel.refreshDirection(
            hasRows: true, hasFetchedBefore: true, pagesOnlyByLink: true, replacesCache: false)
        #expect(later == .newer)
    }

    @Test("A gap that can only be filled by starting again replaces the cache")
    func replacingIsCold() {
        let direction = TimelineModel.refreshDirection(
            hasRows: true, hasFetchedBefore: true, pagesOnlyByLink: true, replacesCache: true)
        #expect(direction == .cold)
    }
}

/// Where the home timeline opens, and where its divider goes.
@Suite("Home reading position")
struct ReadingPositionTests {
    private let alice = Account(id: "a", username: "alice", acct: "alice")

    private func rows(_ ids: [String]) -> [TimelineRow] {
        ids.map { .status(Status(id: $0, account: alice)) }
    }

    @Test("The marker only ever moves to a newer post")
    func markerMovesForwardOnly() {
        #expect(TimelineModel.movesMarkerForward(to: "200", from: "100"))
        #expect(!TimelineModel.movesMarkerForward(to: "100", from: "200"))
        #expect(!TimelineModel.movesMarkerForward(to: "200", from: "200"))
        // Length first: "1000" is newer than "999".
        #expect(TimelineModel.movesMarkerForward(to: "1000", from: "999"))
        #expect(TimelineModel.movesMarkerForward(to: "5", from: nil))
        #expect(TimelineModel.movesMarkerForward(to: "5", from: ""))
    }

    @Test("The divider sits above the last post read, with the new ones over it")
    func dividerAboveMarker() {
        let placed = TimelineModel.placingDivider(in: rows(["9", "8", "7", "6"]), above: "7")
        #expect(placed.map(\.id) == ["9", "8", "caughtUp-7", "7", "6"])
    }

    @Test("Nothing new above the marker draws no divider")
    func noDividerOnNewest() {
        let placed = TimelineModel.placingDivider(in: rows(["9", "8"]), above: "9")
        #expect(placed.map(\.id) == ["9", "8"])
    }

    @Test("There is only ever one divider, and it follows the marker")
    func dividerMoves() {
        let once = TimelineModel.placingDivider(in: rows(["9", "8", "7"]), above: "8")
        let moved = TimelineModel.placingDivider(in: once, above: "7")
        #expect(moved.map(\.id) == ["9", "8", "caughtUp-7", "7"])
        let gone = TimelineModel.placingDivider(in: moved, above: nil)
        #expect(gone.map(\.id) == ["9", "8", "7"])
    }

    @Test("A marker that is not in the list places no divider")
    func markerNotLoaded() {
        let placed = TimelineModel.placingDivider(in: rows(["9", "8"]), above: "3")
        #expect(placed.map(\.id) == ["9", "8"])
    }

    @Test("Several updates land in one pass, boosts included")
    func replacingMany() {
        let post = Status(id: "p", account: alice)
        let boost = Status(id: "b", account: alice, reblog: Box(post))
        var liked = post
        liked.favourited = true
        let replaced = TimelineModel.replacing(
            ["p": liked], in: [.status(post), .status(boost), .gap(id: "g")])
        #expect(replaced[0].status?.favourited == true)
        #expect(replaced[1].status?.id == "b")
        #expect(replaced[1].status?.displayed.favourited == true)
        #expect(replaced[2].id == "g")
    }
}
