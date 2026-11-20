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
        WindowGroup(id: AlohaWindow.main) {
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
        #elseif os(visionOS)
            // Portrait, the width of the reading column and a little over:
            // a feed is read downwards, and the default landscape window left
            // the posts a strip down the middle of a sheet of glass.
            .defaultSize(width: 880, height: 1080)
        #endif

        // A thread or a profile in a window of its own, from "Open in New
        // Window" (iPad and visionOS; the iPhone has one window).
        WindowGroup(for: Route.self) { $route in
            RouteWindow(route: route)
                .environment(environment)
        }
        .modelContainer(environment.container)

        #if os(visionOS)
            // The media viewer and video player as windows of their own, so
            // a video can be parked in space while reading continues in the
            // main window (docs/09 §3). Everywhere else they are a cover.
            WindowGroup(for: MediaWindowRequest.self) { $request in
                MediaWindow(request: request)
                    .environment(environment)
                    .mediaWindowFrame(for: request)
            }
            .modelContainer(environment.container)
            // Beside the main window rather than on top of the feed it was
            // opened from, at the media's own shape (`mediaWindowFrame`).
            .defaultWindowPlacement { content, context in
                let main = context.windows.first { $0.id == AlohaWindow.main }
                return WindowPlacement(
                    main.map { .trailing($0) }, size: content.sizeThatFits(.unspecified))
            }
            .windowResizability(.contentSize)
        #endif
    }
}

/// The intents, entities and Focus filter live in AlohaUI; this is what puts
/// them into the app's App Intents metadata, where Shortcuts and Settings →
/// Focus look for them.
struct AlohaSocialAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [AlohaUIAppIntents.self] }
}
