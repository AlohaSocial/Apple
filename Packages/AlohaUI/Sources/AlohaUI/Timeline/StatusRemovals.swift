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
}

extension View {
    /// Runs `perform` for every removal on this account for as long as the
    /// view exists, so a list holding its own copies of posts can drop them.
    ///
    /// Also while another screen is pushed over it: blocking somebody from
    /// the profile opened from a list must leave the list without them when
    /// the person goes back. A `.task` would end as the list disappeared
    /// under the profile, and miss exactly that.
    func onStatusesRemoved(
        for session: AccountSession,
        perform: @escaping (TimelineStatusRemoval) -> Void
    ) -> some View {
        modifier(StatusRemovalListener(accountID: session.id, perform: perform))
    }
}

/// Holds the subscription in view state, which lives as long as the view's
/// identity rather than only while it is on screen.
private struct StatusRemovalListener: ViewModifier {
    let accountID: UUID
    let perform: (TimelineStatusRemoval) -> Void
    @State private var listener = Listener()

    func body(content: Content) -> some View {
        // Handed over on every update, so a removal always reaches the view
        // as it is now.
        let _ = listener.update(accountID: accountID, perform: perform)
        content
    }

    @MainActor
    private final class Listener {
        private var accountID: UUID?
        private var perform: ((TimelineStatusRemoval) -> Void)?
        private var subscription: NotificationSubscription?

        func update(accountID: UUID, perform: @escaping (TimelineStatusRemoval) -> Void) {
            self.accountID = accountID
            self.perform = perform
            guard subscription == nil else { return }
            subscription = StatusRemovals.observe { [weak self] removal in
                self?.receive(removal)
            }
        }

        private func receive(_ removal: TimelineStatusRemoval) {
            guard removal.accountID == accountID else { return }
            perform?(removal)
        }
    }
}
