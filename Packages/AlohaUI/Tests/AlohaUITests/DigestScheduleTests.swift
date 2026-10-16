// SPDX-License-Identifier: MIT

import Testing

@testable import AlohaUI

/// The digest's schedule, as a pure function (docs/08 §8).
///
/// These are the rules a person set up in Settings — the hours, the quiet
/// hours — and the places where a wrong answer is either a missed digest or a
/// notification at 3am.
@Suite("Digest schedule")
struct DigestScheduleTests {

    static let hour = LocalNotifier.nextDigestHour

    // MARK: - The next hour

    @Test("The next picked hour that has not passed yet")
    func nextAhead() {
        // 08:00 and 18:00, and it is 12:00 — 18:00 must win.
        #expect(Self.hour([8, 18], nil, nil, 12, 0) == 18)
    }

    @Test("A picked hour already past means tomorrow's earliest")
    func pastMeansTomorrow() {
        // 08:00 and 18:00, and it is 21:00 — the earliest is tomorrow.
        #expect(Self.hour([8, 18], nil, nil, 21, 0) == 8)
    }

    @Test("The same hour counts only while the minute is exactly zero")
    func sameHourNeedsZeroMinute() {
        // It is 08:00 sharp — this hour counts.
        #expect(Self.hour([8, 18], nil, nil, 8, 0) == 8)
        // It is 08:01 — this hour has passed, so the next one is 18:00.
        #expect(Self.hour([8, 18], nil, nil, 8, 1) == 18)
    }

    @Test("A single picked hour is used whatever the time")
    func singleHour() {
        #expect(Self.hour([8], nil, nil, 7, 30) == 8)
        #expect(Self.hour([8], nil, nil, 21, 0) == 8)
    }

    @Test("Picked hours are used in order, not in the order they were added")
    func sorted() {
        // Added 18:00 first, but 08:00 is the earliest tomorrow.
        #expect(Self.hour([18, 8], nil, nil, 21, 0) == 8)
    }

    @Test("No picked hours schedule nothing")
    func empty() {
        #expect(Self.hour([], nil, nil, 12, 0) == nil)
    }

    // MARK: - Quiet hours

    @Test("A digest hour inside quiet hours is skipped forward")
    func skippedForward() {
        // Quiet from 22:00 to 07:00. Picked 08:00 and 18:00, and it is 12:00 —
        // 18:00 is not quiet, so it wins.
        #expect(Self.hour([8, 18], 22, 7, 12, 0) == 18)
        // At 06:00 the earliest picked hour is 08:00, which is *not* quiet:
        // quiet ends at 07:00, exclusive. So 08:00 is the answer, and the
        // person is not made to wait until 18:00.
        #expect(Self.hour([8, 18], 22, 7, 6, 0) == 8)
        // At 03:00 the next picked hour is still 08:00, also not quiet.
        #expect(Self.hour([8, 18], 22, 7, 3, 0) == 8)
    }

    @Test("Quiet hours that do not wrap midnight")
    func sameDayQuiet() {
        // Quiet 09:00 to 12:00. Picked 10:00 and 20:00, and it is 11:00 —
        // 10:00 is quiet, so 20:00.
        #expect(Self.hour([10, 20], 9, 12, 11, 0) == 20)
        // At 12:00 quiet has ended — but 10:00 has *passed*, so the next hour
        // ahead is 20:00, not the now-past 10:00.
        #expect(Self.hour([10, 20], 9, 12, 12, 0) == 20)
    }

    @Test("When every picked hour is quiet, nothing is scheduled")
    func allQuiet() {
        // Picked 02:00 and 03:00, both inside 22:00–07:00: no answer.
        #expect(Self.hour([2, 3], 22, 7, 4, 0) == nil)
        // The same for a quiet window that wraps midnight and hours on both
        // sides of it: 06:00 and 23:00 with quiet 22:00–07:00.
        #expect(Self.hour([6, 23], 22, 7, 5, 0) == nil)
    }

    // MARK: - Boundaries

    @Test("Quiet hours sharing an edge with a digest hour")
    func edgeShared() {
        // Quiet 07:00 to 08:00. A digest at 07:00 is inside (the end is
        // exclusive in the ">=" / "<" test), and at 08:00 it is not.
        #expect(Self.hour([7], 7, 8, 6, 0) == nil)
        #expect(Self.hour([8], 7, 8, 6, 0) == 8)
    }

    @Test("A quiet window of nothing schedules normally")
    func emptyQuietWindow() {
        // Start == end is an empty window: nothing is quiet.
        #expect(Self.hour([8, 18], 9, 9, 12, 0) == 18)
    }

    @Test("Midnight is a legitimate digest hour")
    func midnight() {
        #expect(Self.hour([0], nil, nil, 6, 0) == 0)
    }
}
