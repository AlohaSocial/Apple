// SPDX-License-Identifier: MIT

import AlohaDesign
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

    /// Whether the menu bar extra is in the menu bar: off until the person
    /// turns it on in Settings (docs/09 §2).
    @AppStorage(MacMenuBarExtra.isShownKey) private var showsMenuBarExtra = false
    /// Whether the window's ground is the blurred desktop (`MacWindowSettings`).
    @AppStorage(MacWindowSettings.isTranslucentKey) private var isWindowTranslucent = true
    /// The sync engine's unread total, which the Dock badge shows too.
    @AppStorage(AppGroup.unreadTotalKey, store: AppGroup.defaults) private var unreadTotal = 0

    /// The menu bar extra's switch, written only when it really changes.
    ///
    /// `MenuBarExtra` writes its binding back every time the status item
    /// reports its visibility, changed or not. Handed `$showsMenuBarExtra`
    /// directly, each of those writes posted a defaults change, which
    /// re-evaluated this `App`, which applied the visibility again, which
    /// wrote the binding again: the main thread never came back, and the
    /// window that had opened stayed empty.
    private var menuBarExtraInserted: Binding<Bool> {
        Binding(
            get: { showsMenuBarExtra },
            set: { isInserted in
                guard isInserted != showsMenuBarExtra else { return }
                showsMenuBarExtra = isInserted
            })
    }

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
                .providesWindowOpener()
                .environment(\.alohaTranslucentWindow, isWindowTranslucent)
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
                .environment(\.alohaTranslucentWindow, isWindowTranslucent)
        }
        .modelContainer(environment.container)
        .defaultSize(width: 760, height: 820)

        // The composer in a window of its own, so the timeline stays usable
        // while a post is written (docs/09 §2). Not restored at relaunch: a
        // composer closed by quitting has already kept its words as a draft,
        // and reopening it empty beside that draft would be a second copy.
        WindowGroup(for: ComposeWindowRequest.self) { $request in
            ComposeWindow(request: request)
                .environment(environment)
        }
        .modelContainer(environment.container)
        .defaultSize(width: 680, height: 640)
        .restorationBehavior(.disabled)

        // The Mac's own preferences window (⌘,): the same settings form the
        // app shows in its sidebar destination, rather than a second
        // implementation of it. "Add account" cannot present from here —
        // the sign-in sheet belongs to the main window — so it asks the
        // shell, which owns it, via the same notification mechanism every
        // other entry point uses.
        //
        // The Mac's own switches — the window's translucency, the menu bar
        // extra — are panes of their own in its sidebar, so the shared form
        // stays the same on every platform.
        Window(Text("Settings", comment: "Screen title"), id: AlohaWindow.settings) {
            SettingsWindowView(
                panes: [
                    SettingsWindowView.Pane(
                        id: "window",
                        title: String(localized: "Window", comment: "Mac Settings pane"),
                        symbolName: "macwindow",
                        keywords: String(
                            localized: "window translucent transparent blur desktop glass",
                            comment:
                                "Settings search keywords for the Mac's Window pane, separated by spaces. Translate into the words people in your language would type.")
                    ) { MacWindowSettings() },
                    SettingsWindowView.Pane(
                        id: "menu-bar",
                        title: String(localized: "Menu Bar", comment: "Mac Settings pane"),
                        symbolName: "menubar.rectangle",
                        keywords: String(
                            localized: "menu bar extra status unread icon",
                            comment:
                                "Settings search keywords for the Mac's Menu Bar pane, separated by spaces. Translate into the words people in your language would type.")
                    ) { MacMenuBarSettings() },
                ]
            ) {
                NotificationCenter.default.post(name: .alohaAddAccount, object: nil)
            }
            .environment(environment)
            .alohaTheme(
                environment.theme, metrics: environment.metrics,
                accent: environment.serverAccent)
        }
        // A window of the app's own, not a `Settings` scene: that scene's
        // window is fixed at one size whatever its content allows, and this
        // one has a list of panes beside forms of every length. ⌘, and the
        // app menu's Settings… item open it (`AlohaCommands`).
        .defaultSize(width: 780, height: 620)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)

        // The menu bar extra: the unread count, the newest notifications and
        // New Post, from anywhere, without bringing a window forward first.
        MenuBarExtra(isInserted: menuBarExtraInserted) {
            MacMenuBarPanel()
                .environment(environment)
                .modelContainer(environment.container)
        } label: {
            MacMenuBarLabel(unread: unreadTotal)
        }
        .menuBarExtraStyle(.window)
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
    /// Held for the life of the app: AppKit keeps no reference of its own.
    private let services = MacServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NSApplication.shared.servicesProvider = services
    }

    // MARK: - Dock menu

    /// New Post, Activities and the accounts to switch between, from the
    /// Dock (docs/09 §2). Built each time it opens, so the accounts and the
    /// check beside the active one are current.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(
            item(
                String(localized: "New Post", comment: "Menu item"),
                action: #selector(dockNewPost)))
        menu.addItem(
            item(
                String(localized: "Activities", comment: "Menu item"),
                action: #selector(dockActivities)))

        let environment = AlohaSocialMacApp.environment
        // Switching needs somewhere to switch to.
        if environment.sessions.count > 1 {
            menu.addItem(.separator())
            for session in environment.sessions {
                let entry = item(
                    session.snapshot.bestDisplayName, action: #selector(dockSwitchAccount(_:)))
                entry.toolTip = session.snapshot.qualifiedHandle
                entry.representedObject = session.id
                entry.state = session.id == environment.activeSession?.id ? .on : .off
                menu.addItem(entry)
            }
        }
        return menu
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func dockNewPost() {
        MacWindows.compose()
    }

    @objc private func dockActivities() {
        MacWindows.open(.notifications)
    }

    @objc private func dockSwitchAccount(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        AlohaSocialMacApp.environment.setActiveAccount(id)
        MacWindows.activate()
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
