// SPDX-License-Identifier: MIT

import AlohaNetwork
import AlohaStore
import AlohaUI
import AppKit
import Foundation
import SwiftData
import SwiftUI

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
    @State private var environment = AlohaSocialMacApp.makeEnvironment()

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
        WindowGroup {
            AppShell()
                .environment(environment)
                .task {
                    BackgroundWork.register(environment: environment)
                    BackgroundWork.scheduleRefresh()
                    BackgroundWork.scheduleMaintenance()
                }
                .onContinueUserActivity(Continuity.viewingStatus) { activity in resume(activity) }
                .onContinueUserActivity(Continuity.viewingProfile) { activity in resume(activity) }
                .onContinueUserActivity(Continuity.viewingTimeline) { activity in resume(activity) }
        }
        .modelContainer(environment.container)
        .commands { MacCommands() }
        // A client is a reading surface: it opens at the width of a timeline
        // plus a thread, not at the default square.
        .defaultSize(width: 1180, height: 820)
        .defaultPosition(.center)
    }
}

/// The Mac menu bar.
///
/// New Post goes through the same `alohasocial://compose` link the
/// quick-compose widget and the Shortcuts use, so there is one definition of
/// what opening the composer means and every entry point behaves identically
/// (docs/09 §10).
struct MacCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button {
                NSWorkspace.shared.open(URL(string: "alohasocial://compose")!)
            } label: {
                Text("New Post", comment: "Menu item")
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("Timeline") {
            Button {
                NotificationCenter.default.post(
                    name: .alohaOpenRoute, object: nil,
                    userInfo: ["route": Route.notifications])
            } label: {
                Text("Notifications", comment: "Menu item")
            }
            .keyboardShortcut("1", modifiers: .command)

            Button {
                NotificationCenter.default.post(
                    name: .alohaOpenRoute, object: nil,
                    userInfo: ["route": Route.explore])
            } label: {
                Text("Discover", comment: "Menu item")
            }
            .keyboardShortcut("2", modifiers: .command)

            Button {
                NotificationCenter.default.post(
                    name: .alohaOpenRoute, object: nil,
                    userInfo: ["route": Route.conversations])
            } label: {
                Text("Messages", comment: "Menu item")
            }
            .keyboardShortcut("3", modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Button {
                if let url = URL(string: "https://github.com/AlohaSocial/Apple/discussions") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("Aloha Social on GitHub", comment: "Menu item")
            }
        }
    }
}

extension AlohaSocialMacApp {
    /// Every entry point — scheme, universal link, Handoff, intent,
    /// notification — produces a `Route` through `RouteResolver`, so none of
    /// them can behave differently (docs/09 §10).
    private func resume(_ activity: NSUserActivity) {
        guard let route = Continuity.route(from: activity) else { return }
        NotificationCenter.default.post(
            name: .alohaOpenRoute, object: nil, userInfo: ["route": route])
    }
}
