// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

/// What the focused post of a thread says about itself beyond its row: the
/// exact time, what it was posted with, when it was last edited, and who
/// favourited and boosted it.
///
/// A timeline row says "2h"; the post being read is where the exact moment
/// and the people behind the counts are worth the room.
struct PostDetailFooter: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.openURL) private var openURL

    let status: Status
    let session: AccountSession
    let onOpenProfile: (Account) -> Void

    @State private var interactions: InteractionAccountsSheet.Kind?

    private var displayed: Status { status.displayed }
    private var showsCounts: Bool { session.settings.showPopularityCounts }

    var body: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            HStack(spacing: AlohaMetrics.space1) {
                Text(verbatim: PostAge.absolute(displayed.createdAt))
                if let application = displayed.application {
                    Text(verbatim: "·").accessibilityHidden(true)
                    applicationLabel(application)
                }
            }
            .font(.footnote)
            .foregroundStyle(palette.secondaryLabel)

            if let editedAt = displayed.editedAt {
                Text(
                    "Edited \(PostAge.absolute(editedAt))",
                    comment: "When the focused post was last edited"
                )
                .font(.footnote)
                .foregroundStyle(palette.tertiaryLabel)
            }

            HStack(spacing: AlohaMetrics.space4) {
                interactionButton(.favourites, count: displayed.favouritesCount)
                interactionButton(.boosts, count: displayed.reblogsCount)
                Spacer(minLength: 0)
            }
            .font(.footnote.weight(.medium))
        }
        .padding(.vertical, AlohaMetrics.space2)
        .sheet(item: $interactions) { kind in
            InteractionAccountsSheet(
                statusID: displayed.id, session: session, onOpenProfile: onOpenProfile,
                kind: kind)
        }
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

    /// With "Show numbers" off the link stays, without the crowd's size.
    private func interactionButton(
        _ kind: InteractionAccountsSheet.Kind, count: Int
    ) -> some View {
        Button {
            interactions = kind
        } label: {
            switch (kind, showsCounts) {
            case (.favourites, true):
                Text("\(count) favourites", comment: "Opens who favourited the focused post")
            case (.boosts, true):
                Text("\(count) boosts", comment: "Opens who boosted the focused post")
            case (.favourites, false):
                Text("Favourited by", comment: "Title of the list of who favourited")
            case (.boosts, false):
                Text("Boosted by", comment: "Title of the list of who boosted")
            }
        }
        // The text is footnote-sized; the target is not.
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .buttonStyle(.borderless)
        .foregroundStyle(palette.accent)
    }
}
