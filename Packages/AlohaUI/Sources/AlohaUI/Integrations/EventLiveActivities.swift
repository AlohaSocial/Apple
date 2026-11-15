// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation
import OSLog

#if os(iOS)
    import ActivityKit
#endif

/// Starts and ends the Live Activities that count down to the active
/// account's own poll closing and its next scheduled post going out
/// (docs/09 §9).
///
/// ActivityKit lets an app start an activity only while it is in front, so
/// this runs when the app becomes active, after the widget snapshot has been
/// refreshed — the snapshot already holds the open poll and the scheduled
/// posts. The countdown runs by itself (`Text(timerInterval:)`); nothing
/// pushes an update. An activity is marked stale at its moment, ended by a
/// timer while the app still runs, and otherwise ended at the next
/// activation or background refresh.
@MainActor
public enum EventLiveActivities {
    /// The person's own switch, in Settings. On unless turned off.
    public static let enabledKey = "aloha.liveActivities.events"
    /// How long an ended countdown stays on the Lock Screen saying the poll
    /// closed or the post went out, before it goes.
    nonisolated static let lingerAfterEvent: TimeInterval = 5 * 60
    /// How old a snapshot may be and still be trusted with a countdown: a
    /// post rescheduled or a poll deleted since is not worth a wrong timer.
    nonisolated static let snapshotFreshness: TimeInterval = 15 * 60

    private static let logger = Logger(subsystem: "social.aloha.app", category: "liveActivities")

    public static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Whether the system lets this app show Live Activities at all, which
    /// a person can turn off in the system's Settings.
    public static var areSystemActivitiesEnabled: Bool {
        #if os(iOS)
            ActivityAuthorizationInfo().areActivitiesEnabled
        #else
            false
        #endif
    }

    /// Brings the countdowns in line with what is coming up for the active
    /// account: starts the missing ones, ends the ones whose moment passed or
    /// that no longer match (a post rescheduled, a poll deleted), and ends
    /// everything when the switch is off.
    public static func update(_ environment: AppEnvironment, now: Date = Date()) async {
        #if os(iOS)
            guard isEnabled, areSystemActivitiesEnabled,
                let session = environment.activeSession, !session.needsReauthentication
            else {
                await endAll()
                return
            }
            let events = await upcoming(for: session, now: now)
            let running = Activity<EventActivityAttributes>.activities
            for activity in running {
                let attributes = activity.attributes
                let state = activity.content.state
                let stillComing = events.contains {
                    $0.kind == attributes.kind && $0.itemID == attributes.itemID
                        && $0.at == state.at
                }
                // Another account's countdown is still true; it stays until
                // its moment, like any other.
                let otherAccount = attributes.accountID != session.id && state.at > now
                if !stillComing && !otherAccount {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
            for event in events {
                let isRunning = Activity<EventActivityAttributes>.activities.contains {
                    $0.attributes.kind == event.kind && $0.attributes.itemID == event.itemID
                        && $0.attributes.accountID == session.id
                }
                if !isRunning { start(event, accountID: session.id, now: now) }
            }
            scheduleEnds()
        #endif
    }

    /// Ends every countdown whose moment has passed. What a background
    /// refresh can do: ending, unlike starting, works from the background.
    public static func endFinished(now: Date = Date()) async {
        #if os(iOS)
            // Looked up and ended in one place: an `Activity` is not
            // `Sendable`, so one handed in from elsewhere could not be ended.
            for activity in Activity<EventActivityAttributes>.activities
            where activity.content.state.at <= now {
                let state = activity.content.state
                // Left on the Lock Screen a few minutes, saying what happened.
                await activity.end(
                    .init(state: state, staleDate: nil),
                    dismissalPolicy: .after(state.at.addingTimeInterval(lingerAfterEvent)))
            }
        #endif
    }

    /// The switch turned off.
    public static func endAll() async {
        #if os(iOS)
            for activity in Activity<EventActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        #endif
    }

    /// What is coming up, from the widget snapshot where it is fresh, and
    /// from the server otherwise — a build without the app group has no
    /// snapshot at all.
    static func upcoming(
        for session: AccountSession, now: Date
    ) async -> [EventActivityPlanner.Event] {
        if let store = WidgetSnapshotStore.shared, let snapshot = store.read(accountID: session.id),
            now.timeIntervalSince(snapshot.writtenAt) < snapshotFreshness
        {
            return EventActivityPlanner.upcoming(in: snapshot, now: now)
        }
        let client = session.client
        let serverAccountID = session.snapshot.serverAccountID
        async let scheduled = try? client.decode(
            LossyArray<ScheduledStatus>.self, from: Endpoint.composing.scheduled
        ).elements
        async let ownPosts = try? client.decode(
            LossyArray<Status>.self,
            from: Endpoint.timelines.timeline(
                .account(id: serverAccountID, includeReplies: false, onlyMedia: false), limit: 20)
        ).elements
        let fetched = await WidgetSnapshotWriter.Fetched(scheduled: scheduled, ownPosts: ownPosts)
        let snapshot = WidgetSnapshotWriter.merge(
            fetched, into: nil, accountID: session.id, handle: session.snapshot.qualifiedHandle,
            serverAccountID: serverAccountID, aloha: session.capabilities.isNextcloudSocial,
            now: now)
        return EventActivityPlanner.upcoming(in: snapshot, now: now)
    }

    #if os(iOS)
        private static func start(
            _ event: EventActivityPlanner.Event, accountID: UUID, now: Date
        ) {
            let attributes = EventActivityAttributes(
                kind: event.kind, accountID: accountID, itemID: event.itemID, startedAt: now)
            let state = EventActivityAttributes.ContentState(at: event.at, text: event.text)
            do {
                // Stale at its moment: the view then says the poll closed or
                // the post went out, even if nothing ends it on time.
                _ = try Activity.request(
                    attributes: attributes, content: .init(state: state, staleDate: event.at))
            } catch {
                // Refused — too many activities, or turned off a moment ago.
                // Not worth more than a line: the widgets show the same.
                logger.notice(
                    "countdown not started: \(String(describing: error), privacy: .public)")
            }
        }

        /// Ends each running countdown at its moment while this process
        /// lives. Re-armed on every update; an older timer finding nothing to
        /// end does nothing.
        private static var endTimer: Task<Void, Never>?

        private static func scheduleEnds() {
            endTimer?.cancel()
            guard
                let next = Activity<EventActivityAttributes>.activities
                    .map(\.content.state.at).filter({ $0 > Date() }).min()
            else { return }
            endTimer = Task {
                try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow) + 1))
                guard !Task.isCancelled else { return }
                await endFinished()
                scheduleEnds()
            }
        }
    #endif
}
