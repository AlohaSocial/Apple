// SPDX-License-Identifier: MIT

import AlohaNetwork
import AlohaStore
import AlohaUI
import AppIntents
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
    ///
    /// Static, so the app delegate reaches the same instance at launch — before
    /// any scene exists, which is where a notification action answered from
    /// the lock screen arrives.
    static let environment = AlohaSocialApp.makeEnvironment()

    @State private var environment = AlohaSocialApp.environment

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
                    // Registration happens once, at launch, in `AppDelegate`.
                    BackgroundWork.scheduleRefresh()
                    BackgroundWork.scheduleMaintenance()
                }
                .modifier(ContinuityReceiver(environment: environment))
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

/// The intents, entities and Focus filter live in AlohaUI; this is what puts
/// them into the app's App Intents metadata, where Shortcuts and Settings →
/// Focus look for them.
struct AlohaSocialAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [AlohaUIAppIntents.self] }
}
