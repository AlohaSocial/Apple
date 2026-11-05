// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

/// The chrome under the post being read: what it can do, how far it got, and
/// when it was written.
///
/// X, Threads and Instagram all settle on the same three layers under an opened
/// post — one row of actions, one line of numbers, one line of provenance — and
/// none of them put material between them. This screen used to: two glass pills
/// reading "12 favourites" and "40 boosts" sat under a navigation bar that is
/// already glass, repeating numbers the action row had just shown, in a card
/// with an accent rail drawn down its edge. Glass on glass, and the same fact
/// said twice.
///
/// So the pills are gone. The numbers stayed, as the single line that says how
/// far a post travelled, and the actions are the plain icons a reader already
/// knows from the timeline, spread across the width the opened post gives them.
/// Tapping a number still opens the people behind it; that is a text row, not a
/// control competing with the toolbar.
struct PostDetailFooter: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.openURL) private var openURL

    let status: Status
    let session: AccountSession
    let onAction: (StatusRowAction) -> Void
    let onOpenProfile: (Account) -> Void

    @State private var interactions: InteractionAccountsSheet.Kind?

    private var displayed: Status { status.displayed }
    private var showsCounts: Bool { session.settings.showPopularityCounts }
    private var isOwn: Bool {
        displayed.account.id == session.snapshot.serverAccountID
    }

    var body: some View {
        // The gaps are written out rather than shared: the rule sits halfway
        // between the moment and the actions, and the numbers hang directly
        // under the actions they belong to. A single `spacing` made the numbers
        // look like a caption for the replies below, twenty points away from
        // the row that produced them.
        VStack(alignment: .leading, spacing: 0) {
            provenance
            Rectangle()
                .fill(palette.separator)
                .frame(height: 0.5)
                .padding(.top, AlohaMetrics.space2)
                .padding(.bottom, AlohaMetrics.space2)
            actions
            statistics
                .padding(.top, AlohaMetrics.space1)
        }
        .padding(.top, AlohaMetrics.space2)
        .padding(.bottom, -AlohaMetrics.space2)
        .sheet(item: $interactions) { kind in
            InteractionAccountsSheet(
                statusID: displayed.id, session: session, onOpenProfile: onOpenProfile,
                kind: kind)
        }
    }

    // MARK: - Actions

    /// The five things a reader does with an opened post, spread evenly. The
    /// same controls as a timeline row, at the size of a tap target rather than
    /// the size of a footnote, and without their counts: the numbers are the
    /// line below, said once.
    private var actions: some View {
        HStack(spacing: 0) {
            StatusActionButton(
                symbol: AlohaSymbol.reply, count: nil, tint: palette.secondaryLabel,
                isOn: false, style: .plain, label: Text("Reply", comment: "Status action"),
                prominence: .detail
            ) { onAction(.reply(status)) }

            StatusActionButton(
                symbol: AlohaSymbol.boost, count: nil, tint: palette.boost,
                isOn: displayed.reblogged, style: .spin,
                label: Text("Boost", comment: "Status action"), prominence: .detail
            ) { onAction(.boost(status)) }

            StatusActionButton(
                symbol: displayed.favourited ? AlohaSymbol.favouriteFilled : AlohaSymbol.favourite,
                count: nil, tint: palette.favourite, isOn: displayed.favourited, style: .pop,
                label: Text("Favourite", comment: "Status action"), prominence: .detail
            ) { onAction(.favourite(status)) }

            StatusActionButton(
                symbol: displayed.bookmarked ? AlohaSymbol.bookmarkFilled : AlohaSymbol.bookmark,
                count: nil, tint: palette.bookmark, isOn: displayed.bookmarked, style: .pop,
                label: Text("Bookmark", comment: "Status action"), prominence: .detail
            ) { onAction(.bookmark(status)) }

            StatusShareLink(status: status) {
                Image(systemName: AlohaSymbol.share)
                    .font(.body)
                    .foregroundStyle(palette.secondaryLabel)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Share post", comment: "Thread share action"))
        }
    }

    // MARK: - Numbers

    /// One line, the way Threads and X say it: replies, then the people who
    /// passed the post on, then the people who kept it, separated by dots.
    /// Only what is not zero, so a quiet post stays quiet.
    ///
    /// A row, not a wrapping flow: a wrapped flow put "1 reply" on a line of
    /// its own, hanging to the left of "1 favourite · 1 boost" underneath it,
    /// which read as three unrelated facts. At the accessibility text sizes
    /// the row is wider than a phone, so `ViewThatFits` swaps in a column of
    /// the same numbers, all against the same edge — one line, or one number
    /// per line, never a fragment of a sentence.
    @ViewBuilder
    private var statistics: some View {
        if showsCounts, hasStatistics {
            ViewThatFits(in: .horizontal) {
                statisticsRow
                statisticsColumn
            }
            .font(.subheadline)
            .foregroundStyle(palette.secondaryLabel)
        }
    }

    private var statisticsRow: some View {
        HStack(spacing: AlohaMetrics.space2) {
            replyCount
            if displayed.favouritesCount > 0 {
                separator
                favouriteCount
            }
            if displayed.reblogsCount > 0 {
                separator
                boostCount
            }
            if let quotes = displayed.quotesCount, quotes > 0 {
                separator
                quoteCount(quotes)
            }
            if isOwn, let views = displayed.viewCount, views > 0 {
                separator
                viewCount(views)
            }
        }
    }

    /// The same numbers when they no longer fit side by side, one per line and
    /// all against the leading edge, so nothing looks indented by accident.
    private var statisticsColumn: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
            replyCount
            if displayed.favouritesCount > 0 { favouriteCount }
            if displayed.reblogsCount > 0 { boostCount }
            if let quotes = displayed.quotesCount, quotes > 0 { quoteCount(quotes) }
            if isOwn, let views = displayed.viewCount, views > 0 { viewCount(views) }
        }
    }

    /// A dot rather than a gap: at a glance the numbers are one sentence, and
    /// separated they stay legible as separate counts.
    private var separator: some View {
        Text(verbatim: "·")
            .foregroundStyle(palette.tertiaryLabel)
            .accessibilityHidden(true)
    }

    private var hasStatistics: Bool {
        displayed.repliesCount > 0 || displayed.favouritesCount > 0
            || displayed.reblogsCount > 0 || (displayed.quotesCount ?? 0) > 0
            || (isOwn && (displayed.viewCount ?? 0) > 0)
    }

    /// A number nobody can open stays a number.
    private var replyCount: some View {
        replyCountText(displayed.repliesCount)
            .frame(minHeight: 44)
    }

    private func quoteCount(_ count: Int) -> some View {
        NavigationLink(value: Route.quotes(statusID: displayed.id)) {
            quoteCountText(count)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.secondaryLabel)
        .accessibilityHint(
            Text("Shows the posts quoting this one", comment: "Hint for the quotes number"))
    }

    private func viewCount(_ count: Int) -> some View {
        viewCountText(count)
            .frame(minHeight: 44)
    }

    /// The people who kept the post. A text button rather than a pill: the line
    /// already reads as one sentence, and a button that looks like a sentence is
    /// what the rest of the line is.
    private var favouriteCount: some View {
        Button {
            interactions = .favourites
        } label: {
            favouriteCountText(displayed.favouritesCount)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(
            Text("Shows who favourited this post", comment: "Hint for the favourites number"))
    }

    private var boostCount: some View {
        Button {
            interactions = .boosts
        } label: {
            boostCountText(displayed.reblogsCount)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(
            Text("Shows who boosted this post", comment: "Hint for the boosts number"))
    }

    private func replyCountText(_ count: Int) -> Text {
        if count == 1 {
            return Text("**1** reply", comment: "Number of replies on an opened post")
        }
        return Text("**\(count)** replies", comment: "Number of replies on an opened post")
    }

    private func favouriteCountText(_ count: Int) -> Text {
        if count == 1 {
            return Text("**1** favourite", comment: "Number of favourites on an opened post")
        }
        return Text("**\(count)** favourites", comment: "Number of favourites on an opened post")
    }

    private func boostCountText(_ count: Int) -> Text {
        if count == 1 {
            return Text("**1** boost", comment: "Number of boosts on an opened post")
        }
        return Text("**\(count)** boosts", comment: "Number of boosts on an opened post")
    }

    private func quoteCountText(_ count: Int) -> Text {
        if count == 1 {
            return Text("**1** quote", comment: "Number of quotes on an opened post")
        }
        return Text("**\(count)** quotes", comment: "Number of quotes on an opened post")
    }

    private func viewCountText(_ count: Int) -> Text {
        if count == 1 {
            return Text("**1** view", comment: "Number of views on your own post")
        }
        return Text("**\(count)** views", comment: "Number of views on your own post")
    }

    // MARK: - Provenance

    /// The exact moment, the app it came from, and any later edit — the three
    /// things a timeline row has no room for and an opened post is the place
    /// for.
    /// Flows for the same reason the numbers do: a long app name next to an
    /// exact moment is wider than a narrow phone in a large text size.
    private var provenance: some View {
        FlowLayout(spacing: AlohaMetrics.space2) {
            Text(verbatim: PostAge.absolute(displayed.createdAt))

            if let application = displayed.application {
                applicationLabel(application)
            }

            if let editedAt = displayed.editedAt {
                Text(
                    "Edited \(PostAge.absolute(editedAt))",
                    comment: "When the focused post was last edited")
            }
        }
        .font(.footnote)
        .foregroundStyle(palette.tertiaryLabel)
    }

    @ViewBuilder
    private func applicationLabel(_ application: Status.ApplicationSummary) -> some View {
        if let website = application.website {
            Button {
                openURL(website)
            } label: {
                Text("via \(application.name)", comment: "The app a post was written with")
            }
            .buttonStyle(.borderless)
        } else {
            Text("via \(application.name)", comment: "The app a post was written with")
        }
    }
}
