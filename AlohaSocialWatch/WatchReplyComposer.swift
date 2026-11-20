// SPDX-License-Identifier: MIT

import AlohaDesign
import SwiftUI

/// A reply from the wrist — to a post or in a conversation — said or picked,
/// read back, then sent.
///
/// Replies used to go out the moment dictation finished, and a failure
/// threw the words away. Dictation mishears, and a misheard reply to a
/// public post is out in the world before the wrist is down, so the words
/// are shown with Send, as a new post's already were. An "Undo" countdown
/// was the other choice and the worse one on a wrist: it sends whatever
/// was heard unless the reader keeps watching the screen for the length of
/// the countdown, which is exactly what a raised arm does not do. Review
/// costs one tap — or, with Double Tap, none: the pinch that opened
/// dictation also sends what it heard. On failure the words stay, with
/// "Try again".
///
/// Quick replies sit above the field: a canned "Thanks!" needs no dictation
/// and cannot be misheard, but it still lands in the draft rather than
/// going out at once, because a chip is a small target on a moving wrist
/// and a stray tap should not answer somebody.
struct WatchReplyComposer: View {
    @Environment(WatchLink.self) private var link
    /// Sends the words with the idempotency key to post them under; throws
    /// where the server did not take them.
    let send: (_ words: String, _ idempotencyKey: String) async throws -> Void

    @State private var draft = ""
    @State private var state: SendState = .writing
    /// The same key while the words stay the same: "Try again" after a
    /// timeout that did reach the server must not post the reply twice
    /// (docs/12 §2, idempotency). New words, new key.
    @State private var idempotencyKey = UUID().uuidString

    private enum SendState: Equatable {
        case writing, sending, sent, failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if draft.isEmpty {
                quickReplies
                // Dictation, Scribble and emoji come with the system's own
                // text entry; the watch has no keyboard worth building.
                TextFieldLink {
                    Label {
                        Text("Reply", comment: "Watch post action")
                    } icon: {
                        Image(systemName: AlohaSymbol.reply)
                    }
                } onSubmit: { typed in
                    take(typed)
                }
                .handGestureShortcut(.primaryAction)
            } else {
                // A field rather than a label: tapping it opens the words
                // for correcting, instead of saying them all again.
                TextField(text: $draft, axis: .vertical) {
                    Text("Reply", comment: "Watch post action")
                }
                .lineLimit(1...8)
                .font(.caption)
                .disabled(state == .sending)
                .onChange(of: draft) { idempotencyKey = UUID().uuidString }

                Button {
                    Task { await submit() }
                } label: {
                    Label {
                        if state == .failed {
                            Text(
                                "Try again",
                                comment: "Watch reply action: send again after a failure")
                        } else {
                            Text("Send", comment: "Watch reply action: send the reply shown above")
                        }
                    } icon: {
                        Image(systemName: "paperplane.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(state == .sending)
                .handGestureShortcut(.primaryAction)

                Button(role: .destructive) {
                    draft = ""
                    state = .writing
                } label: {
                    Text("Discard", comment: "Watch reply action: throw the unsent reply away")
                        .frame(maxWidth: .infinity)
                }
                .disabled(state == .sending)
            }

            switch state {
            case .writing: EmptyView()
            case .sending: ProgressView().frame(maxWidth: .infinity)
            case .sent:
                Text("Sent", comment: "Watch reply status").font(.caption2)
            case .failed:
                Text("Couldn't send. Your words are still here.", comment: "Watch reply status")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    /// One row the reader swipes along, so eight phrases do not push the
    /// reply field off the bottom of the screen.
    @ViewBuilder private var quickReplies: some View {
        if !link.quickReplies.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(link.quickReplies, id: \.self) { phrase in
                        Button {
                            take(phrase)
                        } label: {
                            Text(verbatim: phrase)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .fixedSize()
                    }
                }
            }
            .scrollIndicators(.hidden)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Quick replies", comment: "Watch, the row of canned replies"))
        }
    }

    private func take(_ typed: String) {
        let words = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        draft = words
        idempotencyKey = UUID().uuidString
        state = .writing
    }

    private func submit() async {
        let words = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else {
            draft = ""
            return
        }
        state = .sending
        do {
            try await send(words, idempotencyKey)
            draft = ""
            state = .sent
            WatchHaptics.succeeded()
        } catch {
            state = .failed
            WatchHaptics.failed()
        }
    }
}
