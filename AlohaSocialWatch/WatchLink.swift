// SPDX-License-Identifier: MIT

import AlohaNetwork
import Foundation
import Observation
import WatchConnectivity

/// Receives the active account's credentials from the phone.
@MainActor
@Observable
final class WatchLink: NSObject {
    nonisolated struct Credentials: Codable, Sendable, Hashable {
        var accountID: UUID
        var apiBase: URL
        var token: String
        var handle: String
    }

    private(set) var credentials: Credentials?
    private(set) var client: APIClient?

    private let store = KeychainStore(service: "com.nextcloud.alohasocial.watch")

    override init() {
        super.init()
        restore()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func restore() {
        guard let raw = (try? store.get("credentials")) ?? nil,
            let data = raw.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(Credentials.self, from: data)
        else { return }
        adopt(decoded)
    }

    private func adopt(_ credentials: Credentials) {
        self.credentials = credentials
        self.client = APIClient(
            accountID: credentials.accountID,
            apiBase: credentials.apiBase,
            accessToken: credentials.token)
    }

    private func persist(_ credentials: Credentials) {
        guard let data = try? JSONEncoder().encode(credentials),
            let raw = String(data: data, encoding: .utf8)
        else { return }
        // Same accessibility class as the phone's: this device only, never
        // iCloud Keychain and never an encrypted backup onto another device.
        try? store.set(raw, for: "credentials")
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
        error: (any Error)?
    ) {}

    nonisolated func session(
        _ session: WCSession, didReceiveApplicationContext context: [String: Any]
    ) {
        guard let data = context["credentials"] as? Data,
            let decoded = try? JSONDecoder().decode(Credentials.self, from: data)
        else { return }

        Task { @MainActor in
            self.adopt(decoded)
            self.persist(decoded)
        }
    }
}
