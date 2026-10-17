// SPDX-License-Identifier: MIT

import SwiftUI

#if os(macOS) || os(iOS) || os(visionOS)
    /// The app's menu bar, shared by every target with a menu bar — and the
    /// keyboard shortcuts of a visionOS window, which has none to show them in.
    ///
    /// The Mac app had its own `MacCommands` and the iPhone/iPad app had a
    /// smaller local copy — two definitions of what "New Post" means, and
    /// nothing at all on iPad, where iPadOS 26 shows these very commands in
    /// the windowing menu bar. One struct, used by both apps, so the menu bar
    /// cannot disagree with itself (docs/09 §10).
    ///
    /// Each item acts on the window in front, through the focused values the
    /// shell and the timeline publish (`ShellCommands`, `TimelineCommands`).
    /// With no window to act on — every window closed on the Mac — the
    /// app-wide items fall back to the notifications the deep links use, which
    /// the shell guards while signed out.
    public struct AlohaCommands: Commands {
        @FocusedValue(\.shellCommands) private var shell
        @FocusedValue(\.timelineCommands) private var timeline
        @Environment(\.openWindow) private var openWindow

        public init() {}

        public var body: some Commands {
            // Replacing the group takes File > New Window with it, so it is
            // put back — on ⌥⌘N, the way Mail pairs New Message with New
            // Viewer Window, because ⌘N is the post.
            CommandGroup(replacing: .newItem) {
                Button {
                    if let shell {
                        shell.compose()
                    } else {
                        NotificationCenter.default.post(
                            name: RouteResolver.composeRequested, object: nil)
                    }
                } label: {
                    Text("New Post", comment: "Menu item")
                }
                .keyboardShortcut("n", modifiers: .command)

                Button {
                    openWindow(id: AlohaWindow.main)
                } label: {
                    Text("New Window", comment: "Menu item")
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
            }

            CommandMenu(Text("Go", comment: "Menu title")) {
                Button {
                    shell?.back()
                } label: {
                    Text("Back", comment: "Menu item")
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(shell?.canGoBack != true)

                Divider()

                Button {
                    open(.timeline(.home()))
                } label: {
                    Text("Home", comment: "Menu item")
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                // ⌘1… in the sidebar's own order (`ShellPlace`). They used to
                // be Notifications, Discover and Messages, which matched no
                // list on screen — ⌘1 was a place the Mac sidebar does not
                // even show.
                ForEach(Array(places.enumerated()), id: \.element) { index, place in
                    placeButton(place, digit: ShellPlace.shortcutDigit(at: index))
                }

                if !places.contains(where: { $0.route == .notifications }) {
                    Button {
                        open(.notifications)
                    } label: {
                        Text("Notifications", comment: "Menu item")
                    }
                }

                Button {
                    open(.search(query: nil))
                } label: {
                    Text("Search", comment: "Menu item")
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            CommandMenu(Text("Timeline", comment: "Menu title")) {
                Button {
                    timeline?.refresh()
                } label: {
                    Text("Refresh", comment: "Menu item")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(timeline == nil)

                Divider()

                Button {
                    timeline?.move(1)
                } label: {
                    Text("Next Post", comment: "Menu item")
                }
                .timelineKey("j")
                .disabled(timeline == nil)

                Button {
                    timeline?.move(-1)
                } label: {
                    Text("Previous Post", comment: "Menu item")
                }
                .timelineKey("k")
                .disabled(timeline == nil)

                Divider()

                postAction(.favourite, key: "l") {
                    Text("Favourite", comment: "Menu item: the post in focus")
                }
                postAction(.boost, key: "b") {
                    Text("Boost", comment: "Menu item: the post in focus")
                }
                postAction(.reply, key: "r") {
                    Text("Reply", comment: "Menu item: the post in focus")
                }
                postAction(.open, key: "o") {
                    Text("Open Post", comment: "Menu item: the post in focus")
                }
            }

            CommandGroup(replacing: .help) {
                if let discussions = URL(string: "https://github.com/AlohaSocial/Apple/discussions")
                {
                    Link(destination: discussions) {
                        Text("Aloha Social on GitHub", comment: "Menu item")
                    }
                }
            }
        }

        private func postAction(
            _ action: TimelineCommands.Action, key: KeyEquivalent, label: () -> Text
        ) -> some View {
            Button {
                timeline?.act(action)
            } label: {
                label()
            }
            .timelineKey(key)
            .disabled(timeline?.hasFocusedPost != true)
        }

        /// The front window's places, or — with no window to ask, every one
        /// closed on the Mac — the three every account has.
        private var places: [ShellPlace] {
            shell?.places
                ?? ShellPlace.sidebarOrder(
                    modes: [.home], includesActivities: false,
                    modeTitle: { _ in String(localized: "My Feed", comment: "Mode title") })
        }

        @ViewBuilder
        private func placeButton(_ place: ShellPlace, digit: Character?) -> some View {
            let button = Button {
                open(place.route)
            } label: {
                Text(verbatim: place.title)
            }
            if let digit {
                button.keyboardShortcut(KeyEquivalent(digit), modifiers: .command)
            } else {
                button
            }
        }

        private func open(_ route: Route) {
            if let shell {
                shell.open(route)
            } else {
                NotificationCenter.default.post(
                    name: .alohaOpenRoute, object: nil, userInfo: ["route": route])
            }
        }
    }

    extension View {
        /// The timeline's single keys, as the web has them, on the iPad's
        /// menu bar, where a menu item is how a hardware keyboard reaches a
        /// list that is not focusable (see `TimelineKeyboardModifier`). Text
        /// input keeps priority over a modifier-less key command, so typing a
        /// "j" into the composer is still a "j".
        ///
        /// Not on the Mac: there the focused list takes the keys itself, and a
        /// menu equivalent with no modifier would fire from inside text
        /// fields.
        @ViewBuilder
        fileprivate func timelineKey(_ key: KeyEquivalent) -> some View {
            #if os(iOS)
                keyboardShortcut(key, modifiers: [])
            #else
                self
            #endif
        }
    }
#endif
