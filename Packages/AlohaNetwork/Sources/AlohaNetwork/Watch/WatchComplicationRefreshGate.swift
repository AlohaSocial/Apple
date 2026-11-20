// SPDX-License-Identifier: MIT

import Foundation

/// One server refresh for every complication on the face.
///
/// The unread, mentions and direct-messages complications share a snapshot
/// but each has its own timeline, and WidgetKit asks for all three at once
/// when they fall due — so a stale snapshot used to cost three identical
/// rounds of requests, from a radio the watch would rather keep asleep. A
/// complication that asks while a refresh is running waits for it; one that
/// asks just after takes its answer, including a failure, rather than trying
/// again at once.
public actor WatchComplicationRefreshGate {
    /// One per process: the widget extension's three providers share it.
    public static let shared = WatchComplicationRefreshGate()

    /// How long a finished refresh answers for. Long enough to cover the
    /// three timelines WidgetKit requests together; far shorter than the
    /// fifteen minutes before the snapshot is stale again.
    public static let reuseInterval: TimeInterval = 60

    private var inFlight: (accountID: UUID, task: Task<WatchComplicationSnapshot?, Never>)?
    private var last: (accountID: UUID, at: Date, snapshot: WatchComplicationSnapshot?)?

    public init() {}

    /// `fetch`'s answer for `accountID`: a running one joined, a recent one
    /// reused, or a new one started.
    public func refresh(
        accountID: UUID, now: Date = Date(),
        fetch: @escaping @Sendable () async -> WatchComplicationSnapshot?
    ) async -> WatchComplicationSnapshot? {
        if let inFlight, inFlight.accountID == accountID {
            return await inFlight.task.value
        }
        if let last, last.accountID == accountID,
            (0..<Self.reuseInterval).contains(now.timeIntervalSince(last.at))
        {
            return last.snapshot
        }
        let task = Task { await fetch() }
        inFlight = (accountID, task)
        let result = await task.value
        // The actor is re-entrant: another account's refresh may have
        // started while this one ran, and is not this one to clear.
        if inFlight?.task == task { inFlight = nil }
        last = (accountID, now, result)
        return result
    }
}
