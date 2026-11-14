// SPDX-License-Identifier: MIT

import AlohaNetwork
import AlohaUI
import AppKit
import SwiftUI

/// The way into the app from outside any window: the Dock menu, the
/// Services menu and the menu bar extra.
///
/// Each can be used with every window closed, where there is no shell to
/// post a notification to. SwiftUI's `openWindow` works without one, but it
/// is only handed to views; the first window or the menu bar extra to appear
/// leaves it here, and AppKit's callers use it from then on.
@MainActor
enum MacWindows {
    static var openWindow: OpenWindowAction?

    /// A new post in a compose window of its own (docs/09 §2).
    static func compose(draftText: String = "") {
        activate()
        if let openWindow {
            openWindow(value: ComposeWindowRequest(draftText: draftText))
        } else {
            // Before any view has appeared, which a service request at
            // launch can be: the main window's shell takes the request when
            // it starts, and opens the compose window itself.
            NotificationCenter.default.post(
                name: RouteResolver.composeRequested, object: nil,
                userInfo: ["draft": draftText])
        }
    }

    /// A destination in a main window — the one in front, or a new one when
    /// every window is closed.
    ///
    /// The route is left where a shell takes it (`IntentNavigation`): a
    /// running one at once, a new one as it becomes active. Still there
    /// after the announcement means no shell took it, so there is no window
    /// to show it in yet.
    static func open(_ route: Route) {
        activate()
        IntentNavigation.enqueue(route)
        if AppGroup.defaults.data(forKey: AppGroup.pendingRouteKey) != nil {
            openWindow?(id: AlohaWindow.main)
        }
    }

    /// Whatever asked, from the Dock or the menu bar, the app may be behind
    /// forty other windows: it comes forward first, so the result is seen.
    static func activate() {
        NSApplication.shared.activate()
    }
}

extension View {
    /// Leaves this scene's `openWindow` for AppKit's callers (`MacWindows`).
    func providesWindowOpener() -> some View {
        modifier(WindowOpenerProvider())
    }
}

private struct WindowOpenerProvider: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear { MacWindows.openWindow = openWindow }
    }
}
