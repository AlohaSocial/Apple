// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import Foundation
import OSLog

/// Subscribes an account to Web Push where its server offers it.
///
/// On Nextcloud Social this does nothing at all: `vapid_key` is an empty
/// string, and the capability that reads it is false. That is the server saying
/// "do not offer this", and honouring it is the difference between an app that
/// waits for a push that never comes and one that polls (docs/08 §2).
public struct PushRegistrar: Sendable {
    private let credentials: CredentialStore
    private let logger = Logger(subsystem: "com.nextcloud.alohasocial", category: "push")

    public init(credentials: CredentialStore) {
        self.credentials = credentials
    }

    private static func keyAccount(_ accountID: UUID) -> String {
        "push-keys-\(accountID.uuidString)"
    }

    public func keys(for accountID: UUID) -> WebPushKeys? {
        guard let raw = (try? credentials.pushKeys(for: accountID)) ?? nil,
            let data = raw.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(WebPushKeys.self, from: data)
    }

    @discardableResult
    public func subscribe(
        session: AccountSession, deviceToken: Data,
        preferences: WebPushPreferences = WebPushPreferences()
    ) async -> Bool {
        guard session.capabilities.webPushVAPIDKey?.isEmpty == false else { return false }

        let keys = keys(for: session.id) ?? WebPushKeys.generate()
        if let data = try? JSONEncoder().encode(keys),
            let raw = String(data: data, encoding: .utf8)
        {
            try? credentials.setPushKeys(raw, for: session.id)
        }

        // The relay address the server pushes to. A real deployment needs a
        // relay that speaks Web Push and forwards to APNs, because Mastodon
        // servers do not speak APNs themselves.
        let endpoint = "https://push.alohasocial.invalid/\(deviceToken.hexString)"

        do {
            _ = try await session.client.send(
                Endpoint.push.subscribe(
                    endpoint: endpoint, keys: keys, preferences: preferences))
            logger.info("web push subscription created")
            return true
        } catch APIError.notFound {
            // The normal case on a server without Web Push.
            logger.debug("server has no web push endpoint; polling continues")
            return false
        } catch {
            await session.handle(error)
            return false
        }
    }

    public func unsubscribe(session: AccountSession) async {
        _ = try? await session.client.send(Endpoint.push.unsubscribe)
        try? credentials.removePushKeys(for: session.id)
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
