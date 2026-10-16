// SPDX-License-Identifier: MIT

import AlohaNetwork
import AlohaStore
import AlohaUI
import AppIntents
import AppKit
import Foundation
import SwiftData
import SwiftUI
import UserNotifications

/// The Mac client.
///
/// Nothing here was written twice: this is one SwiftUI app whose shell picks
/// a `NavigationSplitView` with the sidebar on a regular-width window and a tab
/// bar on a compact one (docs/09 §2). The entry exists because a Mac app is a
/// *Mac target* — its own window, menu bar and app identity — and every
/// difference between the platforms is a difference in how the shell is
/// presented, never a second implementation of the app.
@main
struct AlohaSocialMacApp: App {
    /// Exactly one container, built once and reused: a second one against the
    /// same store file leaves the app running with no window (docs/04 §5).
    ///
    /// Static, so the app delegate reaches the same instance when a
    /// notification is clicked before any window exists.
    static let environment = AlohaSocialMacApp.makeEnvironment()

    @State private var environment = AlohaSocialMacApp.environment

    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate

    /// `-AlohaMockServer` boots into a populated timeline against the mock
    /// server, skipping OAuth. DEBUG only.
    private static func makeEnvironment() -> AppEnvironment {
        #if DEBUG
            if MockMode.isEnabled {
                return AppEnvironment(
                    container: StoreContainer.make(inMemory: true),
                    transport: MockMode.makeTransport(),
                    credentials: CredentialStore(inMemory: true))
            }
        #endif
        return AppEnvironment(container: StoreContainer.make())
    }

    var body: some Scene {
        WindowGroup(id: AlohaWindow.main) {
            AppShell()
                .environment(environment)
                .task {
                    BackgroundWork.register(environment: environment)
                    BackgroundWork.scheduleRefresh()
                    BackgroundWork.scheduleMaintenance()
                }
                .modifier(ContinuityReceiver(environment: environment))
        }
        .modelContainer(environment.container)
        .commands { AlohaCommands() }
        // A client is a reading surface: it opens at the width of a timeline
        // plus a thread, not at the default square.
        .defaultSize(width: 1180, height: 820)
        .defaultPosition(.center)

        // A thread or a profile in a window of its own, from "Open in New
        // Window": narrower than the main window, because it holds one column.
        WindowGroup(for: Route.self) { $route in
            RouteWindow(route: route)
                .environment(environment)
        }
        .modelContainer(environment.container)
        .defaultSize(width: 760, height: 820)

        // The Mac's own preferences window (⌘,): the same settings form the
        // app shows in its sidebar destination, rather than a second
        // implementation of it. "Add account" cannot present from here —
        // the sign-in sheet belongs to the main window — so it asks the
        // shell, which owns it, via the same notification mechanism every
        // other entry point uses.
        Settings {
            SettingsView {
                NotificationCenter.default.post(name: .alohaAddAccount, object: nil)
            }
            .environment(environment)
            .alohaTheme(
                environment.theme, metrics: environment.metrics,
                accent: environment.serverAccent)
        }

        // The menu bar extra: a way in from anywhere — new post, the three
        // destinations — without bringing the window forward first. Each item
        // posts what its menu-bar sibling posts, so the extra cannot behave
        // differently from the menu bar it sits next to.
        MenuBarExtra {
            Button {
                activate()
                NotificationCenter.default.post(
                    name: RouteResolver.composeRequested, object: nil)
            } label: {
                Text("New Post", comment: "Menu item")
            }

            Divider()

            Button {
                openRoute(.notifications)
            } label: {
                Text("Notifications", comment: "Menu item")
            }

            Button {
                openRoute(.explore)
            } label: {
                Text("Discover", comment: "Menu item")
            }

            Button {
                openRoute(.conversations)
            } label: {
                Text("Messages", comment: "Menu item")
            }
        } label: {
            Label {
                Text("Aloha Social", comment: "App name")
            } icon: {
                Image(systemName: "bubble.left.and.text.bubble.right")
            }
        }
    }

    /// A menu-bar action lands in a running app whose window may be behind
    /// forty others: bring it forward first, then navigate, so the
    /// destination is actually seen.
    private func activate() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func openRoute(_ route: Route) {
        activate()
        NotificationCenter.default.post(
            name: .alohaOpenRoute, object: nil, userInfo: ["route": route])
    }
}

// The menu bar itself is the shared `AlohaCommands` in AlohaUI — one
// definition for the Mac app and the iPad windowing menu bar, rather than
// two that can disagree (docs/09 §10).

/// The intents, entities and Focus filter live in AlohaUI; this is what puts
/// them into the Mac app's App Intents metadata.
struct AlohaSocialMacAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [AlohaUIAppIntents.self] }
}

/// The Mac's notification delegate.
///
/// The shell raises the same local notifications here as on iOS and registers
/// the same actions, but without a delegate a click only brought the app
/// forward and Reply, Favourite and Boost did nothing. What each one does is
/// `NotificationResponder`'s, shared with the iOS app delegate.
final class MacAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await NotificationResponder.respond(
            NotificationReply(response: response), environment: AlohaSocialMacApp.environment)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        NotificationResponder.presentationOptions(
            forCategory: notification.request.content.categoryIdentifier)
    }
}
