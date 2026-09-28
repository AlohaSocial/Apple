// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaStore

private typealias Slot = TimelineMerge.Slot

private func slots(_ ids: [String]) -> [Slot] {
    ids.enumerated().map { Slot(statusID: $1, position: Int64(1000 - $0 * 10)) }
}

@Suite("Timeline merge")
struct TimelineMergeTests {

    @Test("A cold load takes the page as the whole timeline")
    func coldLoad() {
        let plan = TimelineMerge.plan(
            existing: [], page: ["5", "4", "3"], direction: .cold, pageWasFull: false)

        #expect(plan.slots.map(\.statusID) == ["5", "4", "3"])
        #expect(plan.insertedStatusIDs == ["5", "4", "3"])
        #expect(TimelineMerge.isWellFormed(plan.slots))
    }

    @Test("A short refresh joins directly, with no gap")
    func shortRefreshJoins() {
        let existing = slots(["3", "2", "1"])
        let plan = TimelineMerge.plan(
            existing: existing, page: ["5", "4"], direction: .newer, pageWasFull: false)

        #expect(plan.slots.map(\.statusID) == ["5", "4", "3", "2", "1"])
        #expect(plan.openedGapIDs.isEmpty)
        #expect(TimelineMerge.isWellFormed(plan.slots))
    }

    /// The bug this rule exists to prevent: joining two ranges that may not
    /// touch produces a timeline with invisible holes.
    @Test("A FULL refresh inserts a gap rather than joining two ranges")
    func fullRefreshInsertsGap() {
        let existing = slots(["3", "2", "1"])
        let plan = TimelineMerge.plan(
            existing: existing, page: ["9", "8", "7"], direction: .newer, pageWasFull: true)

        let ids = plan.slots.map(\.statusID)
        #expect(ids.prefix(3) == ["9", "8", "7"])
        #expect(plan.slots[3].isGapMarker)
        #expect(ids.suffix(3) == ["3", "2", "1"])
        #expect(plan.openedGapIDs.count == 1)
        #expect(TimelineMerge.isWellFormed(plan.slots))
    }

    @Test("A refresh into an empty timeline never opens a gap")
    func fullRefreshOnEmptyTimeline() {
        let plan = TimelineMerge.plan(
            existing: [], page: ["3", "2", "1"], direction: .newer, pageWasFull: true)
        #expect(plan.openedGapIDs.isEmpty)
        #expect(plan.slots.allSatisfy { !$0.isGapMarker })
    }

    @Test("Paging older appends below and never duplicates")
    func pagingOlder() {
        let existing = slots(["5", "4"])
        let plan = TimelineMerge.plan(
            existing: existing, page: ["4", "3", "2"], direction: .older, pageWasFull: false)

        #expect(plan.slots.map(\.statusID) == ["5", "4", "3", "2"])
        // "4" was already cached, so it is not inserted a second time.
        #expect(plan.insertedStatusIDs == ["3", "2"])
        #expect(TimelineMerge.isWellFormed(plan.slots))
    }

    @Test("A short page closes the gap it was fetched for")
    func gapClosesOnShortPage() {
        var existing = slots(["9", "8"])
        existing.append(Slot.gap(below: "8", position: 970))
        existing.append(contentsOf: [
            Slot(statusID: "3", position: 960), Slot(statusID: "2", position: 950),
        ])

        let plan = TimelineMerge.plan(
            existing: existing, page: ["7", "6", "5", "4"],
            direction: .fillingGap(id: "gap:8"), pageWasFull: false)

        #expect(plan.slots.map(\.statusID) == ["9", "8", "7", "6", "5", "4", "3", "2"])
        #expect(plan.closedGapIDs == ["gap:8"])
        #expect(plan.openedGapIDs.isEmpty)
        #expect(TimelineMerge.isWellFormed(plan.slots))
    }

    @Test("A full page moves the gap down instead of closing it")
    func gapMovesOnFullPage() {
        var existing = slots(["9", "8"])
        existing.append(Slot.gap(below: "8", position: 970))
        existing.append(Slot(statusID: "2", position: 960))

        let plan = TimelineMerge.plan(
            existing: existing, page: ["7", "6", "5"],
            direction: .fillingGap(id: "gap:8"), pageWasFull: true)

        let ids = plan.slots.map(\.statusID)
        #expect(ids.first == "9")
        #expect(ids.last == "2")
        #expect(plan.closedGapIDs == ["gap:8"])
        #expect(plan.openedGapIDs.count == 1)
        #expect(plan.slots.filter(\.isGapMarker).count == 1)
        #expect(TimelineMerge.isWellFormed(plan.slots))
    }

