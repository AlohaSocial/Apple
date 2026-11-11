// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

/// The four things a reader does with a post — like, repost, comment, save —
/// in the one order the whole app uses, each in a cell of the same width.
///
/// A timeline row, an opened post and a photo card used to arrange these
/// differently: one packed them to the leading edge, one spread them, one put
/// share in the middle and save at the far end. The same four controls moved
/// every time a post was opened. Drawn from one strip, the glyph, its number
/// and the tap target are in the same place wherever a post appears.
struct StatusActionStrip: View {
    @Environment(\.alohaPalette) private var palette

    let status: Status
    let showsCounts: Bool
    var prominence: StatusActionButton.Prominence = .row
    /// Whether Share follows Save. The opened post and a photo card carry it;
    /// a timeline row leaves sharing to its menu.
    var showsShare: Bool = false
    /// What tapping a number does — who liked, who reposted. `nil` leaves the
    /// number part of its button.
    var onShowInteractions: ((InteractionAccountsSheet.Kind) -> Void)?
    let onAction: (StatusRowAction) -> Void

    private var displayed: Status { status.displayed }

    var body: some View {
        HStack(spacing: 0) {
            StatusActionButton(
                symbol: displayed.favourited
                    ? AlohaSymbol.favouriteFilled : AlohaSymbol.favourite,
                count: showsCounts ? displayed.favouritesCount : nil,
                tint: palette.favourite, isOn: displayed.favourited, style: .pop,
                label: Text("Favourite", comment: "Status action"),
                prominence: prominence,
                onCountTap: interactions(.favourites, count: displayed.favouritesCount),
                countHint: Text(
                    "Shows who favourited this post", comment: "Hint for the favourites number"),
                contentAlignment: .center
            ) { onAction(.favourite(status)) }
            .frame(maxWidth: .infinity)

            StatusActionButton(
                symbol: AlohaSymbol.boost, count: showsCounts ? displayed.reblogsCount : nil,
                tint: palette.boost, isOn: displayed.reblogged, style: .spin,
                label: Text("Boost", comment: "Status action"),
                prominence: prominence,
                onCountTap: interactions(.boosts, count: displayed.reblogsCount),
                countHint: Text(
                    "Shows who boosted this post", comment: "Hint for the boosts number"),
                contentAlignment: .center
            ) { onAction(.boost(status)) }
            .frame(maxWidth: .infinity)

            StatusActionButton(
                symbol: AlohaSymbol.reply, count: showsCounts ? displayed.repliesCount : nil,
                tint: palette.secondaryLabel, isOn: false, style: .plain,
                label: Text("Reply", comment: "Status action"),
                prominence: prominence, contentAlignment: .center
            ) { onAction(.reply(status)) }
            .frame(maxWidth: .infinity)

            StatusActionButton(
                symbol: displayed.bookmarked ? AlohaSymbol.bookmarkFilled : AlohaSymbol.bookmark,
                count: nil, tint: palette.bookmark, isOn: displayed.bookmarked, style: .pop,
                label: Text("Bookmark", comment: "Status action"),
                prominence: prominence, contentAlignment: .center
            ) { onAction(.bookmark(status)) }
            .frame(maxWidth: .infinity)

            if showsShare {
                StatusShareLink(status: status) {
                    Image(systemName: AlohaSymbol.share)
                        .font(prominence == .row ? .footnote : .body)
                        .foregroundStyle(palette.secondaryLabel)
                        .frame(
                            minWidth: prominence == .row ? 24 : 44,
                            minHeight: prominence == .row ? 32 : 44
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text("Share post", comment: "Thread share action"))
            }
        }
    }

    /// The number opens the people behind it — only where the surface can
    /// show them and the reader asked for numbers at all.
    private func interactions(
        _ kind: InteractionAccountsSheet.Kind, count: Int
    ) -> (() -> Void)? {
        guard showsCounts, count > 0, let onShowInteractions else { return nil }
        return { onShowInteractions(kind) }
    }
}
