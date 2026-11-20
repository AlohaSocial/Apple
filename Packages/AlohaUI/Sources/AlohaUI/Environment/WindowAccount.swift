// SPDX-License-Identifier: MIT

import Foundation
import SwiftUI

/// Which account a window shows.
///
/// The active account used to be the app's one answer, so switching account
/// in one window switched every window, and a thread restored in a window of
/// its own was looked up under whichever account happened to be active — a
/// post id is one server's id, so that was somebody else's post, or none.
/// A window now keeps its own: a main window remembers it in its scene
/// storage, a window opened for one destination carries it in its value
/// (`RouteWindowRequest`), and the active account is only the default a new
/// window starts on (docs/09 §2).
public enum WindowAccount {
    /// A request to show an account, from a window's own switcher or from
    /// outside any window: the Dock menu, a notification, a link, a Focus.
    /// Numbered, so the same account asked for twice is two requests.
    public struct Request: Equatable, Sendable {
        public var serial: Int
        public var accountID: UUID?

        public init(serial: Int, accountID: UUID?) {
            self.serial = serial
            self.accountID = accountID
        }
    }

    /// The account a window shows: the one it is pinned to (a window opened
    /// for one destination), else the one it remembers, else the default —
    /// each only while it is still signed in here.
    static func resolve(
        pinned: UUID?, stored: String?, signedIn: [UUID], fallback: UUID?
    ) -> UUID? {
        if let pinned, signedIn.contains(pinned) { return pinned }
        if let stored = stored.flatMap(UUID.init(uuidString:)), signedIn.contains(stored) {
            return stored
        }
        return fallback
    }

    /// Whether a window takes up a request: only a main window, only the one
    /// in front (or the only one, before any has been in front), and only a
    /// request it has not already answered. A window opened for one
    /// destination never does — its post belongs to its account.
    static func adopts(
        _ request: Request, answered: Int, isFront: Bool, isPinned: Bool
    ) -> Bool {
        guard !isPinned, request.accountID != nil, request.serial > answered else { return false }
        return isFront
    }
}

extension EnvironmentValues {
    /// The account of the window this view is in; nil where no window has
    /// said, which reads as the active account (`AppEnvironment.session(for:)`).
    @Entry public var windowAccountID: UUID?
}
