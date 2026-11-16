// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaStore

/// Which countdowns the app starts: the account's own poll closing and its
/// next scheduled post going out, within the hour, and nothing already past.
@Suite("Live Activity countdowns")
struct EventActivityPlannerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let account = UUID()

    private func snapshot(
        pollClosesIn minutes: Double? = nil, expired: Bool = false,
        scheduledIn: [Double] = []
    ) -> WidgetSnapshot {
        let poll = minutes.map {
            WidgetSnapshot.Poll(
                statusID: "p1", question: "Tea or coffee?", options: [], voters: 3,
                expiresAt: now.addingTimeInterval($0 * 60), expired: expired)
        }
        let scheduled = scheduledIn.enumerated().map { index, minutes in
            WidgetSnapshot.ScheduledPost(
                id: "s\(index)", text: "Post \(index)", at: now.addingTimeInterval(minutes * 60),
                mediaCount: 0)
        }
        return WidgetSnapshot(
            accountID: account, handle: "@me@example.test", writtenAt: now, scheduled: scheduled,
            poll: poll)
    }

    @Test("A poll closing within the hour counts down; one closing later does not")
    func poll() throws {
        let soon = EventActivityPlanner.upcoming(in: snapshot(pollClosesIn: 20), now: now)
        let event = try #require(soon.first)
        #expect(event.kind == .pollCloses)
        #expect(event.itemID == "p1")
        #expect(event.text == "Tea or coffee?")
        #expect(event.at == now.addingTimeInterval(20 * 60))

        #expect(EventActivityPlanner.upcoming(in: snapshot(pollClosesIn: 61), now: now).isEmpty)
        #expect(EventActivityPlanner.upcoming(in: snapshot(pollClosesIn: 60), now: now).count == 1)
    }

    @Test("A closed or past poll gets no countdown")
    func closedPoll() {
        #expect(
            EventActivityPlanner.upcoming(in: snapshot(pollClosesIn: 20, expired: true), now: now)
                .isEmpty)
        #expect(EventActivityPlanner.upcoming(in: snapshot(pollClosesIn: -1), now: now).isEmpty)
    }

    @Test("Only the next scheduled post counts down, and only within the hour")
    func scheduled() throws {
        let events = EventActivityPlanner.upcoming(
            in: snapshot(scheduledIn: [90, 45, -5, 50]), now: now)
        let event = try #require(events.first)
        #expect(events.count == 1)
        #expect(event.kind == .scheduledPost)
        #expect(event.itemID == "s1")

        #expect(EventActivityPlanner.upcoming(in: snapshot(scheduledIn: [75]), now: now).isEmpty)
    }

    @Test("A poll and a post can both count down; no snapshot is nothing")
    func both() {
        let events = EventActivityPlanner.upcoming(
            in: snapshot(pollClosesIn: 10, scheduledIn: [30]), now: now)
        #expect(Set(events.map(\.kind)) == [.pollCloses, .scheduledPost])
        #expect(EventActivityPlanner.upcoming(in: nil, now: now).isEmpty)
    }

    @Test("Long text is cut for the Lock Screen")
    func shortening() {
        let long = String(repeating: "a", count: 200)
        #expect(EventActivityPlanner.shortened(long).count == EventActivityPlanner.textLimit)
        #expect(EventActivityPlanner.shortened(" two\nlines ") == "two lines")
    }
}
