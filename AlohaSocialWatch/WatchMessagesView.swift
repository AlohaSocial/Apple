// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Direct messages on the wrist: the conversations, newest first, each with
/// who it is with and the start of the last thing said.
///
/// The watch had a complication counting unread messages and nowhere to read
/// them. A message is the thing a wrist is good for — short, from somebody
/// in particular, answered in a sentence — so this is a list of them and a
/// way to answer, and nothing a phone does better.
struct WatchConversationsView: View {
    @Environment(WatchLink.self) private var link
    @State private var feed = WatchFeed<Conversation>(.conversations)

    var body: some View {
        List {
            ForEach(feed.items) { conversation in
                NavigationLink {
                    WatchConversationView(conversation: conversation)
                } label: {
                    WatchConversationRow(conversation: conversation)
                }
            }
            if feed.items.isEmpty && !feed.isLoading && !feed.isShowingCache {
                Text("No messages yet", comment: "Watch, empty messages list").font(.caption2)
            }
            if feed.isShowingCache {
                WatchUpdatedHint(updatedAt: feed.updatedAt)
            }
        }
        .navigationTitle(Text("Direct messages", comment: "Watch messages screen title"))
        .task(id: link.credentials?.accountID) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        await feed.load(accountID: link.credentials?.accountID) {
            guard let client = link.client else { throw APIError.invalidResponse }
            return try await client.decode(
                LossyArray<Conversation>.self, from: Endpoint.timelines.conversations(limit: 20)
            ).elements
        }
    }
}

/// One conversation in the list: its people, a dot while it is unread, and
/// the last message's warning or first lines.
struct WatchConversationRow: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if conversation.unread {
                    Circle()
                        .fill(.tint)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel(Text("Unread", comment: "Watch, unread conversation"))
                }
                Text(verbatim: WatchMessages.names(of: conversation))
                    .font(.caption.weight(conversation.unread ? .bold : .semibold))
                    .lineLimit(1)
            }
            if let last = conversation.lastStatus {
                let warning = WatchText.warning(of: last)
                if warning.isEmpty {
                    Text(WatchText.body(of: last))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    WatchWarningLabel(warning: warning)
                }
            }
        }
    }
}

/// What the messages screens share: who a conversation is with, and how a
/// reply is addressed.
enum WatchMessages {
    static func names(of conversation: Conversation) -> String {
        let names = conversation.accounts.map(\.bestDisplayName)
        return names.isEmpty
            ? String(localized: "You", comment: "Conversation with nobody else")
            : names.formatted(.list(type: .and))
    }

    /// A direct message reaches the people it names and nobody else, so a
    /// reply names everybody in the conversation: its other people, and
    /// anyone the last message mentioned — the phone's rule.
    static func addressed(
        _ text: String, to conversation: Conversation, after last: Status?, viewer: String?
    ) -> String {
        var handles = conversation.accounts.map(\.acct)
        if let last {
            for handle in last.replyMentions(excluding: viewer) where !handles.contains(handle) {
                handles.append(handle)
            }
        }
        let missing = handles.filter { !text.localizedCaseInsensitiveContains("@\($0)") }
        guard !missing.isEmpty else { return text }
        return missing.map { "@\($0)" }.joined(separator: " ") + " " + text
    }
}

/// One conversation: its messages oldest first, yours on the trailing side,
/// and a reply by dictation, Scribble, the keyboard or a quick reply — read
/// back before it is sent (`WatchReplyComposer`).
struct WatchConversationView: View {
    @Environment(WatchLink.self) private var link
    let conversation: Conversation

