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
    /// shell and the lists publish (`ShellCommands`, `TimelineCommands`). With
    /// no window to act on — every window closed on the Mac — the app-wide
    /// items fall back to the notifications the deep links use, which the
    /// shell guards while signed out.
    ///
    /// The Mac's menu bar is docs/09 §2's: File (New Post ⌘N, New Window ⌥⌘N,
    /// Open Link… ⌘L), View (sidebar, toolbar, Columns and Trends, Refresh,
    /// text size), Go, Post (acting on the selected post), Account, Window
    /// and Help. The keys are listed for people in `KeyboardShortcuts`.
    public struct AlohaCommands: Commands {
        @FocusedValue(\.shellCommands) private var shell
        @FocusedValue(\.timelineCommands) private var focusedTimeline
        @FocusedValue(\.sceneTimelineCommands) private var sceneTimeline
        @FocusedValue(\.refreshCommand) private var refreshCommand
        @Environment(\.openWindow) private var openWindow
        #if os(macOS)
            @AppStorage(MacOptions.deckKey) private var showsDeck = false
            @AppStorage(MacOptions.contextColumnKey) private var showsContextColumn = false
            @AppStorage(MacOptions.textSizeKey) private var textSizeStep = 0
        #endif

        public init() {}

        /// The list being read: the one with the keyboard focus, else the
        /// one on screen. A Deck column publishes only the first, so ⌘R and
        /// the Post menu act on the column in use rather than on all three.
        private var timeline: TimelineCommands? { focusedTimeline ?? sceneTimeline }

        public var body: some Commands {
            #if os(macOS)
                // The app menu's own Settings… item, on ⌘, as everywhere —
                // opening the app's settings window rather than a `Settings`
                // scene, whose window cannot be resized.
                CommandGroup(replacing: .appSettings) {
                    Button {
                        openWindow(id: AlohaWindow.settings)
                    } label: {
                        Text("Settings…", comment: "Menu item")
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
                SidebarCommands()
                ToolbarCommands()
            #endif

            // Replacing the group takes File > New Window with it, so it is
            // put back. ⌘N is the post everywhere, as in every app whose
            // document is a post or a message (Mail's ⌘N is a new message, not
            // a new viewer window), and New Window is ⌥⌘N. The Mac used to have
            // them the other way round, and its toolbar's compose button
            // claimed ⌘N as well.
            CommandGroup(replacing: .newItem) {
                Button {
                    compose()
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

                #if os(macOS)
                    Divider()

                    Button {
                        shell?.openLink()
                    } label: {
                        Text(
                            "Open Link…",
                            comment: "Menu item: open a post or a profile by its address")
                    }
                    .keyboardShortcut("l", modifiers: .command)
                    .disabled(shell == nil)
                #endif
            }

            #if os(macOS)
                viewCommands

                CommandGroup(after: .windowArrangement) {
                    Button {
                        openWindow(id: AlohaWindow.mini)
                    } label: {
                        Text("Mini Timeline", comment: "Menu item: a small floating timeline")
                    }
                    // Not ⌥⌘M, which is the system's Minimize All.
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                }
            #endif

            CommandMenu(Text("Go", comment: "Menu title")) {
                #if os(macOS)
                    Button {
                        shell?.jump()
                    } label: {
                        Text("Go to…", comment: "Menu item: opens the command palette")
                    }
                    .keyboardShortcut("k", modifiers: .command)
                    .disabled(shell == nil)

                    Divider()
                #endif
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
                    Text("My Feed", comment: "Menu item")
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                // ⌘1… in the sidebar's own order (`ShellPlace`). They used to
                // be Notifications, Discover and Messages, which matched no
                // list on screen — ⌘1 was a place the Mac sidebar does not
                // even show.
                ForEach(Array(places.enumerated()), id: \.element) { index, place in
                    placeButton(place, digit: ShellPlace.shortcutDigit(at: index))
                }

                Button {
                    // The toolbar's field, where the window has one.
                    if let shell { shell.search() } else { open(.search(query: nil)) }
                } label: {
                    Text("Search", comment: "Menu item")
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            #if os(macOS)
                postCommands
                accountCommands
            #else
                timelineCommands
            #endif

            CommandGroup(replacing: .help) {
                #if os(macOS)
                    Button {
                        shell?.showShortcuts()
                    } label: {
                        Text("Keyboard Shortcuts", comment: "Menu item")
                    }
                    .keyboardShortcut("/", modifiers: .command)
                    .disabled(shell == nil)

                    Divider()
                #endif
                if let discussions = URL(string: "https://github.com/AlohaSocial/Apple/discussions")
                {
                    Link(destination: discussions) {
                        Text("Aloha Social on GitHub", comment: "Menu item")
                    }
                }
            }
        }

        /// A new post from the window in front, as its account; with every
        /// window closed, a compose window for the active account.
        private func compose() {
            if let shell {
                shell.compose()
            } else {
                #if os(macOS)
                    openWindow(value: ComposeWindowRequest())
                #else
                    NotificationCenter.default.post(
                        name: RouteResolver.composeRequested, object: nil)
                #endif
            }
        }

        /// ⌘R: the list being read, or any refreshable screen in front.
        private var refresh: (() -> Void)? {
            if let timeline, timeline.canRefresh { return timeline.refresh }
            return refreshCommand?.refresh
        }

        #if !os(macOS)
            /// The iPad's Timeline menu: its single keys, the web's, reach a
            /// list that cannot take the keyboard's focus. Text input keeps
            /// priority over a modifier-less key command, so a "j" typed into
            /// the composer is still a "j".
            @CommandsBuilder
            private var timelineCommands: some Commands {
                CommandMenu(Text("Timeline", comment: "Menu title")) {
                    Button {
                        refresh?()
                    } label: {
                        Text("Refresh", comment: "Menu item")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(refresh == nil)

                    Divider()

                    Button {
                        timeline?.move(1)
                    } label: {
                        Text("Next Post", comment: "Menu item")
                    }
                    .singleKey("j")
                    .disabled(timeline == nil)

                    Button {
                        timeline?.move(-1)
                    } label: {
                        Text("Previous Post", comment: "Menu item")
                    }
                    .singleKey("k")
                    .disabled(timeline == nil)

                    Divider()

                    postAction(.favourite, key: "l", modifiers: []) {
                        Text("Like", comment: "Menu item: the post in focus")
                    }
                    postAction(.boost, key: "b", modifiers: []) {
                        Text("Boost", comment: "Menu item: the post in focus")
                    }
                    postAction(.reply, key: "r", modifiers: []) {
                        Text("Reply", comment: "Menu item: the post in focus")
                    }
                    postAction(.open, key: "o", modifiers: []) {
                        Text("Open Post", comment: "Menu item: the post in focus")
                    }
                }
            }
        #endif

        #if os(macOS)
            /// View: the layout switches that used to be only in Settings,
            /// Refresh and the text size, above the sidebar and toolbar items
            /// `SidebarCommands` and `ToolbarCommands` bring.
            @CommandsBuilder
            private var viewCommands: some Commands {
                CommandGroup(before: .sidebar) {
                    Toggle(isOn: $showsDeck) {
                        Text(
                            "Show Columns",
                            comment: "Menu item: My Feed, Activities and Local side by side")
                    }
                    .keyboardShortcut("d", modifiers: [.command, .control])
                    Toggle(isOn: $showsContextColumn) {
                        Text(
                            "Show Trends",
                            comment: "Menu item: the column of trends beside the feed")
                    }
                    .keyboardShortcut("t", modifiers: [.command, .control])
                    .disabled(showsDeck)

                    Divider()

                    Button {
                        refresh?()
                    } label: {
                        Text("Refresh", comment: "Menu item")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(refresh == nil)

                    Divider()

                    Button {
                        textSizeStep = 0
                    } label: {
                        Text("Actual Size", comment: "Menu item: text size")
                    }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(textSizeStep == 0)
                    Button {
                        textSizeStep = min(textSizeStep + 1, MacTextSize.steps.upperBound)
                    } label: {
                        Text("Bigger", comment: "Menu item: text size")
                    }
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(textSizeStep >= MacTextSize.steps.upperBound)
                    Button {
                        textSizeStep = max(textSizeStep - 1, MacTextSize.steps.lowerBound)
                    } label: {
                        Text("Smaller", comment: "Menu item: text size")
                    }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(textSizeStep <= MacTextSize.steps.lowerBound)

                    Divider()
                }
            }

            /// Post: what a person does to the selected post. ⌘R is Refresh,
            /// as in every reading app on the Mac, so Reply is ⇧⌘R.
            @CommandsBuilder
            private var postCommands: some Commands {
                CommandMenu(Text("Post", comment: "Menu title")) {
                    postAction(.open, key: "o", modifiers: .command) {
                        Text("Open", comment: "Menu item: the selected post")
                    }
                    postAction(.peek, key: "y", modifiers: .command) {
                        Text("Quick Look", comment: "Menu item: a look at the selected post")
                    }

                    Divider()

                    postAction(.reply, key: "r", modifiers: [.command, .shift]) {
                        Text("Reply", comment: "Menu item: the selected post")
                    }
                    postAction(.boost, key: "b", modifiers: [.command, .shift]) {
                        Text("Boost", comment: "Menu item: the selected post")
                    }
                    postAction(.favourite, key: "l", modifiers: [.command, .shift]) {
                        Text("Like", comment: "Menu item: the selected post")
                    }
                    postAction(.bookmark, key: "d", modifiers: .command) {
                        Text("Bookmark", comment: "Menu item: the selected post")
                    }
                    postAction(.translate, key: "t", modifiers: [.command, .shift]) {
                        Text("Translate", comment: "Menu item: the selected post")
                    }

                    Divider()

                    postAction(.copyLink, key: "c", modifiers: [.command, .shift]) {
                        Text("Copy Link", comment: "Menu item: the selected post's address")
                    }
                    postAction(.openInBrowser, key: "o", modifiers: [.command, .option]) {
                        Text("Open in Browser", comment: "Menu item: the selected post")
                    }

                    Divider()

                    // j and k are the list's own keys; a menu item without ⌘
                    // would fire from inside text fields.
                    Button {
                        timeline?.move(1)
                    } label: {
                        Text("Next Post", comment: "Menu item")
                    }
                    .disabled(timeline == nil)
                    Button {
                        timeline?.move(-1)
                    } label: {
                        Text("Previous Post", comment: "Menu item")
                    }
                    .disabled(timeline == nil)
                }
            }

            /// Account: the window's account and the others to switch it to
            /// (⌃⌘1–9, in the order Settings lists them), Add and Sign Out.
            @CommandsBuilder
            private var accountCommands: some Commands {
                CommandMenu(Text("Account", comment: "Menu title")) {
                    ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                        accountButton(account, digit: ShellPlace.shortcutDigit(at: index))
                    }

                    if !accounts.isEmpty { Divider() }

                    Button {
                        if let shell {
                            shell.addAccount()
                        } else {
                            NotificationCenter.default.post(name: .alohaAddAccount, object: nil)
                        }
                    } label: {
                        Text("Add Account…", comment: "Menu item")
                    }

                    Button {
                        shell?.signOut()
                    } label: {
                        if let current = accounts.first(where: { $0.id == shell?.accountID }) {
                            Text("Sign Out \(current.name)…", comment: "Menu item")
                        } else {
                            Text("Sign Out…", comment: "Menu item")
                        }
                    }
                    .disabled(shell?.accountID == nil)
                }
            }

            private var accounts: [ShellCommands.AccountChoice] { shell?.accounts ?? [] }

            @ViewBuilder
            private func accountButton(
                _ account: ShellCommands.AccountChoice, digit: Character?
            ) -> some View {
                let toggle = Toggle(
                    isOn: Binding(
                        get: { shell?.accountID == account.id },
                        set: { isOn in if isOn { shell?.switchAccount(account.id) } })
                ) {
                    Text(verbatim: account.name)
                }
                if let digit {
                    toggle.keyboardShortcut(KeyEquivalent(digit), modifiers: [.command, .control])
                } else {
                    toggle
                }
            }
        #endif

        private func postAction(
            _ action: TimelineCommands.Action, key: KeyEquivalent, modifiers: EventModifiers,
            label: () -> Text
        ) -> some View {
            Button {
                timeline?.act(action)
            } label: {
                label()
            }
            .menuKey(key, modifiers: modifiers)
            .disabled(timeline?.hasFocusedPost != true)
        }

        /// The front window's places, or — with no window to ask, every one
        /// closed on the Mac — the ones every account has.
        private var places: [ShellPlace] {
            shell?.places
                ?? ShellPlace.sidebarOrder(
                    modes: [.home],
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
        /// A menu item's key. A key without a modifier is the iPad's way to
        /// reach a list that cannot take the focus (text input keeps priority
        /// over it, so typing a "j" into the composer is still a "j"); it is
        /// not bound on visionOS, whose windows have no menu bar to show it in.
        @ViewBuilder
        fileprivate func menuKey(_ key: KeyEquivalent, modifiers: EventModifiers) -> some View {
            if modifiers.isEmpty {
                singleKey(key)
            } else {
                keyboardShortcut(key, modifiers: modifiers)
            }
        }

        @ViewBuilder
        fileprivate func singleKey(_ key: KeyEquivalent) -> some View {
            #if os(iOS)
                keyboardShortcut(key, modifiers: [])
            #else
                self
            #endif
        }
    }
#endif
