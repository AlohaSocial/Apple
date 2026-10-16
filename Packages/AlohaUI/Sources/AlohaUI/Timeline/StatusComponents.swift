// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaMedia
import AlohaModels
import SwiftUI

public struct PollView: View {
    @Environment(\.alohaPalette) private var palette

    private let poll: Poll
    private let onVote: ([Int]) -> Void
    @State private var selection: Set<Int> = []

    public init(poll: Poll, onVote: @escaping ([Int]) -> Void) {
        self.poll = poll
        self.onVote = onVote
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            ForEach(Array(poll.options.enumerated()), id: \.offset) { index, option in
                optionRow(option, index: index)
            }

            HStack(spacing: AlohaMetrics.space2) {
                Text(
                    "^[\(poll.participantCount) vote](inflect: true)",
                    comment: "Poll participation count")
                if let expiresAt = poll.expiresAt {
                    Text(verbatim: "·")
                    if poll.expired {
                        Text("Closed", comment: "Poll state")
                    } else {
                        Text(expiresAt, format: .relative(presentation: .named))
                    }
                }
                Spacer()
                if !poll.expired && !poll.voted && !selection.isEmpty {
                    Button {
                        onVote(Array(selection).sorted())
                    } label: {
                        Text("Vote", comment: "Poll action")
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
            .font(.caption)
            .foregroundStyle(palette.secondaryLabel)
        }
        .padding(AlohaMetrics.space3)
        .background(
            palette.surfaceRaised,
            in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous))
    }

    private func optionRow(_ option: Poll.Option, index: Int) -> some View {
        let share = poll.share(ofOptionAt: index)
        let isChosen = poll.ownVotes.contains(index)

        return Button {
            guard !poll.expired, !poll.voted else { return }
            if poll.multiple {
                if selection.contains(index) {
                    selection.remove(index)
                } else {
                    selection.insert(index)
                }
            } else {
                selection = [index]
            }
        } label: {
            ZStack(alignment: .leading) {
                // Results appear only once the poll is closed or the reader has
                // voted; before that, showing them tells people how to vote.
                if poll.showsResults {
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous)
                            .fill(palette.accentMuted.opacity(0.35))
                            .frame(width: max(0, proxy.size.width * share))
                    }
                }

                HStack(spacing: AlohaMetrics.space2) {
                    if !poll.showsResults {
                        Image(
                            systemName: selection.contains(index)
                                ? (poll.multiple
                                    ? "checkmark.square.fill" : "largecircle.fill.circle")
                                : (poll.multiple ? "square" : "circle")
                        )
                        .foregroundStyle(palette.accent)
                    } else if isChosen {
                        Image(systemName: "checkmark")
                            .foregroundStyle(palette.accent)
                    }

                    Text(option.title)
                        .font(.subheadline)
                        .foregroundStyle(palette.label)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: AlohaMetrics.space2)

                    if poll.showsResults {
                        Text(share, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(palette.secondaryLabel)
                    }
                }
                .padding(.horizontal, AlohaMetrics.space2)
                .padding(.vertical, AlohaMetrics.space2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(poll.showsResults ? [] : .isButton)
    }
}

public struct LinkCardView: View {
    @Environment(\.alohaPalette) private var palette

    /// A wash of the preview image's own colour, so a card belongs to the page
    /// it links to rather than being one more grey box.
    private var cardTint: AnyShapeStyle {
        guard let hash = card.blurhash, let average = BlurHash.averageColour(hash) else {
            return AnyShapeStyle(palette.surfaceRaised)
        }
        let colour = Color(red: average.red, green: average.green, blue: average.blue)
        return AnyShapeStyle(
            palette.surfaceRaised.mix(with: colour, by: 0.14))
    }

    private let card: Card
    private let onOpen: () -> Void

    public init(card: Card, onOpen: @escaping () -> Void) {
        self.card = card
        self.onOpen = onOpen
    }

    public var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                if card.image != nil {
                    RemoteImage(url: card.image, blurhash: card.blurhash)
                        .aspectRatio(1.91, contentMode: .fit)
                }
                VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
                    if !card.displayProvider.isEmpty {
                        Text(card.displayProvider)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(palette.secondaryLabel)
                    }
                    Text(card.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.label)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !card.description.isEmpty {
                        Text(card.description)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryLabel)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AlohaMetrics.space3)
            }
            .background(
                cardTint,
                in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous))
        }
        .buttonStyle(.plain)
        .modifier(CardLinkDrag(url: card.url))
    }
}

