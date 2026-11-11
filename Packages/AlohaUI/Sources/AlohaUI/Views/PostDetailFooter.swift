// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

/// The chrome under the post being read: what it can do, how far it got, and
/// when it was written.
///
/// X, Threads and Instagram all settle on the same two layers under an opened
/// post — one row of actions, one line of provenance. This screen used to
/// spend a third layer on the numbers: a row of actions without counts, then
/// "**12** replies · **40** boosts · **128** favourites" underneath it. The
/// numbers were a field of their own, twenty points away from the controls
/// they described, and a reader had to look in two places to see one thing.
///
/// The counts live beside their glyphs now, in the same strip every other
/// surface draws. Tapping the glyph acts on the post; tapping the number opens
/// the people behind it — who favourited, who boosted — which is what the
/// number was always asking to do.
///
/// The numbers nobody can change from here — quotes, views on your own post,
/// a federated video's dislikes — sit on the provenance line with the moment
/// and the app: they describe the post, rather than being something to do
/// with it.
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
        VStack(alignment: .leading, spacing: 0) {
            provenance
            Rectangle()
                .fill(palette.separator)
                .frame(height: 0.5)
                .padding(.top, AlohaMetrics.space2)
                .padding(.bottom, AlohaMetrics.space1)
            actions
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

    /// Like, repost, comment, save and share, spread evenly, each with its own
    /// count beside it — the same strip a timeline row and a photo card draw.
    private var actions: some View {
        StatusActionStrip(
            status: status, showsCounts: showsCounts, prominence: .detail,
            showsShare: true, onShowInteractions: { interactions = $0 },
            onAction: { onAction($0) })
    }

    // MARK: - Provenance

    /// The exact moment, the app it came from, any later edit, and the reach
    /// nobody can act on from here — with the post's own menu at the end,
    /// where an opened post keeps translate, report, edit and delete.
    /// Flows for the same reason the numbers used to: a long app name next to
    /// an exact moment is wider than a narrow phone in a large text size.
    private var provenance: some View {
        HStack(alignment: .top, spacing: AlohaMetrics.space2) {
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

                if showsCounts {
                    if let quotes = displayed.quotesCount, quotes > 0 {
                        quoteCount(quotes)
                    }
                    if showsDislikes {
                        dislikeCount(displayed.dislikesCount)
                    }
                    if isOwn, let views = displayed.viewCount, views > 0 {
                        viewCount(views)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            moreMenu
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

    /// The posts quoting this one are a list worth opening, so the count is a
    /// link rather than a number.
    private func quoteCount(_ count: Int) -> some View {
        NavigationLink(value: Route.quotes(statusID: displayed.id)) {
            statisticLabel(
                "quote.bubble",
                text: Text(
                    "^[\(count) quote](inflect: true)",
                    comment: "Quote count on an opened post"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.tertiaryLabel)
        .accessibilityHint(
            Text("Shows the posts quoting this one", comment: "Hint for the quotes number"))
    }

    /// A federated video's thumbs-down, which nothing can cast from here.
    private var showsDislikes: Bool {
        displayed.mediaAttachments.contains(where: { $0.type.isPlayable })
            && displayed.dislikesCount > 0
    }

    private func dislikeCount(_ count: Int) -> some View {
        statisticLabel(
            "hand.thumbsdown",
            text: Text(
                "^[\(count) dislike](inflect: true) elsewhere",
                comment: "Read-only dislike count on a federated video"))
    }

    /// Who read it: only the author's own posts carry a value.
    private func viewCount(_ count: Int) -> some View {
        statisticLabel(
            "eye",
            text: Text(
                "^[\(count) view](inflect: true)",
                comment: "View count on your own post"))
    }

    private func statisticLabel(_ symbol: String, text: Text) -> some View {
        Label {
            text
        } icon: {
            Image(systemName: symbol)
        }
    }

    // MARK: - Menu

    /// The overflow menu every other surface gives a post. The opened post is
    /// where a reader decides to translate, report or delete one, and it used
    /// to be the one place with no way to ask.
    private var moreMenu: some View {
        Menu {
            StatusMenu(status: status, onAction: onAction)
        } label: {
            Image(systemName: AlohaSymbol.more)
                .font(.footnote)
                .foregroundStyle(palette.secondaryLabel)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel(Text("More actions", comment: "Status action"))
        .accessibilityInputLabels([
            Text("More actions", comment: "Status action"),
            Text("More", comment: "Voice Control name for the post's More actions menu"),
        ])
    }
}
