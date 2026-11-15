// SPDX-License-Identifier: MIT

import AlohaDesign
import SwiftUI

/// What the reader is told when an action they took did not stick.
///
/// A favourite, boost or bookmark shows at once and is sent behind it
/// (`StatusActions`). When the server refuses, the row flips back — which,
/// unexplained, reads as a tap that did not register. So the failure is said:
/// in a brief toast over the screen on display, and to VoiceOver wherever
/// the reader is, because a button flipping back makes no sound.
@MainActor
@Observable
public final class ActionFeedback {
    public static let shared = ActionFeedback()

    public struct Message: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public let text: String
    }

    /// The failure being shown; one at a time, the newest winning.
    public private(set) var message: Message?

    func report(_ text: String) {
        message = Message(text: text)
        // High priority: it is the answer to something the reader just did,
        // and must not wait behind the row's own value change being read.
        var announcement = AttributedString(text)
        announcement.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(announcement).post()
    }

    func dismiss(_ id: Message.ID) {
        if message?.id == id { message = nil }
    }

    /// The screens on display that can show the toast, newest last.
    ///
    /// A failure can come from any screen with post actions, and more than
    /// one is on display at a time — a wide iPad shows a thread beside the
    /// timeline it was opened from. Each would draw the same toast; only
    /// the newest does, which is the one the reader just acted in or came to.
    private(set) var hosts: [UUID] = []

    func register(_ host: UUID) {
        hosts.removeAll { $0 == host }
        hosts.append(host)
    }

    func unregister(_ host: UUID) {
        hosts.removeAll { $0 == host }
    }
}

extension View {
    /// Shows `ActionFeedback`'s toast over this screen while it is the newest
    /// on display (`ActionFeedback.hosts`).
    func actionFeedbackToast() -> some View {
        overlay(alignment: .bottom) { ActionFeedbackToast() }
    }
}

/// The toast `ActionFeedback` shows: at the bottom, out of the way of the
/// new-posts pill, gone after a few seconds or at a tap.
struct ActionFeedbackToast: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var host = UUID()

    private var feedback: ActionFeedback { .shared }

    var body: some View {
        ZStack {
            if let message = feedback.message, feedback.hosts.last == host {
                toast(message)
                    .transition(
                        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
                    )
                    .task(id: message.id) {
                        try? await Task.sleep(for: .seconds(5))
                        feedback.dismiss(message.id)
                    }
            }
        }
        .animation(
            reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3),
            value: feedback.message
        )
        .onAppear { feedback.register(host) }
        .onDisappear { feedback.unregister(host) }
    }

    private func toast(_ message: ActionFeedback.Message) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AlohaMetrics.space2) {
            Image(systemName: AlohaSymbol.warning)
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text(verbatim: message.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(palette.label)
        .padding(.horizontal, AlohaMetrics.space4)
        .padding(.vertical, AlohaMetrics.space3)
        .background(
            palette.surfaceRaised,
            in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
        )
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.horizontal, AlohaMetrics.space4)
        .padding(.bottom, AlohaMetrics.space4)
        .contentShape(Rectangle())
        .onTapGesture { feedback.dismiss(message.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityAction(named: Text("Dismiss", comment: "Action failure toast action")) {
            feedback.dismiss(message.id)
        }
    }
}