    @State private var messages: [Status] = []
    @State private var isLoading = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(messages) { message in
                        bubble(message)
                            .id(message.id)
                    }
                    if messages.isEmpty && isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    }

                    // The same composer as a reply to a post.
                    WatchReplyComposer { typed, key in try await send(typed, key: key) }
                        .id("reply")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // A conversation opens where it left off: at its newest message.
            .onChange(of: messages.last?.id) { _, _ in
                proxy.scrollTo("reply", anchor: .bottom)
            }
        }
        .navigationTitle(Text(verbatim: WatchMessages.names(of: conversation)))
        .task { await load() }
    }

    private func bubble(_ message: Status) -> some View {
        let isMine = isMine(message)
        let warning = WatchText.warning(of: message)
        return VStack(alignment: .leading, spacing: 2) {
            if !isMine && conversation.accounts.count > 1 {
                Text(verbatim: message.account.bestDisplayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if warning.isEmpty {
                Text(WatchText.body(of: message)).font(.caption)
            } else {
                WatchWarningLabel(warning: warning)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            isMine ? AnyShapeStyle(.tint.opacity(0.35)) : AnyShapeStyle(.fill.tertiary),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        .padding(isMine ? .leading : .trailing, 18)
    }

    /// The pairing carries the reader's handle, not their id on the server.
    private func isMine(_ message: Status) -> Bool {
        guard let handle = link.credentials?.handle else { return false }
        let acct = message.account.acct
        return acct.caseInsensitiveCompare(handle) == .orderedSame
            || handle.lowercased().hasPrefix(acct.lowercased() + "@")
    }

    /// The last message at once, then the thread it belongs to. A direct
    /// status's context holds only what this reader may see.
    private func load() async {
        defer { isLoading = false }
        guard let last = conversation.lastStatus else { return }
        if messages.isEmpty { messages = [last] }
        guard let client = link.client else { return }
        if conversation.unread {
            _ = try? await client.send(Endpoint.timelines.markConversationRead(conversation.id))
        }
        guard
            let context = try? await client.decode(
                StatusContext.self, from: Endpoint.statuses.context(last.id))
        else { return }
        merge(context.ancestors + [last] + context.descendants)
    }

    private func merge(_ incoming: [Status]) {
        var byID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for status in incoming { byID[status.id] = status }
        messages = byID.values.sorted {
            ($0.createdAt, $0.id) < ($1.createdAt, $1.id)
        }
    }

    private func send(_ words: String, key: String) async throws {
        guard let client = link.client else { throw APIError.invalidResponse }
        let post = StatusPost(
            text: WatchMessages.addressed(
                words, to: conversation, after: messages.last, viewer: link.credentials?.handle),
            visibility: .direct, inReplyToID: messages.last?.id, idempotencyKey: key)
        let sent = try await client.decode(Status.self, from: Endpoint.composing.post(post))
        merge([sent])
    }
}

/// A new post from the wrist: say it, choose who sees it, send it.
///
/// Words only. A picture, a poll or a thread is the phone's work; what a
/// watch can do well is take down a sentence while the thought is there.
/// The words are shown before anything is sent, because dictation mishears.
struct WatchComposeView: View {
    @Environment(WatchLink.self) private var link
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var visibility: AlohaModels.Visibility = .public
    @State private var state: PostState = .writing
    /// Kept while the words are, so posting again after a timeout cannot
    /// post twice (docs/12 §2, idempotency).
    @State private var idempotencyKey = UUID().uuidString

    private enum PostState: Equatable {
        case writing, sending, sent, failed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if !text.isEmpty {
                    Text(verbatim: text)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(
                            .fill.tertiary,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                TextFieldLink {
                    Label {
                        if text.isEmpty {
                            Text("Write", comment: "Watch compose action: enter the post's text")
                        } else {
                            Text(
                                "Change", comment: "Watch compose action: re-enter the post's text")
                        }
                    } icon: {
                        Image(systemName: "mic")
                    }
                } onSubmit: { typed in
                    text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
                    idempotencyKey = UUID().uuidString
                    state = .writing
                }

                Picker(selection: $visibility) {
                    Text("Public", comment: "Visibility").tag(AlohaModels.Visibility.public)
                    Text("Unlisted", comment: "Visibility").tag(AlohaModels.Visibility.unlisted)
                    Text("Followers", comment: "Visibility").tag(
                        AlohaModels.Visibility.private)
                } label: {
                    Text("Visibility", comment: "Composer picker")
                }
                .onChange(of: visibility) { idempotencyKey = UUID().uuidString }

                Button {
                    Task { await post() }
                } label: {
                    Label {
                        Text("Post", comment: "Watch compose action: send the post")
                    } icon: {
                        Image(systemName: "paperplane.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.isEmpty || state == .sending || state == .sent)
                .handGestureShortcut(.primaryAction)

                switch state {
                case .writing: EmptyView()
                case .sending: ProgressView().frame(maxWidth: .infinity)
                case .sent:
                    Text("Posted", comment: "Watch compose status").font(.caption2)
                case .failed:
                    Text(
                        "Couldn't post. Your words are still here.", comment: "Watch compose status"
                    )
                    .font(.caption2)
                    .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(Text("New post", comment: "Watch compose screen title"))
    }

    private func post() async {
        guard !text.isEmpty, let client = link.client else { return }
        state = .sending
        do {
            _ = try await client.send(
                Endpoint.composing.post(
                    StatusPost(text: text, visibility: visibility, idempotencyKey: idempotencyKey)))
            state = .sent
            WatchHaptics.succeeded()
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        } catch {
            state = .failed
            WatchHaptics.failed()
        }
    }
}
