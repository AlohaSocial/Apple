// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation
import UserNotifications

/// Decrypts a push from Nextcloud's proxy.
///
/// The proxy delivers a `subject` that is RSA-encrypted to this device's public
/// key. Without decrypting it the notification reads "New activity" and nothing
/// else; with it, the person sees who did what (docs/08 §6).
///
/// Follows the shape of `nextcloud/ios`'s own service extension: try each
/// account's key until one decrypts, because a device may hold several.
/// `@unchecked Sendable` with intent: the system creates one instance per push,
/// calls `didReceive` once and `serviceExtensionTimeWillExpire` at most once
/// after it, and tears the instance down. There is no concurrent access to
/// guard — the API simply predates `Sendable`.
final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttempt = request.content.mutableCopy() as? UNMutableNotificationContent

        // The copy is kept on `self` for `deliver()` to finish; this only has
        // to know whether making it worked.
        guard bestAttempt != nil else {
            contentHandler(request.content)
            return
        }

        guard let subject = request.content.userInfo["subject"] as? String else {
            deliver()
            return
        }

        // The mutable content cannot cross into the task, so the work answers
        // a value and the content is written back here.
        Task { [weak self] in
            let resolved = await Self.resolve(subject: subject)
            self?.apply(resolved)
        }
    }

    private func apply(_ resolved: Resolved?) {
        guard let bestAttempt else { return }
        if let resolved, resolved.isWithdrawal {
            // Nothing to show: an alert with no title and no body is not
            // presented.
            bestAttempt.title = ""
            bestAttempt.body = ""
        } else if let resolved {
            bestAttempt.title = resolved.title
            bestAttempt.body = resolved.body
            if let subtitle = resolved.subtitle { bestAttempt.subtitle = subtitle }
            // The same labels a local alert gets (`NotificationAlert`): the
            // category carries Reply, Favourite and Boost, the thread groups
            // a conversation, the account is what a Focus filters on, and the
            // status id is what a tap opens.
            bestAttempt.categoryIdentifier = NotificationAlert.category(for: resolved.kind)
            bestAttempt.interruptionLevel =
                NotificationAlert.isActive(resolved.kind) ? .active : .passive
            bestAttempt.sound = NotificationAlert.isActive(resolved.kind) ? .default : nil
            bestAttempt.threadIdentifier = NotificationAlert.threadIdentifier(
                statusID: resolved.statusID, notificationID: resolved.notificationID)
            bestAttempt.filterCriteria = resolved.accountID.uuidString
            for (key, value) in NotificationAlert.userInfo(
                accountID: resolved.accountID, statusID: resolved.statusID,
                notificationID: resolved.notificationID)
            {
                bestAttempt.userInfo[key] = value
            }
            if let nid = resolved.nextcloudID {
                bestAttempt.userInfo[NotificationAlert.nextcloudNotificationIDKey] = nid
            }
        }
        deliver()
    }

    struct Resolved: Sendable {
        var title: String
        var body: String
        var subtitle: String?
        var accountID: UUID
        /// The Nextcloud notification, which a withdrawal names later.
        var nextcloudID: Int?
        /// The Mastodon notification this push is about, when it could be
        /// found; otherwise the Nextcloud one's id, so the thread and the
        /// userInfo still have something to hold.
        var notificationID: String
        var statusID: String?
        var kind: NotificationKind?
        var isWithdrawal = false
    }

    /// The system gives an extension a few seconds; whatever has been worked
    /// out by then is what is shown.
    override func serviceExtensionTimeWillExpire() {
        deliver()
    }

    private func deliver() {
        guard let contentHandler, let bestAttempt else { return }
        self.contentHandler = nil
        contentHandler(bestAttempt)
    }

    /// Tries each account's key in turn: a device may hold several, and only
    /// the one this push was encrypted to will decrypt it.
    private static func resolve(subject: String) async -> Resolved? {
        let credentials = CredentialStore.shared
        // Read-only: the push can arrive before the first unlock, and a
        // service extension is the last process that should touch the file.
        let accounts = AccountStore(modelContainer: StoreContainer.reader())

        guard let snapshots = try? await accounts.allAccounts() else { return nil }

        for snapshot in snapshots {
            guard let raw = (try? credentials.pushKeys(for: snapshot.id)) ?? nil,
                let data = raw.data(using: .utf8),
                let keys = try? JSONDecoder().decode(NextcloudPushKeys.self, from: data),
                let plaintext = try? keys.decrypt(subject: subject),
                let payload = try? JSONDecoder().decode(
                    NextcloudPushPayload.self, from: plaintext)
            else { continue }

            // A withdrawal tells the client to take a notification back down
            // rather than to show anything.
            if payload.isWithdrawal {
                await withdraw(payload, for: snapshot.id)
                return Resolved(
                    title: "", body: "", subtitle: nil, accountID: snapshot.id,
                    nextcloudID: nil, notificationID: "", statusID: nil, kind: nil,
                    isWithdrawal: true)
            }

            var resolved = Resolved(
                title: payload.subject ?? "",
                body: "",
                subtitle: snapshots.count > 1 ? snapshot.qualifiedHandle : nil,
                accountID: snapshot.id,
                nextcloudID: payload.nid,
                notificationID: payload.nid.map { "nc-\($0)" } ?? UUID().uuidString,
                statusID: nil,
                kind: nil)
            // Nextcloud's push says what happened in a sentence and nothing
            // more. For Social's own notifications the post it is about is
            // asked of Social, so the alert carries its text and opens it.
            if payload.app == nil || payload.app == "social",
                let found = await latestNotification(for: snapshot)
            {
                resolved.notificationID = found.id
                resolved.kind = found.type
                if let decoded = NotificationPayload.decode(NotificationPayload.encode(found)) {
                    resolved.body = decoded.body
                    resolved.statusID = decoded.statusID
                    if resolved.title.isEmpty { resolved.title = decoded.title }
                }
                NotificationAlert.notePushAnnounced(found.id, accountID: snapshot.id)
            }
            return resolved
        }
        return nil
    }

    /// How old the newest notification may be and still be taken as the one
    /// this push announces. A push arrives within seconds of the event; a
    /// notification older than this is one the person has already been told
    /// about, and labelling the push with it would show the wrong post.
    static let matchWindow: TimeInterval = 120

    /// The account's newest notification, if it is recent enough to be what
    /// this push is about.
    ///
    /// One small request with the token the app left in the shared Keychain
    /// group, and no store writes: the extension's memory and seconds are
    /// short, and nothing here is worth failing the alert over. Without a
    /// match the alert keeps Nextcloud's sentence and opens the list.
    private static func latestNotification(
        for snapshot: AccountStore.Snapshot
    ) async -> MastodonNotification? {
        guard let token = (try? CredentialStore.shared.token(for: snapshot.id)) ?? nil else {
            return nil
        }
        let client = APIClient(
            accountID: snapshot.id, apiBase: snapshot.capabilities.apiBase, accessToken: token)
        guard
            let page = try? await client.decode(
                LossyArray<MastodonNotification>.self,
                from: Endpoint.notifications.flat(limit: 1)),
            let newest = page.elements.first,
            Date().timeIntervalSince(newest.createdAt) < matchWindow
        else { return nil }
        return newest
    }

    /// Takes down what the push being withdrawn put up.
    ///
    /// APNs, not this extension, names a delivered push, so its identifier
    /// is not something that can be worked out here. What the extension did
    /// write is the Nextcloud id in the alert's userInfo, and that is what a
    /// withdrawal is matched on — only within the account it is for.
    private static func withdraw(_ payload: NextcloudPushPayload, for accountID: UUID) async {
        let centre = UNUserNotificationCenter.current()
        let account = accountID.uuidString
        let deleteAll = payload.deleteAll == true
        let nid = payload.nid
        let identifiers: [String] = await withCheckedContinuation { continuation in
            centre.getDeliveredNotifications { delivered in
                let matching = delivered.filter { notification in
                    let info = notification.request.content.userInfo
                    guard info[NotificationAlert.accountIDKey] as? String == account,
                        let pushed = info[NotificationAlert.nextcloudNotificationIDKey] as? Int
                    else { return false }
                    return deleteAll || pushed == nid
                }
                continuation.resume(returning: matching.map(\.request.identifier))
            }
        }
        guard !identifiers.isEmpty else { return }
        centre.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
