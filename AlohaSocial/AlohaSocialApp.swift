// SPDX-License-Identifier: MIT

import AlohaNetwork
import AlohaStore
import AlohaUI
import Foundation
import SwiftData
import SwiftUI

@main
struct AlohaSocialApp: App {
    /// Exactly one container. Building a second one against the same store file
    /// leaves the app running with no window, which is not a failure mode worth
    /// discovering twice — `AppEnvironment` owns it and the scene reuses it.
    ///
    /// `StoreContainer` rebuilds the store from scratch rather than trapping
    /// when it cannot be opened: the cache is disposable, and accounts, drafts
    /// and settings do not live in it (docs/04 §5).
    @State private var environment = AlohaSocialApp.makeEnvironment()

    /// `-AlohaMockServer` boots into a populated timeline against the mock
    /// server, skipping OAuth. DEBUG only; the argument does nothing in Release.
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

    #if canImport(UIKit)
        @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(environment)
                .task {
                    #if canImport(UIKit)
                        AppDelegate.environment = environment
                    #endif
                    BackgroundWork.register(environment: environment)
                    BackgroundWork.scheduleRefresh()
                    BackgroundWork.scheduleMaintenance()
                }
                .onContinueUserActivity(Continuity.viewingStatus) { activity in
                    resume(activity)
                }
                .onContinueUserActivity(Continuity.viewingProfile) { activity in
                    resume(activity)
                }
                .onContinueUserActivity(Continuity.viewingTimeline) { activity in
                    resume(activity)
                }
        }
        .modelContainer(environment.container)
        // On every platform with a menu bar: the Mac's own, and the iPad's
        // windowing menu bar, which shows these very commands.
        .commands { AlohaCommands() }
        #if os(macOS)
            .defaultSize(width: 1100, height: 780)
        #endif
    }
}

extension AlohaSocialApp {
    /// Every entry point — scheme, universal link, Handoff, intent,
    /// notification — produces a `Route` and goes through `RouteResolver`, so
    /// none of them can behave differently (docs/09 §10).
    private func resume(_ activity: NSUserActivity) {
        guard let route = Continuity.route(from: activity) else { return }
        NotificationCenter.default.post(
            name: .alohaOpenRoute, object: nil, userInfo: ["route": route])
    }
}


