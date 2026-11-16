// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

#if os(macOS)
    /// A line to write in and Return to send: a reply at the foot of a
    /// thread, or a short post from the menu bar.
    ///
    /// The full composer is a window; this is for the answer that is one
    /// sentence long and would be gone by the time a window had opened. It
    /// sends words only — a picture, a poll or a warning is what the composer
    /// is for, and the button beside the field opens it with what was typed.
    public struct QuickPostField: View {
        @Environment(\.alohaPalette) private var palette

        private let session: AccountSession
        private let replyTo: Status?
        private let onPosted: (Status) -> Void
        private let onExpand: ((String) -> Void)?

        @State private var text = ""
        @State private var isSending = false
        @State private var errorMessage: String?

        public init(
            session: AccountSession, replyTo: Status? = nil,
            onExpand: ((String) -> Void)? = nil,
            onPosted: @escaping (Status) -> Void = { _ in }
        ) {
            self.session = session
            self.replyTo = replyTo
            self.onExpand = onExpand
            self.onPosted = onPosted
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
                HStack(alignment: .bottom, spacing: AlohaMetrics.space2) {
                    AvatarView(account: session.snapshot.asAccount, size: 26)
                    TextField(text: $text, prompt: prompt, axis: .vertical) {
                        prompt
                    }
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .onSubmit { Task { await send() } }
                    .disabled(isSending)

                    if let onExpand {
                        Button {
                            onExpand(text)
                            text = ""
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                        }
                        .buttonStyle(.borderless)
                        .help(Text("Open in the composer", comment: "Quick reply action"))
                    }
                    Button {
                        Task { await send() }
                    } label: {
                        if isSending {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isEmpty || isSending)
                    .help(Text("Send", comment: "Quick reply action"))
                }
                .padding(.horizontal, AlohaMetrics.space3)
                .padding(.vertical, AlohaMetrics.space2)
                .background(
                    palette.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(palette.separator.opacity(0.5), lineWidth: 0.5))

                if let errorMessage {
                    Text(verbatim: errorMessage)
                        .font(.caption)
                        .foregroundStyle(palette.destructive)
                }
            }
        }

        private var prompt: Text {
            if let replyTo {
                Text(
                    "Reply to \(replyTo.displayed.account.bestDisplayName)…",
                    comment: "Quick reply field prompt")
            } else {
                Text("What's happening?", comment: "Composer placeholder")
            }
        }

        private var isEmpty: Bool {
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        /// A reply names the person it answers, as the composer would, unless
        /// that is the writer themselves or the words already do.
        private func addressed(_ words: String) -> String {
            guard let author = replyTo?.displayed.account,
                author.id != session.snapshot.serverAccountID
            else { return words }
            let mention = "@" + author.acct
            return words.localizedCaseInsensitiveContains(mention) ? words : mention + " " + words
        }

        private func send() async {
            let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !words.isEmpty, !isSending else { return }
            isSending = true
            defer { isSending = false }
            do {
                let post = StatusPost(
                    text: addressed(words),
                    visibility: replyTo?.displayed.visibility ?? .public,
                    inReplyToID: replyTo?.displayed.id)
                let sent = try await session.client.decode(
                    Status.self, from: Endpoint.composing.post(post))
                text = ""
                errorMessage = nil
                session.notePosted(sent)
                onPosted(sent)
            } catch {
                await session.handle(error)
                errorMessage =
                    (error as? APIError)?.errorDescription
                    ?? String(
                        localized: "Your post could not be sent. Your text has been kept.",
                        comment: "Quick reply failure")
            }
        }
    }
#endif
