// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaStore
import SwiftUI

/// The gestures a post row answers besides a tap: a swipe from either edge,
/// a long press (or a secondary click) for its menu, and a drag that carries
/// its link out of the app.
///
/// Applied by the list that hosts the row rather than inside `StatusRow`,
/// because some hosts already give their rows a context menu of their own —
/// For you's "Less like this" — and the inner menu would silently replace it.
struct StatusRowInteractions: ViewModifier {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.alohaPalette) private var palette
    @Environment(\.alohaMetrics) private var metrics

    let status: Status
    let settings: AccountSettings
    let policy: SensitiveMediaPolicy
    let localHost: String?
    let onAction: (StatusRowAction) -> Void

    private var displayed: Status { status.displayed }

    func body(content: Content) -> some View {
        content
            #if !os(tvOS) && !os(watchOS)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    swipeButton(settings.leadingSwipeAction)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    swipeButton(settings.trailingSwipeAction)
                }
            #endif
            .contextMenu {
                StatusMenu(status: status, onAction: onAction)
            } preview: {
                preview
            }
            .modifier(StatusLinkDrag(url: displayed.url))
    }

    // MARK: - Swipes

    @ViewBuilder
    private func swipeButton(_ action: AccountSettings.SwipeAction) -> some View {
        switch action {
        case .none:
            EmptyView()
        case .reply:
            swipe(.reply(status), tint: palette.accent) {
                Label {
                    Text("Reply", comment: "Swipe action on a post")
                } icon: {
                    Image(systemName: AlohaSymbol.reply)
                }
            }
        case .favourite:
            swipe(.favourite(status), tint: palette.favourite) {
                Label {
                    if displayed.favourited {
                        Text("Unfavourite", comment: "Swipe action on a post")
                    } else {
                        Text("Favourite", comment: "Swipe action on a post")
                    }
                } icon: {
                    Image(
                        systemName: displayed.favourited
                            ? AlohaSymbol.favourite : AlohaSymbol.favouriteFilled)
                }
            }
        case .boost:
            swipe(.boost(status), tint: palette.boost) {
                Label {
                    if displayed.reblogged {
                        Text("Undo boost", comment: "Swipe action on a post")
                    } else {
                        Text("Boost", comment: "Swipe action on a post")
                    }
                } icon: {
                    Image(systemName: AlohaSymbol.boost)
                }
            }
        case .bookmark:
            swipe(.bookmark(status), tint: palette.bookmark) {
                Label {
                    if displayed.bookmarked {
                        Text("Remove bookmark", comment: "Swipe action on a post")
                    } else {
                        Text("Bookmark", comment: "Swipe action on a post")
                    }
                } icon: {
                    Image(
                        systemName: displayed.bookmarked
                            ? AlohaSymbol.bookmark : AlohaSymbol.bookmarkFilled)
                }
            }
        }
    }

    private func swipe(
        _ action: StatusRowAction, tint: Color, @ViewBuilder label: () -> some View
    ) -> some View {
        Button {
            // Somebody who has swiped once has learnt the gesture; the tip
            // that teaches it has nothing left to say.
            SwipeActionsTip().invalidate(reason: .actionPerformed)
            onAction(action)
        } label: {
            label()
        }
        .tint(tint)
    }

    // MARK: - Preview

    /// The post as the row draws it, without its action row: the menu below
    /// the preview carries the actions, and drawing them twice is noise.
    ///
    /// The preview is hosted outside the row, so the theme and the app
    /// environment are handed to it explicitly rather than trusted to arrive.
    private var preview: some View {
        StatusRow(
            status: status, policy: policy, localHost: localHost, showActions: false,
            showsCounts: settings.showPopularityCounts, onAction: { _ in }
        )
        .padding(.horizontal, AlohaMetrics.space4)
        .frame(width: 360)
        .background(palette.background)
        .environment(environment)
        .environment(\.alohaPalette, palette)
        .environment(\.alohaMetrics, metrics)
    }
}

/// A post drags out as its public link, which is what every other app
/// understands a post to be. A post with no URL — a draft-like local copy —
/// is not draggable rather than dragging nothing.
private struct StatusLinkDrag: ViewModifier {
    let url: URL?

    func body(content: Content) -> some View {
        #if os(tvOS) || os(watchOS)
            content
        #else
            if let url {
                content.draggable(url)
            } else {
                content
            }
        #endif
    }
}

extension View {
    func statusRowInteractions(
        _ status: Status, session: AccountSession, onAction: @escaping (StatusRowAction) -> Void
    ) -> some View {
        modifier(
            StatusRowInteractions(
                status: status, settings: session.settings,
                policy: session.settings.sensitiveMediaPolicy,
                localHost: session.snapshot.instanceHost, onAction: onAction))
    }
}
