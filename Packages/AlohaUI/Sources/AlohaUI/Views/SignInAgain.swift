// SPDX-License-Identifier: MIT

import Foundation
import SwiftUI

/// Asks for a fresh sign-in to an account that is already on this device —
/// the way back from "your sign-in has expired".
///
/// The sign-in sheet belongs to the shell, but the places that know an
/// account has expired are deep inside it: the timeline's banner, the
/// account rows in Settings, the account menu. The shell puts this action in
/// the environment so each of them can ask its own window for the sheet; a
/// notification would reach every open window and put a sheet up in each.
nonisolated struct SignInAgainAction: Sendable {
    let perform: @MainActor @Sendable (UUID) -> Void

    @MainActor func callAsFunction(_ accountID: UUID) { perform(accountID) }

    /// Where there is no shell above — the Mac's Settings window is a scene of
    /// its own — the request goes to the main window's shell, the same way
    /// "Add account" does from there.
    static let viaMainWindow = SignInAgainAction { accountID in
        NotificationCenter.default.post(
            name: .alohaSignInAgain, object: nil,
            userInfo: [SignInAgainAction.accountIDKey: accountID])
    }

    static let accountIDKey = "accountID"
}

extension EnvironmentValues {
    @Entry var signInAgain: SignInAgainAction = .viaMainWindow
}

extension Notification.Name {
    /// Posted when something outside the main window asks to sign an expired
    /// account in again; the user info carries the account's id.
    static let alohaSignInAgain = Notification.Name("aloha.signInAgain")
}
