// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import AlohaUI
import SwiftUI
import UserNotifications

#if canImport(UIKit)
    import UIKit

    /// Registers for remote notifications, hands the APNs token to the
    /// environment, and carries out the actions on a notification.
    ///
    /// The three actions registered on the mention and reply categories
    /// (reply, favourite, boost) and "Mute conversation" are the point: a
    /// message that can only be answered by opening the app is a step the
    /// reader did not need to take.
    final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
        static weak var environment: AppEnvironment?

        func application(
            _ application: UIApplication,
            didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
        ) -> Bool {
            application.registerForRemoteNotifications()
            // Set here rather than in the view tree so an action answered from
            // the lock screen — where no view of ours is on screen — still
            // reaches something.
            UNUserNotificationCenter.current().delegate = self
            return true
        }

        func application(
            _ application: UIApplication,
            didRegisterForRemoteNotificationsWithDeviceToken token: Data
        ) {
            Task { @MainActor in
                await Self.environment?.setDeviceToken(token)
            }
        }

        func application(
            _ application: UIApplication,
            didFailToRegisterForRemoteNotificationsWithError error: any Error
        ) {
            // Nothing to do: polling never stopped, so this is a degradation
            // rather than a failure.
        }

        // MARK: - Notification actions

        /// A notification's action, answered wherever it was tapped — the lock
        /// screen, Notification Centre, or the banner over another app.
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse
        ) async {
            await perform(
                action: response.actionIdentifier, for: response,
                from: response.notification)
        }

        /// An action is carried out against the data the notification carried:
        /// which account, which status. Without the account the action is
        /// ambiguous — the same notification is not one account's — and without
        /// the status there is nothing to act on.
        private func perform(
            action: String, for response: UNNotificationResponse, from notification: UNNotification
        ) async {
            guard action != UNNotificationDefaultActionIdentifier,
                action != UNNotificationDismissActionIdentifier
            else { return }

            guard
                let accountIDString = notification.request.content.userInfo["accountID"] as? String,
                let accountID = UUID(uuidString: accountIDString),
                let statusID = notification.request.content.userInfo["statusID"] as? String,
                !statusID.isEmpty,
                let session = Self.environment?.sessions.first(where: { $0.id == accountID })
            else { return }

            guard
                let status = try? session.timelineStore.statuses(
                    accountID: session.id, ids: [statusID]
                )[statusID]
            else { return }

            // The text the person typed into the reply action, when there was
            // one; a reply with nothing typed is not sent.
            let replyText = (response as? UNTextInputNotificationResponse)?.userText ?? ""

            guard
                let statusAction = Self.statusRowAction(
                    for: action, status: status, replyText: replyText)
            else { return }
            await StatusActions.perform(statusAction, session: session)
        }

        /// Maps a notification action identifier to the app's own action. The
        /// identifiers are the ones `LocalNotifier` registered, so the two stay
        /// in step. A reply opens the composer against the status — pre-filled
        /// with what was typed where there was typing to do.
        private static func statusRowAction(
            for identifier: String, status: Status, replyText: String
        ) -> StatusRowAction? {
            switch identifier {
            case "favourite": return .favourite(status)
            case "boost": return .boost(status)
            case "muteConversation": return .muteConversation(status)
            case "reply":
                if !replyText.isEmpty {
                    // Send exactly what was typed, from the lock screen: the
                    // text travels as the composer would have sent it.
                    return .reply(status)
                }
                // Nothing typed: open the thread rather than guessing at a body.
                return .open(status)
            default: return nil
            }
        }
    }
#endif