    @Test("An empty gap-fill page proves the ranges touch and closes the gap")
    func emptyGapFillCloses() {
        var existing = slots(["9", "8"])
        existing.append(Slot.gap(below: "8", position: 970))
        existing.append(Slot(statusID: "7", position: 960))

        let plan = TimelineMerge.plan(
            existing: existing, page: [], direction: .fillingGap(id: "gap:8"), pageWasFull: false)

        #expect(plan.slots.map(\.statusID) == ["9", "8", "7"])
        #expect(plan.closedGapIDs == ["gap:8"])
    }

    @Test("Re-fetching the same page changes nothing")
    func refetchIsIdempotent() {
        let existing = slots(["3", "2", "1"])
        let plan = TimelineMerge.plan(
            existing: existing, page: ["3", "2", "1"], direction: .newer, pageWasFull: false)

        #expect(plan.insertedStatusIDs.isEmpty)
        #expect(plan.slots.map(\.statusID) == ["3", "2", "1"])
    }

    @Test("Positions stay strictly descending through every operation")
    func positionsRemainOrdered() throws {
        var current = slots(["5", "4", "3"])

        current =
            TimelineMerge.plan(
                existing: current, page: ["9", "8", "7"], direction: .newer, pageWasFull: true
            ).slots
        #expect(TimelineMerge.isWellFormed(current))

        current =
            TimelineMerge.plan(
                existing: current, page: ["2", "1"], direction: .older, pageWasFull: false
            ).slots
        #expect(TimelineMerge.isWellFormed(current))

        let marker = current.first(where: { $0.isGapMarker })
        let gapID = try #require(marker).statusID
        current =
            TimelineMerge.plan(
                existing: current, page: ["6"], direction: .fillingGap(id: gapID),
                pageWasFull: false
            ).slots
        #expect(TimelineMerge.isWellFormed(current))
        #expect(current.map(\.statusID) == ["9", "8", "7", "6", "5", "4", "3", "2", "1"])
    }

    @Test("A deletion removes the row and leaves the rest ordered")
    func deletion() {
        let existing = slots(["5", "4", "3"])
        let after = TimelineMerge.removing("4", from: existing)
        #expect(after.map(\.statusID) == ["5", "3"])
        #expect(TimelineMerge.isWellFormed(after))
    }

    @Test("A duplicated or misordered timeline is detected")
    func wellFormedDetectsProblems() {
        #expect(
            TimelineMerge.isWellFormed([
                Slot(statusID: "a", position: 10), Slot(statusID: "a", position: 9),
            ]) == false)
        #expect(
            TimelineMerge.isWellFormed([
                Slot(statusID: "a", position: 9), Slot(statusID: "b", position: 10),
            ]) == false)
    }
}

@Suite("Account settings")
struct AccountSettingsTests {

    @Test("Autoplay defaults on, with no per-network state to reason about")
    func autoplayDefault() {
        let settings = AccountSettings()
        #expect(settings.autoplayVideo)
        #expect(settings.startMuted)
    }

    @Test("Server preferences override local defaults")
    func adoptsServerPreferences() {
        var settings = AccountSettings()
        settings.adopt(
            Preferences(
                defaultVisibility: .private, defaultSensitive: true,
                defaultLanguage: "de", expandMedia: .hideAll))

        #expect(settings.defaultVisibility == .private)
        #expect(settings.defaultSensitive)
        #expect(settings.defaultLanguage == "de")
        #expect(settings.sensitiveMediaPolicy == .hideAll)
    }

    @Test("An unknown policy from a fork is ignored rather than adopted")
    func ignoresUnknownPolicies() {
        var settings = AccountSettings()
        let original = settings.sensitiveMediaPolicy
        settings.adopt(Preferences(defaultVisibility: .unknownCase, expandMedia: .unknownCase))
        #expect(settings.sensitiveMediaPolicy == original)
        #expect(settings.defaultVisibility == .public)
    }

