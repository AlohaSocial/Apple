// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import AlohaNetwork
import SwiftUI

/// One direct-message thread as a chat: the other person in the bar, day
/// separators, bubbles that sit right for yours and left for theirs, and a
/// message field at the foot with visibility locked to direct (docs/05 §8).
///
/// The shape follows Nextcloud Social's Messages page: consecutive messages
/// from one sender group under a single avatar, and a bubble's corner nearest
/// the sender is the sharp one.
public struct ConversationThreadView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let conversation: Conversation
    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var messages: [Status] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var errorMessage: String?
    /// A message that did not go out is a different problem from a thread
    /// that did not load, and it belongs next to the field that still holds
    /// the text.
    @State private var sendError: String?
    @FocusState private var isFieldFocused: Bool

    public init(
        conversation: Conversation, session: AccountSession,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.conversation = conversation
        self.session = session
        self.onAction = onAction
    }

    /// The people in the thread other than you.
    private var others: [Account] {
        conversation.accounts.filter { $0.id != session.snapshot.serverAccountID }
    }

    private var title: String {
        let names = others.map(\.bestDisplayName)
        return names.isEmpty
            ? String(localized: "You", comment: "Conversation with nobody else")
            : names.formatted(.list(type: .and))
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if isLoading && messages.isEmpty {
                        ProgressView().padding(.top, AlohaMetrics.space6)
                    }

                    if messages.isEmpty && !isLoading { intro }

                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        if startsNewDay(at: index) {
                            daySeparator(message.createdAt)
                        }
                        bubbleRow(message, at: index)
                            .id(message.id)
                    }

                    // An anchor under the last bubble, so scrolling to the
                    // bottom lands past its timestamp rather than on it.
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, AlohaMetrics.space3)
                .padding(.vertical, AlohaMetrics.space2)
            }
            // Unavailable on visionOS, where there is no keyboard over the
            // content to dismiss.
            #if !os(visionOS)
                .scrollDismissesKeyboard(.interactively)
            #endif
            .onChange(of: messages.last?.id) { _, _ in
                scrollToBottom(proxy)
            }
            .task {
                await load()
                scrollToBottom(proxy, animated: false)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if let sendError {
                    failureStrip(sendError, retry: .send)
                } else if let errorMessage {
                    failureStrip(errorMessage, retry: .load)
                }
                composer
            }
        }
        // After the inset, so the field sits on the palette rather than on
        // whatever is behind the window — glass needs that to blur.
        .background(palette.background)
        .navigationTitle(Text(title))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) { header }
        }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        Button {
            if let first = others.first { onAction(.openProfile(first)) }
        } label: {
            HStack(spacing: AlohaMetrics.space2) {
                ConversationAvatar(accounts: others, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.label)
                        .lineLimit(1)
                    Text("Private conversation", comment: "Conversation header subtitle")
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryLabel)
                }
            }
        }
        .buttonStyle(.plain)
        // With nobody else in the thread there is no profile to open, and a
        // control that does nothing is worse than no control at all.
        .disabled(others.isEmpty)
        .accessibilityLabel(
            Text("Private conversation with \(title)", comment: "Conversation header label"))
    }

    private var intro: some View {
        VStack(spacing: AlohaMetrics.space2) {
            ConversationAvatar(accounts: others, size: 72)
            Text(title)
                .font(AlohaType.display)
            if let first = others.first {
                Text(first.qualifiedHandle(localHost: session.snapshot.instanceHost))
                    .font(AlohaType.meta)
                    .foregroundStyle(palette.tertiaryLabel)
            }
            Text(
                "Only the people in this conversation can see what you write here.",
                comment: "Conversation intro"
            )
            .font(.footnote)
            .foregroundStyle(palette.secondaryLabel)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AlohaMetrics.space6)
    }

    // MARK: - Messages

    private func isOwn(_ message: Status) -> Bool {
        message.account.id == session.snapshot.serverAccountID
    }

    private func startsNewDay(at index: Int) -> Bool {
        guard index > 0 else { return true }
        return !Calendar.current.isDate(
            messages[index - 1].createdAt, inSameDayAs: messages[index].createdAt)
    }

    /// True when the message after this one is from the same sender on the
    /// same day, so the avatar and timestamp wait for the group's end.
    private func continuesGroup(at index: Int) -> Bool {
        guard index + 1 < messages.count else { return false }
        let next = messages[index + 1]
        return next.account.id == messages[index].account.id
            && Calendar.current.isDate(next.createdAt, inSameDayAs: messages[index].createdAt)
            && next.createdAt.timeIntervalSince(messages[index].createdAt) < 5 * 60
    }

    private func daySeparator(_ date: Date) -> some View {
        Text(dayLabel(date))
            .font(AlohaType.micro)
            .foregroundStyle(palette.secondaryLabel)
            .padding(.horizontal, AlohaMetrics.space3)
            .padding(.vertical, AlohaMetrics.space1)
            .background(palette.surfaceRaised, in: Capsule())
            .padding(.vertical, AlohaMetrics.space3)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
    }

    private func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return String(localized: "Today", comment: "Conversation day separator")
        }
        if calendar.isDateInYesterday(date) {
            return String(localized: "Yesterday", comment: "Conversation day separator")
        }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private func bubbleRow(_ message: Status, at index: Int) -> some View {
        let own = isOwn(message)
        let isLast = !continuesGroup(at: index)
        return HStack(alignment: .bottom, spacing: AlohaMetrics.space2) {
            if own {
                Spacer(minLength: 48)
            } else {
                // The avatar sits under the last bubble of a run; the ones
                // above leave its column empty so the bubbles line up.
                Group {
                    if isLast {
                        Button {
                            onAction(.openProfile(message.account))
                        } label: {
                            AvatarView(account: message.account, size: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHidden(true)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 28, height: 28)
            }

            VStack(alignment: own ? .trailing : .leading, spacing: 3) {
                bubble(message, own: own)
                if isLast {
                    Text(message.createdAt, format: .dateTime.hour().minute())
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryLabel)
                        .padding(.horizontal, AlohaMetrics.space1)
                }
            }

            if !own { Spacer(minLength: 48) }
        }
        .padding(.bottom, isLast ? AlohaMetrics.space2 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(message, own: own))
    }

    private func bubble(_ message: Status, own: Bool) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            if message.hasContentWarning {
                Label {
                    Text(message.spoilerText)
                } icon: {
                    Image(systemName: AlohaSymbol.warning)
                }
                .font(.footnote.weight(.medium))
            }

            if !plainText(message).isEmpty {
                RichTextView(status: message, isSelectable: true) { link in
                    onAction(.followLink(link))
                }
            }

            if !message.mediaAttachments.isEmpty {
                MediaGrid(
                    attachments: message.mediaAttachments,
                    isSensitive: message.sensitive,
                    policy: session.settings.sensitiveMediaPolicy
                ) { index in
                    onAction(.openMedia(status: message, index: index))
                }
                .frame(maxWidth: 260)
            }

            if let poll = message.poll {
                PollView(poll: poll) { choices in
                    onAction(.vote(pollID: poll.id, choices: choices))
                }
            }
        }
        .font(.body)
        .foregroundStyle(own ? palette.onAccent : palette.label)
        // Links and mentions are drawn in the accent, which vanishes on an
        // accent bubble; your own bubbles get a palette that keeps them legible.
        .environment(\.alohaPalette, own ? ownBubblePalette : palette)
        .padding(.horizontal, AlohaMetrics.space3)
        .padding(.vertical, AlohaMetrics.space2)
        .background(own ? palette.accent : palette.surfaceRaised, in: BubbleShape(own: own))
        .contextMenu {
            Button {
                onAction(.reply(message))
            } label: {
                Label {
                    Text("Reply", comment: "Status action")
                } icon: {
                    Image(systemName: AlohaSymbol.reply)
                }
            }
            Button {
                onAction(.open(message))
            } label: {
                Label {
                    Text("Open post", comment: "Conversation bubble action")
                } icon: {
                    Image(systemName: "arrow.up.right.square")
                }
            }
            Divider()
            StatusMenu(status: message, onAction: onAction)
        }
    }

    private var ownBubblePalette: AlohaPalette {
        var inverted = palette
        inverted.label = palette.onAccent
        inverted.secondaryLabel = palette.onAccent.opacity(0.85)
        inverted.tertiaryLabel = palette.onAccent.opacity(0.7)
        inverted.mention = palette.onAccent
        inverted.hashtag = palette.onAccent
        inverted.accent = palette.onAccent
        inverted.surfaceRaised = palette.onAccent.opacity(0.2)
        return inverted
    }

    private func accessibilityLabel(_ message: Status, own: Bool) -> Text {
        let who =
            own
            ? String(localized: "You", comment: "Conversation own message sender")
            : message.account.bestDisplayName
        let when = message.createdAt.formatted(.dateTime.hour().minute())
        var parts = [who, when]
        if message.hasContentWarning { parts.append(message.spoilerText) }
        let body = plainText(message)
        if !body.isEmpty { parts.append(body) }
        if !message.mediaAttachments.isEmpty {
            parts.append(
                String(
                    localized: "^[\(message.mediaAttachments.count) attachment](inflect: true)",
                    comment: "Accessibility media count"))
        }
        return Text(verbatim: parts.joined(separator: ", "))
    }

    // MARK: - Composer

    /// Which of the two things that can fail is being reported, so the
    /// retry runs that one.
    private enum Retry { case load, send }

    /// The failure sits above the field, not at the head of a scroll that
    /// has already moved on to the newest message.
    private func failureStrip(_ message: String, retry: Retry) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: AlohaSymbol.warning)
            Text(message).font(.footnote)
            Spacer()
            Button {
                Task { await perform(retry) }
            } label: {
                Text("Retry", comment: "Conversation reload action")
            }
            .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(palette.destructive)
        .padding(.horizontal, AlohaMetrics.space3)
        .padding(.vertical, AlohaMetrics.space2)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.separator).frame(height: 0.5)
        }
    }

    private func perform(_ retry: Retry) async {
        switch retry {
        case .load: await load()
        case .send: await send()
        }
    }

    private var composer: some View {
        GlassEffectContainer(spacing: AlohaMetrics.space2) {
            HStack(alignment: .bottom, spacing: AlohaMetrics.space2) {
                Button {
                    // The full composer, for attachments, polls and a content
                    // warning. Replying to the last message keeps it direct
                    // and addressed to everybody in the thread.
                    if let last = messages.last { onAction(.reply(last)) }
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.secondaryLabel)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .disabled(messages.isEmpty)
                .accessibilityLabel(Text("Attach", comment: "Conversation composer action"))

                TextField(
                    String(localized: "Write a message…", comment: "Conversation field prompt"),
                    text: $draft, axis: .vertical
                )
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .focused($isFieldFocused)
                .accessibilityIdentifier("conversation.field")
                .padding(.horizontal, AlohaMetrics.space3)
                .padding(.vertical, AlohaMetrics.space2)
                .frame(minHeight: 44)
                .glassEffect(.regular, in: Capsule())
                .accessibilityLabel(Text("Message", comment: "Conversation field label"))
                .onChange(of: draft) { _, _ in
                    // Editing the text means the last failure no longer
                    // describes what is about to be sent.
                    sendError = nil
                }

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.onAccent)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(palette.accent).interactive(), in: Circle())
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel(Text("Send", comment: "Conversation composer action"))
            }
        }
        .padding(.horizontal, AlohaMetrics.space3)
        .padding(.vertical, AlohaMetrics.space2)
    }

    private var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Loading and sending

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let last = conversation.lastStatus else {
            messages = []
            return
        }
        if messages.isEmpty { merge([last]) }
        do {
            async let statusTask = session.client.decode(
                Status.self, from: Endpoint.statuses.status(last.id))
            async let contextTask = session.client.decode(
                StatusContext.self, from: Endpoint.statuses.context(last.id))
            let focused = try await statusTask
            let context = try await contextTask
            merge(context.ancestors + [focused] + context.descendants)
            errorMessage = nil
        } catch {
            // The last message is still worth showing on its own.
            guard !Task.isCancelled else { return }
            merge([last])
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "Messages could not be loaded. Pull down to try again.")
        }
    }

    /// Everything in the thread, oldest first, without duplicates. The
    /// context of a direct status already holds only what this reader may
    /// see, so nothing is filtered out here.
    private func merge(_ incoming: [Status]) {
        var byID: [String: Status] = Dictionary(
            messages.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for status in incoming { byID[status.id] = status }
        messages = byID.values.sorted { $0.createdAt < $1.createdAt }
    }

    private func send() async {
        let submittedDraft = draft
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }

        let post = StatusPost(
            text: addressed(text), visibility: .direct, inReplyToID: messages.last?.id)
        do {
            let sent = try await session.client.decode(
                Status.self, from: Endpoint.composing.post(post))
            // Preserve anything typed while the previous message was sending.
            if draft == submittedDraft { draft = "" }
            sendError = nil
            merge([sent])
            try? await session.timelineStore.updateStatus(accountID: session.id, status: sent)
        } catch {
            await session.handle(error)
            sendError =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized:
                        "Your message could not be sent. Your text has been kept; please try again."
                )
        }
    }

    /// A direct message reaches only who it names, so every participant is
    /// mentioned unless the text already does it.
    private func addressed(_ text: String) -> String {
        let viewer = session.snapshot.handle
        var handles = others.map(\.acct)
        if let last = messages.last {
            for handle in last.replyMentions(excluding: viewer) where !handles.contains(handle) {
                handles.append(handle)
            }
        }
        let missing = handles.filter { !text.localizedCaseInsensitiveContains("@\($0)") }
        guard !missing.isEmpty else { return text }
        return missing.map { "@\($0)" }.joined(separator: " ") + " " + text
    }

    private func plainText(_ status: Status) -> String {
        StatusHTMLParser().plainText(status.content).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard !messages.isEmpty else { return }
        if animated && !reduceMotion {
            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

/// A chat bubble: three round corners, and the one nearest the sender sharp.
struct BubbleShape: Shape {
    let own: Bool

    func path(in rect: CGRect) -> Path {
        let radii = RectangleCornerRadii(
            topLeading: AlohaMetrics.cornerLarge,
            bottomLeading: own ? AlohaMetrics.cornerLarge : AlohaMetrics.cornerSmall,
            bottomTrailing: own ? AlohaMetrics.cornerSmall : AlohaMetrics.cornerLarge,
            topTrailing: AlohaMetrics.cornerLarge)
        return UnevenRoundedRectangle(cornerRadii: radii, style: .continuous).path(in: rect)
    }
}
