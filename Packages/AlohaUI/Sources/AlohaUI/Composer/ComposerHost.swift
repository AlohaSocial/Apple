// SPDX-License-Identifier: MIT

import SwiftUI

/// How a composer ended: the host decides what that means for it.
public enum ComposerOutcome: Sendable, Equatable {
    case posted
    case cancelled
}

/// A composer hosted outside a SwiftUI presentation — the share extensions,
/// which put it at the root of a hosting controller.
///
/// There `dismiss` has nothing to dismiss, so a composer that only called it
/// would never let the extension finish its request; and on macOS the
/// window's toolbar belongs to the system's share sheet, so Cancel and Post
/// have to be drawn by the composer itself.
public struct ComposerHost {
    /// Cancel and Post as a row under the composer instead of toolbar items.
    public var showsInlineActions: Bool
    /// Called instead of `dismiss` when the composer is done.
    public var finish: @MainActor (ComposerOutcome) -> Void

    public init(
        showsInlineActions: Bool, finish: @escaping @MainActor (ComposerOutcome) -> Void
    ) {
        self.showsInlineActions = showsInlineActions
        self.finish = finish
    }
}

extension EnvironmentValues {
    @Entry var composerHost: ComposerHost?
}

extension View {
    /// Hosts a composer outside a sheet: `finish` replaces `dismiss`, and
    /// `showsInlineActions` draws Cancel and Post inside the composer.
    public func composerHost(
        showsInlineActions: Bool = false,
        finish: @escaping @MainActor (ComposerOutcome) -> Void
    ) -> some View {
        environment(
            \.composerHost,
            ComposerHost(showsInlineActions: showsInlineActions, finish: finish))
    }
}