/// A link card drags out as the page it links to.
private struct CardLinkDrag: ViewModifier {
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

/// Emoji reactions — Nextcloud Social, Misskey and Pleroma have these;
/// Mastodon itself does not, so the row only appears where detected.
public struct ReactionRow: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let reactions: [Status.Reaction]
    private let canAdd: Bool
    private let onToggle: (String, Bool) -> Void

    /// Nextcloud Social has emoji reactions and Mastodon does not, so the add
    /// button appears only where the server will accept one.
    public init(
        reactions: [Status.Reaction], canAdd: Bool = false,
        onToggle: @escaping (String, Bool) -> Void
    ) {
        self.reactions = reactions
        self.canAdd = canAdd
        self.onToggle = onToggle
    }

    public var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AlohaMetrics.space2) {
                ForEach(reactions, id: \.name) { reaction in
                    ReactionChip(reaction: reaction) {
                        onToggle(reaction.name, reaction.me)
                    }
                }
                if canAdd { addButton }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var addButton: some View {
        Menu {
            ForEach(Self.quickReactions, id: \.self) { emoji in
                Button {
                    onToggle(emoji, false)
                } label: {
                    Text(verbatim: emoji)
                }
            }
        } label: {
            Image(systemName: "face.smiling")
                .font(.footnote)
                .foregroundStyle(palette.secondaryLabel)
                .padding(.horizontal, AlohaMetrics.space2)
                .padding(.vertical, AlohaMetrics.space1 + 1)
                .background(palette.surfaceRaised, in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel(Text("Add a reaction", comment: "Reactions action"))
    }

    /// The set people actually reach for, in the order they reach for it.
    static let quickReactions = ["👍", "🎉", "❤️", "😂", "🤔", "👀", "🙏", "🔥"]
}

/// One reaction, which pops when it becomes yours.
private struct ReactionChip: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let reaction: Status.Reaction
    let onToggle: () -> Void

    @State private var isPopping = false

    var body: some View {
        Button {
            onToggle()
            guard !reduceMotion, !reaction.me else { return }
            withAnimation(.spring(response: 0.26, dampingFraction: 0.45)) { isPopping = true }
            Task {
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isPopping = false }
            }
        } label: {
            HStack(spacing: AlohaMetrics.space1) {
                Text(reaction.name)
                Text(reaction.count, format: .number)
                    .font(.caption.monospacedDigit())
                    .fontDesign(.rounded)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, AlohaMetrics.space2)
            .padding(.vertical, AlohaMetrics.space1)
            .background(
                reaction.me ? palette.accentMuted.opacity(0.3) : palette.surfaceRaised,
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(reaction.me ? palette.accent : .clear, lineWidth: 1)
            )
            .scaleEffect(isPopping ? 1.22 : 1)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: reaction.me)
        .accessibilityLabel(
            Text(
                "\(reaction.name), \(reaction.count)",
                comment: "Accessibility label for an emoji reaction")
        )
        .accessibilityAddTraits(reaction.me ? [.isButton, .isSelected] : .isButton)
    }
}

/// The overflow menu on every post.
///
/// Reads the active session from the environment rather than taking it: the
/// menu sits in eight places, and what it may offer — quote, album, archive,
/// delivery — depends on the server and on whose post this is, not on the
/// screen that shows it.
public struct StatusMenu: View {
    @Environment(AppEnvironment.self) private var environment

    private let status: Status
    private let onAction: (StatusRowAction) -> Void

    public init(status: Status, onAction: @escaping (StatusRowAction) -> Void) {
        self.status = status
        self.onAction = onAction
    }

    private var displayed: Status { status.displayed }
    private var session: AccountSession? { environment.activeSession }
    private var isOwn: Bool {
        session.map { displayed.account.id == $0.snapshot.serverAccountID } ?? false
    }
    private var isNextcloud: Bool { session?.capabilities.isNextcloudSocial ?? false }
    private var hasImages: Bool {
        displayed.mediaAttachments.contains { $0.type == .image }
    }

