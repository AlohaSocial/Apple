// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import AlohaNetwork
import SwiftUI

/// A thread somebody wrote to themselves, read as one article: their posts in
/// order, pictures where they put them, and nobody else's replies in between
/// (`SelfThread`).
///
/// Opened from the thread screen's "Read as article", or from the menu of a
/// timeline post that answers its own author. It fetches the conversation
/// itself rather than being handed it, so the route works from a deep link
/// or a restored window as well.
public struct ThreadReaderView: View {
    @Environment(\.alohaPalette) private var palette

    private let statusID: String
    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var posts: [Status] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// Content warnings the reader opened, this visit.
    @State private var revealed: Set<String> = []

    public init(
        statusID: String, session: AccountSession,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.statusID = statusID
        self.session = session
        self.onAction = onAction
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AlohaMetrics.space5) {
                if let first = posts.first {
                    header(first)
                    ForEach(Array(posts.enumerated()), id: \.element.id) { offset, post in
                        if offset > 0 { partBreak(offset + 1) }
                        passage(post)
                    }
                    footer
                }

                if let errorMessage {
                    AlohaErrorStrip(message: errorMessage) {
                        Task { await load() }
                    }
                }
            }
            .padding(AlohaMetrics.space4)
            // A line of an article is easier to follow at a book's measure
            // than across a whole iPad.
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(palette.background)
        .overlay {
            if isLoading && posts.isEmpty { ProgressView() }
        }
        .navigationTitle(Text("Thread", comment: "Thread reader screen title"))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let url = posts.first?.url {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: url) {
                        Label {
                            Text("Share thread", comment: "Thread reader action")
                        } icon: {
                            Image(systemName: AlohaSymbol.share)
                        }
                    }
                }
            }
        }
        .task { await load() }
        .alohaRefreshable { await load() }
    }

    // MARK: - Pieces

    private func header(_ first: Status) -> some View {
        let author = first.account
        return VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
            Button {
                onAction(.openProfile(author))
            } label: {
                HStack(spacing: AlohaMetrics.space3) {
                    AvatarView(account: author, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        EmojiLabel(
                            author.bestDisplayName, emojis: author.emojis, relativeTo: .headline
                        )
                        .font(.headline)
                        .foregroundStyle(palette.label)
                        Text(verbatim: "@\(author.acct)")
                            .font(AlohaType.meta)
                            .foregroundStyle(palette.secondaryLabel)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            HStack(spacing: AlohaMetrics.space2) {
                Text(first.createdAt, format: .dateTime.day().month().year())
                Text(verbatim: "·").accessibilityHidden(true)
                Text(
                    "^[\(posts.count) post](inflect: true)",
                    comment: "Thread reader: how many posts the thread has")
                Text(verbatim: "·").accessibilityHidden(true)
                Text(
                    "^[\(readingMinutes) minute](inflect: true) to read",
                    comment: "Thread reader: estimated reading time")
            }
            .font(AlohaType.meta)
            .foregroundStyle(palette.secondaryLabel)
            .accessibilityElement(children: .combine)
        }
    }

    /// A rule between two posts, said aloud as a heading so a screen reader
    /// can move through the article part by part.
    private func partBreak(_ number: Int) -> some View {
        Rectangle()
            .fill(palette.separator)
            .frame(width: 32, height: 1)
            .frame(maxWidth: .infinity)
            .accessibilityElement()
            .accessibilityLabel(
                Text(
                    "Part \(number) of \(posts.count)",
                    comment: "Thread reader: heading before each post after the first")
            )
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func passage(_ post: Status) -> some View {
        let hasWarning = !post.spoilerText.isEmpty
        let isOpen = !hasWarning || revealed.contains(post.id)
        VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
            if hasWarning {
                warning(post, isOpen: isOpen)
            }
            if isOpen {
                RichTextView(status: post, isSelectable: true) { link in
                    onAction(.followLink(link))
                }
                if !post.mediaAttachments.isEmpty {
                    MediaGrid(
                        attachments: post.mediaAttachments, isSensitive: post.sensitive,
                        policy: session.settings.sensitiveMediaPolicy
                    ) { index in
                        onAction(.openMedia(status: post, index: index))
                    }
                }
                if let poll = post.poll {
                    PollView(poll: poll) { choices in
                        onAction(.vote(pollID: poll.id, choices: choices))
                    }
                }
                if post.mediaAttachments.isEmpty, let card = post.card, card.url != nil {
                    LinkCardView(card: card) { onAction(.openCard(card)) }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// A content warning keeps its post closed here as it does on the
    /// timeline: unrolling a thread is not consent to what it warned about.
    private func warning(_ post: Status, isOpen: Bool) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                if isOpen { revealed.remove(post.id) } else { revealed.insert(post.id) }
            }
        } label: {
            HStack(spacing: AlohaMetrics.space2) {
                Image(systemName: AlohaSymbol.warning)
                EmojiLabel(
                    post.spoilerText, emojis: post.emojis, relativeTo: .footnote, lineLimit: nil
                )
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(palette.label)
            .padding(AlohaMetrics.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                palette.surfaceRaised,
                in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(
            isOpen
                ? Text("Hides this part again", comment: "Thread reader content warning hint")
                : Text("Shows this part", comment: "Thread reader content warning hint"))
    }

    /// The way back to the conversation, where the replies this page left out
    /// are.
    @ViewBuilder
    private var footer: some View {
        if let last = posts.last {
            NavigationLink(value: Route.thread(statusID: last.id)) {
                Label {
                    Text("Read the replies", comment: "Thread reader: open the full conversation")
                } icon: {
                    Image(systemName: AlohaSymbol.reply)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, AlohaMetrics.space3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Simple counting at a reading pace of two hundred words a minute, and
    /// never "0 minutes".
    private var readingMinutes: Int {
        let parser = StatusHTMLParser()
        let words = posts.reduce(0) { total, post in
            total + parser.plainText(post.content).split(whereSeparator: \.isWhitespace).count
        }
        return max(1, Int((Double(words) / 200).rounded()))
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let statusTask = session.client.decode(
                Status.self, from: Endpoint.statuses.status(statusID))
            async let contextTask = session.client.decode(
                StatusContext.self, from: Endpoint.statuses.context(statusID))
            let status = try await statusTask
            let context = try await contextTask
            posts = SelfThread.unroll(
                ancestors: context.ancestors, focused: status.displayed,
                descendants: context.descendants)
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "This thread could not be loaded. Please try again.",
                    comment: "Thread reader load failure")
        }
    }
}
