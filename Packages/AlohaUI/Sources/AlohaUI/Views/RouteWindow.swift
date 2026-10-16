// SPDX-License-Identifier: MIT

import SwiftUI

/// Window identities the apps declare, so a menu item can ask for one.
public enum AlohaWindow {
    /// The main window: the whole app, opened by File > New Window.
    public static let main = "main"
}

/// One destination in a window of its own — a thread or a profile kept open
/// beside the timeline, the way Mail opens a message.
///
/// It is the shell itself with the route already pushed, not a bare screen:
/// a thread opened elsewhere still has to reply, share, report and show its
/// media, and every one of those is presented by the shell. Declared by the
/// apps as `WindowGroup(for: Route.self)`; `Route` is `Codable`, so the
/// windows survive a relaunch (docs/01 §5).
public struct RouteWindow: View {
    private let route: Route?

    public init(route: Route?) {
        self.route = route
    }

    public var body: some View {
        AppShell(initialRoute: route)
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

    private let route: Route

    public init(_ route: Route) {
        self.route = route
    }

    public var body: some View {
        #if os(iOS) || os(macOS) || os(visionOS)
            if supportsMultipleWindows {
                Button {
                    openWindow(value: route)
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
    /// The sidebar's places in its order, for ⌘1–⌘9 (`ShellPlace`).
    public var places: [ShellPlace] = []
}

/// What the timeline in the front window offers the menu bar — the same
/// moves its single-key shortcuts make.
public struct TimelineCommands {
    public enum Action: Sendable {
        case favourite, boost, reply, open
    }

    public var move: (Int) -> Void
    public var act: (Action) -> Void
    public var refresh: () -> Void
    /// Whether a post has the keyboard's focus ring, which the four actions
    /// need.
    public var hasFocusedPost: Bool
}

extension FocusedValues {
    @Entry public var shellCommands: ShellCommands?
    @Entry public var timelineCommands: TimelineCommands?
}