    public var body: some View {
        // The four actions under every post, first and in one row. A swipe
        // can perform each of them, and nothing a gesture does may exist
        // only as a gesture (docs/12 §3, Switch Control); a long press opens
        // this menu too, where these are what people reach for.
        ControlGroup {
            Button {
                onAction(.reply(status))
            } label: {
                Label {
                    Text("Reply", comment: "Status menu item")
                } icon: {
                    Image(systemName: AlohaSymbol.reply)
                }
            }
            Button {
                onAction(.boost(status))
            } label: {
                Label {
                    if displayed.reblogged {
                        Text("Undo boost", comment: "Status menu item")
                    } else {
                        Text("Boost", comment: "Status menu item")
                    }
                } icon: {
                    Image(systemName: AlohaSymbol.boost)
                }
            }
            Button {
                onAction(.favourite(status))
            } label: {
                Label {
                    if displayed.favourited {
                        Text("Unfavourite", comment: "Status menu item")
                    } else {
                        Text("Favourite", comment: "Status menu item")
                    }
                } icon: {
                    Image(
                        systemName: displayed.favourited
                            ? AlohaSymbol.favouriteFilled : AlohaSymbol.favourite)
                }
            }
            Button {
                onAction(.bookmark(status))
            } label: {
                Label {
                    if displayed.bookmarked {
                        Text("Remove bookmark", comment: "Status menu item")
                    } else {
                        Text("Bookmark", comment: "Status menu item")
                    }
                } icon: {
                    Image(
                        systemName: displayed.bookmarked
                            ? AlohaSymbol.bookmarkFilled : AlohaSymbol.bookmark)
                }
            }
        }

        OpenInNewWindowButton(.thread(statusID: displayed.id))

        StatusShareLink(status: status) {
            Label {
                Text("Share", comment: "Status menu item")
            } icon: {
                Image(systemName: AlohaSymbol.share)
            }
        }

        if session?.capabilities.quotePosts == true, displayed.visibility != .direct {
            Button {
                onAction(.quote(status))
            } label: {
                Label {
                    Text("Quote", comment: "Status menu item")
                } icon: {
                    Image(systemName: "text.quote")
                }
            }
            NavigationLink(value: Route.quotes(statusID: displayed.id)) {
                Label {
                    Text("Posts quoting this", comment: "Status menu item")
                } icon: {
                    Image(systemName: "quote.bubble")
                }
            }
        }

        Button {
            onAction(.translate(status))
        } label: {
            Label {
                Text("Translate", comment: "Status menu item")
            } icon: {
                Image(systemName: AlohaSymbol.translate)
            }
        }

        if displayed.isEdited {
            Button {
                onAction(.showEditHistory(status))
            } label: {
                Label {
                    Text("Edit history", comment: "Status menu item")
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
        }

        if session?.capabilities.collections == true, displayed.hasMedia {
            Button {
                onAction(.addToCollection(status))
            } label: {
                Label {
                    Text("Add to album", comment: "Status menu item")
                } icon: {
                    Image(systemName: "rectangle.stack.badge.plus")
                }
            }
        }

        if !isOwn {
            Button {
                onAction(.addToList(displayed.account))
            } label: {
                Label {
                    Text("Add to list", comment: "Status menu item")
                } icon: {
                    Image(systemName: AlohaSymbol.list)
                }
            }
        }

        Button {
            onAction(.muteConversation(status))
        } label: {
            Label {
                Text(
                    status.displayed.muted
                        ? "Unmute conversation"
                        : "Mute conversation",
                    comment: "Status menu item")
            } icon: {
                Image(systemName: AlohaSymbol.mute)
            }
        }

        if isOwn { ownSection }

        // The thread's author can put a reply away (`can_hide`), and bring it
        // back: hidden is collapsed for everybody, never deleted.
        if displayed.canHide == true {
            Button {
                onAction(.hideReply(status))
            } label: {
                Label {
                    if displayed.isHiddenByAuthor {
                        Text("Show reply again", comment: "Status menu item")
                    } else {
                        Text("Hide reply", comment: "Status menu item")
                    }
                } icon: {
                    Image(systemName: displayed.isHiddenByAuthor ? "eye" : "eye.slash")
                }
            }
        }

        Divider()

        // Report, block and mute are never more than two taps away, on every
        // status and every profile (docs/11 §1.2).
        Button(role: .destructive) {
            onAction(.report(status))
        } label: {
            Label {
                Text("Report post", comment: "Status menu item")
            } icon: {
                Image(systemName: AlohaSymbol.report)
            }
        }

        if !isOwn {
            Button(role: .destructive) {
                onAction(.block(status.displayed.account))
            } label: {
                Label {
                    Text(
                        "Block \(status.displayed.account.bestDisplayName)",
                        comment: "Status menu item")
                } icon: {
                    Image(systemName: AlohaSymbol.block)
                }
            }

            Button(role: .destructive) {
                onAction(.mute(status.displayed.account))
            } label: {
                Label {
                    Text(
                        "Mute \(status.displayed.account.bestDisplayName)",
                        comment: "Status menu item")
                } icon: {
                    Image(systemName: AlohaSymbol.mute)
                }
            }
        }
    }

    /// Everything only the author can do, in one group.
    @ViewBuilder
    private var ownSection: some View {
        Divider()

        Button {
            onAction(.pin(status))
        } label: {
            Label {
                if displayed.pinned {
                    Text("Unpin from profile", comment: "Status menu item")
                } else {
                    Text("Pin to profile", comment: "Status menu item")
                }
            } icon: {
                Image(systemName: displayed.pinned ? "pin.slash" : AlohaSymbol.pin)
            }
        }

        Button {
            onAction(.edit(status))
        } label: {
            Label {
                Text("Edit", comment: "Status menu item")
            } icon: {
                Image(systemName: AlohaSymbol.edit)
            }
        }

        if isNextcloud {
            Button {
                onAction(.archive(status))
            } label: {
                Label {
                    if displayed.archived == true {
                        Text("Unarchive", comment: "Status menu item")
                    } else {
                        Text("Archive", comment: "Status menu item")
                    }
                } icon: {
                    Image(systemName: "archivebox")
                }
            }

            Button {
                onAction(.showDelivery(status))
            } label: {
                Label {
                    Text("Delivery", comment: "Status menu item")
                } icon: {
                    Image(systemName: "paperplane")
                }
            }

            if hasImages {
                Button {
                    onAction(.tagPeople(status))
                } label: {
                    Label {
                        Text("Tag people", comment: "Status menu item")
                    } icon: {
                        Image(systemName: "person.crop.rectangle")
                    }
                }
            }
        }

        if session?.capabilities.quotePosts == true {
            Button {
                onAction(.quoteControls(status))
            } label: {
                Label {
                    Text("Who may quote this", comment: "Status menu item")
                } icon: {
                    Image(systemName: "quote.closing")
                }
            }
        }

        // Aloha Social's own `reply_policy`, only on its own posts — which is
        // where the server answers with one.
        if isNextcloud, displayed.replyPolicy != nil {
            Menu {
                ForEach(ReplyPolicy.allCases, id: \.self) { policy in
                    Button {
                        onAction(.setReplyPolicy(status, policy))
                    } label: {
                        if displayed.replyAudience == policy {
                            Label {
                                ReplyPolicyLabel(policy: policy)
                            } icon: {
                                Image(systemName: "checkmark")
                            }
                        } else {
                            ReplyPolicyLabel(policy: policy)
                        }
                    }
                }
            } label: {
                Label {
                    Text("Who can reply", comment: "Status menu item")
                } icon: {
                    Image(systemName: "arrowshape.turn.up.left.2")
                }
            }
        }

        Button {
            onAction(.redraft(status))
        } label: {
            Label {
                Text("Delete & redraft", comment: "Status menu item")
            } icon: {
                Image(systemName: "arrow.uturn.backward.circle")
            }
        }

        Button(role: .destructive) {
            onAction(.delete(status))
        } label: {
            Label {
                Text("Delete", comment: "Status menu item")
            } icon: {
                Image(systemName: AlohaSymbol.delete)
            }
        }
    }
}

/// A post's link, handed to the system share sheet by SwiftUI itself.
///
/// This replaced presenting `UIActivityViewController` on the window's root
/// view controller, which failed silently whenever a sheet was already up —
/// the root was busy presenting it — and gave the controller no popover
/// anchor, which UIKit requires on iPad. `ShareLink` needs neither. A post
/// without a URL has nothing to share, so nothing is drawn.
struct StatusShareLink<ShareLabel: View>: View {
    let status: Status
    @ViewBuilder let label: () -> ShareLabel

    var body: some View {
        if let url = status.displayed.url {
            ShareLink(item: url, label: label)
        }
    }
}
