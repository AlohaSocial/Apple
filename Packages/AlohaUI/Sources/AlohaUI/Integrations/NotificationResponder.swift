// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import Foundation
import OSLog
import UserNotifications

/// What a person did with one of the app's notifications, reduced to the values
/// that cross into the app: the system's response object is not `Sendable`, and
/// its `userInfo` is `[AnyHashable: Any]`.
public struct NotificationReply: Sendable, Hashable {
    public let actionIdentifier: String
    public let accountID: UUID?
    public let statusID: String?
    /// What was typed into the Reply action, when there was typing to do.
    public let typedText: String

    public init(actionIdentifier: String, userInfo: [AnyHashable: Any], typedText: String?) {
        self.actionIdentifier = actionIdentifier
        self.accountID = (userInfo["accountID"] as? String).flatMap(UUID.init(uuidString:))
        let status = userInfo["statusID"] as? String
        self.statusID = status?.isEmpty == false ? status : nil
        self.typedText = typedText ?? ""
    }

    public init(response: UNNotificationResponse) {
        self.init(
            actionIdentifier: response.actionIdentifier,
            userInfo: response.notification.request.content.userInfo,
            typedText: (response as? UNTextInputNotificationResponse)?.userText)
    }
}

/// Carries out a notification's action, on every platform that raises them.
///
/// The iOS app delegate and the Mac one both hand over here, so the lock screen
/// and Notification Centre on a Mac cannot answer the same tap differently.
@MainActor
public enum NotificationResponder {
    private static let logger = Logger(subsystem: "social.aloha.app", category: "notifications")

    /// Answers a tap or an action button.
    ///
    /// An action can arrive before any window exists — a reply sent from the
    /// lock screen launches the app in the background — so the accounts are
    /// loaded here rather than assumed.
    public static func respond(_ reply: NotificationReply, environment: AppEnvironment) async {
        guard reply.actionIdentifier != UNNotificationDismissActionIdentifier else { return }
        await environment.loadIfNeeded()

        if reply.actionIdentifier == UNNotificationDefaultActionIdentifier {
            open(reply, environment: environment)
            return
        }

        guard let accountID = reply.accountID, let statusID = reply.statusID,
            let session = environment.sessions.first(where: { $0.id == accountID })
        else { return }
        guard let status = await status(statusID, session: session) else { return }

        switch reply.actionIdentifier {
        case "favourite": await StatusActions.perform(.favourite(status), session: session)
        case "boost": await StatusActions.perform(.boost(status), session: session)
        case "muteConversation":
            await StatusActions.perform(.muteConversation(status), session: session)
        case "reply":
            let typed = reply.typedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if typed.isEmpty {
                // Nothing typed: open the thread rather than guess at a body.
                open(reply, environment: environment)
            } else {
                await sendReply(typed, to: status, session: session)
            }
        default: break
        }
    }

    /// How a notification raised while the app is in front is shown.
    ///
    /// A mention is somebody talking to you, so it still gets its banner. The
    /// rest — likes, boosts, follows, a digest — goes quietly into Notification
    /// Centre: the person is already reading the app, and a banner over the
    /// timeline for a favourite is the interruption the digest exists to avoid
    /// (docs/08 §8).
    public nonisolated static func presentationOptions(
        forCategory category: String
    ) -> UNNotificationPresentationOptions {
        category == "mention" ? [.banner, .list, .sound] : [.list]
    }

    /// Where a tap lands: the post the notification is about, or the
    /// notifications screen for the ones that are about no post (a follow, a
    /// digest summary).
    nonisolated static func route(forTapOn statusID: String?) -> Route {
        statusID.map { Route.thread(statusID: $0) } ?? .notifications
    }

    /// The text that is actually posted for a reply typed on the lock screen.
    ///
    /// The composer starts a reply with the people in the conversation, and a
    /// reply sent without them reaches nobody on the other server — so the
    /// same mentions go in front of what was typed, minus any the person typed
    /// themselves and minus the replier.
    nonisolated static func replyText(
        typed: String, to status: Status, viewerHandle: String?
    ) -> String {
        let typedLowercased = typed.lowercased()
        let missing = status.replyMentions(excluding: viewerHandle).filter { handle in
            !typedLowercased.contains("@\(handle.lowercased())")
        }
        guard !missing.isEmpty else { return typed }
        return missing.map { "@\($0)" }.joined(separator: " ") + " " + typed
    }

    /// The draft a lock-screen reply posts. A reply is never less restrictive
    /// than what it answers, and keeps the content warning it was written
    /// under, as the composer would.
    nonisolated static func replyDraft(
        typed: String, to status: Status, viewerHandle: String?, defaultVisibility: Visibility
    ) -> StatusPost {
        let target = status.displayed
        return StatusPost(
            text: replyText(typed: typed, to: status, viewerHandle: viewerHandle),
            visibility: status.replyVisibility(default: defaultVisibility),
            spoilerText: target.spoilerText.isEmpty ? nil : target.spoilerText,
            sensitive: target.sensitive,
            inReplyToID: target.id)
    }

    // MARK: - Private

    private static func open(_ reply: NotificationReply, environment: AppEnvironment) {
        // The notification belongs to one account; opening it under another
        // would show a post that account cannot act on, or not at all.
        if let accountID = reply.accountID { environment.setActiveAccount(accountID) }
        IntentNavigation.enqueue(route(forTapOn: reply.statusID))
    }

    /// The cached copy where there is one, the server's otherwise: a
    /// notification can name a post that never reached a cached timeline.
    private static func status(_ id: String, session: AccountSession) async -> Status? {
        if let cached = try? await session.timelineStore.statuses(
            accountID: session.id, ids: [id])[id]
        {
            return cached
        }
        return try? await session.client.decode(Status.self, from: Endpoint.statuses.status(id))
    }

    private static func sendReply(
        _ typed: String, to status: Status, session: AccountSession
    ) async {
        let draft = replyDraft(
            typed: typed, to: status, viewerHandle: session.snapshot.handle,
            defaultVisibility: session.settings.defaultVisibility)
        do {
            let posted = try await session.client.decode(
                Status.self, from: Endpoint.composing.post(draft))
            session.notePosted(posted)
        } catch {
            logger.error(
                "lock-screen reply failed: \(String(describing: error), privacy: .public)")
            // What was typed on the lock screen exists nowhere else, so a
            // failure hands it back rather than dropping it.
            await raiseUnsentReply(draft.text, statusID: status.displayed.id, session: session)
        }
    }

    private static func raiseUnsentReply(
        _ text: String, statusID: String, session: AccountSession
    ) async {
        let content = UNMutableNotificationContent()
        content.title = String(
            localized: "Your reply wasn't sent", comment: "Notification title after a failed reply")
        content.body = text
        content.categoryIdentifier = "generic"
        content.userInfo = ["accountID": session.id.uuidString, "statusID": statusID]
        let request = UNNotificationRequest(
            identifier: "\(session.id.uuidString)-unsent-\(statusID)", content: content,
            trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
