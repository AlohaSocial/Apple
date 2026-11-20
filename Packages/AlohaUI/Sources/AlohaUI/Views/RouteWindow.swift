// SPDX-License-Identifier: MIT

import Foundation
import SwiftUI

/// Window identities the apps declare, so a menu item can ask for one.
public enum AlohaWindow {
    /// The main window: the whole app, opened by File > New Window.
    public static let main = "main"
    /// The Mac's Settings window (`SettingsWindowView`).
    public static let settings = "settings"
    /// The Mac's small timeline that floats over other apps.
    public static let mini = "mini"
}

#if os(macOS)
    /// What a Mac window for one destination shows: the route, and the
    /// account it belongs to. A post id is one server's id, so a thread
    /// restored at launch is looked up under the account it was opened from,
    /// not whichever one is active by then (`WindowAccount`).
    public struct RouteWindowRequest: Codable, Hashable, Sendable {
        public var route: Route
        public var accountID: UUID?

        public init(route: Route, accountID: UUID?) {
            self.route = route
            self.accountID = accountID
        }
    }
#endif

/// One destination in a window of its own — a thread or a profile kept open
/// beside the timeline, the way Mail opens a message.
///
/// It is the shell itself, not a bare screen: a thread opened elsewhere still
/// has to reply, share, report and show its media, and every one of those is
/// presented by the shell. On the Mac the shell shows the destination alone,
/// without a sidebar (`routeWindowShell`); elsewhere it opens with the route
/// pushed. Declared by the apps as `WindowGroup(for: Route.self)` — on the
/// Mac `WindowGroup(for: RouteWindowRequest.self)` — and both are `Codable`,
/// so the windows survive a relaunch (docs/01 §5).
public struct RouteWindow: View {
    private let route: Route?
    private let accountID: UUID?

    public init(route: Route?) {
        self.route = route
        self.accountID = nil
    }

    #if os(macOS)
        public init(request: RouteWindowRequest?) {
            self.route = request?.route
            self.accountID = request?.accountID
        }
    #endif

    public var body: some View {
        AppShell(initialRoute: route, accountID: accountID)
    }
}

/// "Open in New Window", wherever a destination can be opened.
///
/// Draws nothing where a platform has one window per app — iPhone — so a
/// menu can include it unconditionally.
public struct OpenInNewWindowButton: View {
    #if os(iOS) || os(macOS) || os(visionOS)
        @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
        @Environment(\.openWindow) private var openWindow
    #endif
    #if os(macOS)
        @Environment(\.windowAccountID) private var windowAccountID
    #endif

    private let route: Route

    public init(_ route: Route) {
        self.route = route
    }

    public var body: some View {
        #if os(iOS) || os(macOS) || os(visionOS)
            if supportsMultipleWindows {
                Button {
                    #if os(macOS)
                        openWindow(
                            value: RouteWindowRequest(route: route, accountID: windowAccountID))
                    #else
                        openWindow(value: route)
                    #endif
                } label: {
                    Label {
                        Text("Open in New Window", comment: "Menu item")
                    } icon: {
                        Image(systemName: "macwindow.badge.plus")
                    }
                }
            }
        #endif
    }
}

// MARK: - What the menu bar acts on

/// What the shell in the front window offers the menu bar.
///
/// A focused value rather than a notification: a notification reaches every
/// window, so with two windows open ⌘N opened two composers. The menu acts on
/// the window in front, and only on it.
public struct ShellCommands {
    public var compose: () -> Void
    public var open: (Route) -> Void
    public var back: () -> Void
    public var canGoBack: Bool
    /// Opens the Mac's "Go to…" field (`CommandPalette`).
    public var jump: () -> Void = {}
    /// The sidebar's places in its order, for ⌘1–⌘9 (`ShellPlace`).
    public var places: [ShellPlace] = []
    /// Puts the cursor in the toolbar's search field, or opens Search where
    /// the screen has no such field.
    public var search: () -> Void = {}
    /// File ▸ Open Link…: a post's or a profile's address, pasted.
    public var openLink: () -> Void = {}
    /// Help ▸ Keyboard Shortcuts.
    public var showShortcuts: () -> Void = {}
    /// The accounts signed in, in order, for the Account menu.
    public var accounts: [AccountChoice] = []
    /// The account this window shows (`WindowAccount`).
    public var accountID: UUID?
    /// Shows another account in this window.
    public var switchAccount: (UUID) -> Void = { _ in }
    public var addAccount: () -> Void = {}
    /// Asks before removing this window's account from the device.
    public var signOut: () -> Void = {}

    /// One row of the Account menu.
    public struct AccountChoice: Identifiable, Hashable {
        public var id: UUID
        public var name: String
        public var handle: String
    }
}

/// What the list of posts with the keyboard's focus offers the menu bar —
/// the same moves its single-key shortcuts make, acting on the selected post.
public struct TimelineCommands {
    public enum Action: Sendable {
        case favourite, boost, reply, open, bookmark, translate
        case copyLink, openInBrowser
        /// A look at the post over the list, Quick Look's ⌘Y.
        case peek
    }

    public var move: (Int) -> Void
    public var act: (Action) -> Void
    public var refresh: () -> Void
    /// Whether a post is selected, which the actions need.
    public var hasFocusedPost: Bool
    /// Whether the list has anything to refresh from.
    public var canRefresh = true
}

/// ⌘R for a list that is not a list of posts — Activities' cousins:
/// conversations, lists, follow requests — published by `alohaRefreshable`.
public struct RefreshCommand {
    public var refresh: () -> Void
}

extension FocusedValues {
    @Entry public var shellCommands: ShellCommands?
    /// From the list that has the keyboard focus. In the Deck, where three
    /// lists share a window, it is the one being read, not the last drawn.
    @Entry public var timelineCommands: TimelineCommands?
    /// The same, from any list on screen, for when the focus is elsewhere in
    /// the window — the sidebar, a toolbar field.
    @Entry public var sceneTimelineCommands: TimelineCommands?
    @Entry public var refreshCommand: RefreshCommand?
}

extension EnvironmentValues {
    /// Whether this shell is the Mac's mini timeline: the feed alone in a
    /// narrow window that floats, with the sidebar put away.
    @Entry public var alohaMiniWindow = false
    /// Whether the screen is the whole of a window opened for it, and so
    /// names the window after whose it is (`routeWindowShell`).
    @Entry var titlesWindowByAuthor = false
}
