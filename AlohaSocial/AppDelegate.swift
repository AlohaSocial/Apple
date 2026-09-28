// SPDX-License-Identifier: MIT

import AlohaUI
import SwiftUI

#if canImport(UIKit)
    import UIKit

    /// Registers for remote notifications and hands the APNs token to the
    /// environment, which forwards it to Nextcloud's push proxy for every
    /// account that has a connected Nextcloud.
    final class AppDelegate: NSObject, UIApplicationDelegate {
        static weak var environment: AppEnvironment?

        func application(
            _ application: UIApplication,
            didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
        ) -> Bool {
            application.registerForRemoteNotifications()
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
    }
#endif
