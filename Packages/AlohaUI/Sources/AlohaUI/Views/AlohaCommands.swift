// SPDX-License-Identifier: MIT

import SwiftUI

#if os(macOS) || os(iOS)
    /// The app's menu bar, shared by every target with a menu bar.
    ///
    /// The Mac app had its own `MacCommands` and the iPhone/iPad app had a
    /// smaller local copy — two definitions of what "New Post" means, and
    /// nothing at all on iPad, where iPadOS 26 shows these very commands in
    /// the windowing menu bar. One struct, used by both apps, so the menu bar
    /// cannot disagree with itself (docs/09 §10).
    ///
    /// Everything here goes through the same notifications the deep links use:
    /// the composer request the quick-compose widget posts, and the route
    /// notification Handoff posts. A menu item is an entry point like any
    /// other, so it behaves like the others — including doing nothing graceful
    /// while signed out, where the shell guards both.
    public struct AlohaCommands: Commands {
        public init() {}

        public var body: some Commands {
            CommandGroup(replacing: .newItem) {
                Button {
                    NotificationCenter.default.post(
                        name: RouteResolver.composeRequested, object: nil)
                } label: {
                    Text("New Post", comment: "Menu item")
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("Timeline") {
                Button {
                    openRoute(.notifications)
                } label: {
                    Text("Notifications", comment: "Menu item")
                }
                .keyboardShortcut("1", modifiers: .command)

                Button {
                    openRoute(.explore)
                } label: {
                    Text("Discover", comment: "Menu item")
                }
                .keyboardShortcut("2", modifiers: .command)

                Button {
                    openRoute(.conversations)
                } label: {
                    Text("Messages", comment: "Menu item")
                }
                .keyboardShortcut("3", modifiers: .command)
            }

            CommandGroup(replacing: .help) {
                Link(
                    destination: URL(
                        string: "https://github.com/AlohaSocial/Apple/discussions")!
                ) {
                    Text("Aloha Social on GitHub", comment: "Menu item")
                }
            }
        }

        private func openRoute(_ route: Route) {
            NotificationCenter.default.post(
                name: .alohaOpenRoute, object: nil, userInfo: ["route": route])
        }
    }
#endif
