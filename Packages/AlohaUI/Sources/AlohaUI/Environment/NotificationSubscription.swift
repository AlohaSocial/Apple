// SPDX-License-Identifier: MIT

import Foundation

/// A `NotificationCenter` observer that lasts as long as this object does.
///
/// The block runs on whichever thread posted, so it must not touch isolated
/// state itself; callers hop to their actor from inside it. Written instead of
/// a Combine `sink` (docs/12 §1: no Combine).
nonisolated final class NotificationSubscription: Sendable {
    // `NSObjectProtocol` tokens are not marked `Sendable`; this one is only
    // ever handed back to `removeObserver`, which is thread-safe.
    nonisolated(unsafe) private let token: any NSObjectProtocol
    private let center: NotificationCenter

    init(
        name: Notification.Name, center: NotificationCenter = .default,
        _ block: @escaping @Sendable (Notification) -> Void
    ) {
        self.center = center
        self.token = center.addObserver(forName: name, object: nil, queue: nil, using: block)
    }

    deinit {
        center.removeObserver(token)
    }
}
