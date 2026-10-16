// SPDX-License-Identifier: MIT

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
    /// reader did not need to take. What each one does lives in
    /// `NotificationResponder`, shared with the Mac.
    final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
        /// The app's one environment, reachable from launch rather than from
        /// the first window's `.task`: a reply sent from the lock screen
        /// launches the app in the background, where no window is ever built,
        /// and used to find nothing here and be dropped.
        private var environment: AppEnvironment { AlohaSocialApp.environment }

        func application(
            _ application: UIApplication,
            didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
        ) -> Bool {
            application.registerForRemoteNotifications()
            // Set here rather than in the view tree so an action answered from
            // the lock screen — where no view of ours is on screen — still
            // reaches something.
            UNUserNotificationCenter.current().delegate = self
            // Once, during launch, which is what `BGTaskScheduler` requires: in
            // a window's `.task` it ran late, and again for every iPad window,
            // and registering an identifier twice raises.
            BackgroundWork.register(environment: environment)
            return true
        }

        func application(
            _ application: UIApplication,
            didRegisterForRemoteNotificationsWithDeviceToken token: Data
        ) {
            Task { @MainActor in
                await environment.setDeviceToken(token)
            }
        }

        func application(
            _ application: UIApplication,
            didFailToRegisterForRemoteNotificationsWithError error: any Error
        ) {
            // Nothing to do: polling never stopped, so this is a degradation
            // rather than a failure.
        }

        // MARK: - Notifications

        /// A notification's tap or action, answered wherever it happened — the
        /// lock screen, Notification Centre, or the banner over another app.
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse
        ) async {
            await NotificationResponder.respond(
                NotificationReply(response: response), environment: environment)
        }

        /// A notification raised while the app is in front: see
        /// `NotificationResponder.presentationOptions(forCategory:)`.
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification
        ) async -> UNNotificationPresentationOptions {
            NotificationResponder.presentationOptions(
                forCategory: notification.request.content.categoryIdentifier)
        }
    }
#endif