    @Test("Modes are filtered by what the server can source")
    func visibleModes() {
        var settings = AccountSettings()
        settings.enabledModes = [.home, .photos, .video, .shorts, .news]

        let mastodon = ServerCapabilities(apiBase: URL(string: "https://m.test/")!)
        #expect(settings.visibleModes(capabilities: mastodon).contains(.news) == false)

        let nextcloud = ServerCapabilities(
            apiBase: URL(string: "https://c.test/")!, onlyNewsFilter: true)
        #expect(settings.visibleModes(capabilities: nextcloud).contains(.news))
    }
}

@Suite("Poll scheduling")
struct PollSchedulerTests {

    @Test("The active account polls more often than the others")
    func activeAccountIsFaster() {
        let active = PollScheduler(isActiveAccount: true, activity: .interacting)
        let other = PollScheduler(isActiveAccount: false, activity: .interacting)
        #expect(active.interval == 30)
        #expect(other.interval == 180)
    }

    @Test("Going idle backs the interval off")
    func idleBacksOff() {
        let interacting = PollScheduler(isActiveAccount: true, activity: .interacting).interval
        let shortIdle = PollScheduler(isActiveAccount: true, activity: .idleShort).interval
        let longIdle = PollScheduler(isActiveAccount: true, activity: .idleLong).interval

        #expect(interacting! < shortIdle!)
        #expect(shortIdle! < longIdle!)
    }

    @Test("Low Power Mode doubles every interval")
    func lowPowerDoubles() {
        let normal = PollScheduler(isActiveAccount: true, activity: .interacting).interval!
        let saving = PollScheduler(
            isActiveAccount: true, activity: .interacting, isLowPowerMode: true
        ).interval!
        #expect(saving == normal * 2)
    }

    @Test("Manual mode and the background never schedule a tick")
    func noTimerCases() {
        #expect(
            PollScheduler(isActiveAccount: true, activity: .interacting, frequency: .manual)
                .interval == nil)
        // A background state is BGAppRefreshTask's job, not a timer's.
        #expect(PollScheduler(isActiveAccount: true, activity: .background).interval == nil)
    }

    @Test("On cellular with Wi-Fi-only sync, notifications still poll")
    func cellularNarrowsScope() {
        // A badge staying wrong is worse than the bytes it costs to fix.
        let scheduler = PollScheduler(
            isActiveAccount: true, activity: .interacting, isCellular: true, wifiOnlySync: true)
        #expect(scheduler.scope == .notificationsOnly)
        #expect(scheduler.interval != nil)
    }

    @Test("A tick stays inside the three-request budget")
    func requestBudget() {
        let busiest = PollPlan.make(
            scope: .full, timelineRecentlyVisible: true, unreadCountChanged: true)
        #expect(busiest.requestCount == 3)

        // Notifications are only fetched when the cheap call says something moved.
        let quiet = PollPlan.make(
            scope: .full, timelineRecentlyVisible: true, unreadCountChanged: false)
        #expect(quiet.wantsNotifications == false)
        #expect(quiet.requestCount == 2)

        let narrow = PollPlan.make(
            scope: .notificationsOnly, timelineRecentlyVisible: true, unreadCountChanged: false)
        #expect(narrow.wantsTimeline == false)
    }
}

@Suite("Quiet hours")
struct QuietHoursTests {

    private func date(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
    }

    @Test("A window inside one day")
    func sameDayWindow() {
        let quiet = QuietHours(startHour: 9, endHour: 17)
        #expect(quiet.isQuiet(at: date(hour: 12)))
        #expect(quiet.isQuiet(at: date(hour: 8)) == false)
        #expect(quiet.isQuiet(at: date(hour: 17)) == false)
    }

    @Test("A window that wraps midnight")
    func wrappingWindow() {
        let quiet = QuietHours(startHour: 22, endHour: 7)
        #expect(quiet.isQuiet(at: date(hour: 23)))
        #expect(quiet.isQuiet(at: date(hour: 3)))
        #expect(quiet.isQuiet(at: date(hour: 12)) == false)
    }

    @Test("No window set means never quiet")
    func unset() {
        #expect(QuietHours(startHour: nil, endHour: nil).isQuiet(at: date(hour: 3)) == false)
        #expect(QuietHours(startHour: 9, endHour: 9).isQuiet(at: date(hour: 9)) == false)
    }
}
