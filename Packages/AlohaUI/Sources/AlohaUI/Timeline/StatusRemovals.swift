// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaStore
import Foundation
import SwiftUI

/// How a list on screen hears that posts have gone — deleted, archived, or
/// by somebody just blocked or muted (`TimelineStatusRemoval`).
///
/// Blocking somebody and still seeing them until the next refresh is not
/// blocking (docs/11 §1.3), and a post deleted over streaming should not sit
/// there to be replied to. The store says what went the moment it goes;
/// every open list drops those rows itself.
enum StatusRemovals {
    /// For a model: removals heard on the main actor, for as long as the
    /// returned object lives. Store writes post from the store's own thread.
    nonisolated static func observe(
        _ receive: @escaping @MainActor @Sendable (TimelineStatusRemoval) -> Void
    ) -> NotificationSubscription {
        NotificationSubscription(name: TimelineStatusRemoval.notification) { notification in
            guard let removal = notification.object as? TimelineStatusRemoval else { return }
            Task { @MainActor in receive(removal) }
        }
    }

    /// For a view: removals as a sequence, ending when the task that reads it
    /// is cancelled.
    nonisolated static func stream() -> AsyncStream<TimelineStatusRemoval> {
        AsyncStream { continuation in
            let subscription = NotificationSubscription(
                name: TimelineStatusRemoval.notification
            ) { notification in
                guard let removal = notification.object as? TimelineStatusRemoval else { return }
                continuation.yield(removal)
            }
            continuation.onTermination = { _ in withExtendedLifetime(subscription) {} }
        }
    }
}

extension View {
    /// Runs `perform` for every removal on this account while the view is
    /// on screen, so a list holding its own copies of posts can drop them.
    func onStatusesRemoved(
        for session: AccountSession,
        perform: @escaping (TimelineStatusRemoval) -> Void
    ) -> some View {
        task(id: session.id) {
            for await removal in StatusRemovals.stream() where removal.accountID == session.id {
                perform(removal)
            }
        }
    }
}
