// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

#if os(macOS) || os(iOS)
    /// A line to write in and send: a reply at the foot of a thread, or a
    /// short post from the Mac's menu bar.
    ///
    /// The full composer is a sheet or a window; this is for the answer that
    /// is one sentence long and would be gone by the time either had opened.
    /// It sends words only — a picture, a poll or a warning is what the
    /// composer is for, and the button beside the field opens it with what
    /// was typed, addressed. It answers by the composer's rules: every
    /// mention, the reply never less private than the post, the server's
    /// character limit (`QuickReply`).
    public struct QuickPostField: View {
        @Environment(\.alohaPalette) private var palette

        private let session: AccountSession
        private let replyTo: Status?
        private let onPosted: (Status) -> Void
        private let onExpand: ((String) -> Void)?

        @State private var text = ""
        @State private var isSending = false
        @State private var errorMessage: String?
        /// The key the last attempt was sent with, and the words it carried:
        /// a retry of the same words reuses it, so a send whose answer was
        /// lost does not post twice (docs/12 §2, idempotency).
        @State private var attempt: (text: String, key: String)?
        @FocusState private var isFocused: Bool

        /// - Parameter onExpand: opens the full composer with the text as it
        ///   would be sent, mentions included. The field is emptied.
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

        private var rules: QuickReply {
            QuickReply(
                replyTo: replyTo?.displayed, viewerHandle: session.snapshot.handle,
                defaultVisibility: session.settings.defaultVisibility,
                limits: session.capabilities.limits)
        }

        public var body: some View {
            let rules = rules
            VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
                HStack(alignment: .bottom, spacing: AlohaMetrics.space2) {
                    AvatarView(account: session.snapshot.asAccount, size: 26)
                        .accessibilityHidden(true)
                        .padding(.bottom, avatarInset)
                    TextField(text: $text, prompt: prompt, axis: .vertical) {
                        prompt
                    }
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isFocused)
                    .padding(.bottom, avatarInset)
                    // Return sends on the Mac; on a phone's keyboard it is a
                    // new line, and the send button is beside the field.
                    .onSubmit { Task { await send() } }
                    .disabled(isSending)
                    .accessibilityIdentifier("quickReply.field")

                    if rules.showsCount(text) {
                        remainingCount(rules.remaining(text))
                    }
                    if let onExpand {
                        Button {
                            onExpand(rules.composerText(text))
                            text = ""
                            attempt = nil
                            isFocused = false
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .frame(minWidth: buttonSide, minHeight: buttonSide)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(
                            Text("Open in the composer", comment: "Quick reply action")
                        )
                        .help(Text("Open in the composer", comment: "Quick reply action"))
                    }
                    Button {
                        Task { await send() }
                    } label: {
                        Group {
                            if isSending {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                        }
                        .frame(minWidth: buttonSide, minHeight: buttonSide)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(!rules.canSend(text) || isSending)
                    .accessibilityLabel(Text("Send", comment: "Quick reply action"))
                    .help(Text("Send", comment: "Quick reply action"))
                    .accessibilityIdentifier("quickReply.send")
                }
                .padding(.horizontal, AlohaMetrics.space3)
                .padding(.vertical, fieldPadding)
                .background(
                    palette.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(palette.separator.opacity(0.5), lineWidth: 0.5))

                if let errorMessage {
                    Text(verbatim: errorMessage)
                        .font(.caption)
                        .foregroundStyle(palette.destructive)
                }
            }
        }

        /// Shown only near the limit, where it tells the writer something.
        private func remainingCount(_ remaining: Int) -> some View {
            Text(remaining, format: .number)
                .font(.caption.monospacedDigit())
                .foregroundStyle(remaining < 0 ? palette.destructive : palette.secondaryLabel)
                .padding(.bottom, avatarInset)
                .accessibilityLabel(
                    Text(
                        "^[\(remaining) character](inflect: true) left",
                        comment: "Quick reply: characters left before the server's limit"))
        }

        /// A finger needs a bigger target than a pointer.
        private var buttonSide: CGFloat {
            #if os(iOS)
                36
            #else
                0
            #endif
        }

        /// Lines the avatar and the text up with the middle of a taller button.
        private var avatarInset: CGFloat {
            #if os(iOS)
                5
            #else
                0
            #endif
        }

        private var fieldPadding: CGFloat {
            #if os(iOS)
                AlohaMetrics.space1
            #else
                AlohaMetrics.space2
            #endif
        }

        private var cornerRadius: CGFloat {
            #if os(iOS)
                22
            #else
                12
            #endif
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

        private func send() async {
            let rules = rules
            guard rules.canSend(text), !isSending else { return }
            let typed = text
            isSending = true
            defer { isSending = false }
            let key =
                attempt.flatMap { $0.text == typed ? $0.key : nil } ?? UUID().uuidString
            attempt = (typed, key)
            do {
                let post = rules.post(
                    typed, language: session.settings.defaultLanguage, idempotencyKey: key)
                let sent = try await session.client.decode(
                    Status.self, from: Endpoint.composing.post(post))
                text = ""
                attempt = nil
                errorMessage = nil
                isFocused = false
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
