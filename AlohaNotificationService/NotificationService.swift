// SPDX-License-Identifier: MIT

import AlohaNetwork
import AlohaStore
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
        if let resolved {
            bestAttempt.title = resolved.title
            bestAttempt.body = resolved.body
            if let subtitle = resolved.subtitle { bestAttempt.subtitle = subtitle }
            bestAttempt.userInfo["accountID"] = resolved.accountID
            if let nid = resolved.notificationID {
                bestAttempt.userInfo["nextcloudNotificationID"] = nid
            }
        }
        deliver()
    }

    struct Resolved: Sendable {
        var title: String
        var body: String
        var subtitle: String?
        var accountID: String
        var notificationID: Int?
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
        let accounts = AccountStore(modelContainer: StoreContainer.make())

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
                withdraw(payload, for: snapshot.id)
                return Resolved(
                    title: "", body: "", subtitle: nil,
                    accountID: snapshot.id.uuidString, notificationID: nil)
            }

            return Resolved(
                title: payload.subject ?? "",
                body: "",
                subtitle: snapshots.count > 1 ? snapshot.qualifiedHandle : nil,
                accountID: snapshot.id.uuidString,
                notificationID: payload.nid)
        }
        return nil
    }

    private static func withdraw(_ payload: NextcloudPushPayload, for accountID: UUID) {
        let centre = UNUserNotificationCenter.current()
        if payload.deleteAll == true {
            centre.removeAllDeliveredNotifications()
            return
        }
        if let nid = payload.nid {
            centre.removeDeliveredNotifications(
                withIdentifiers: ["\(accountID.uuidString)-nc-\(nid)"])
        }
    }
}
