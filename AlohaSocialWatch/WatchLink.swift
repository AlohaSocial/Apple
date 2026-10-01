// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaNetwork
import Foundation
import Observation
import WatchConnectivity

/// Receives the active account's credentials from the phone.
@MainActor
@Observable
final class WatchLink: NSObject {
    typealias Credentials = WatchPairing

    private(set) var credentials: Credentials?
    private(set) var client: APIClient?

    /// The colour of the account's server, as the phone resolved it.
    var serverTheme: AlohaThemeModifier.ServerTheme? {
        guard let credentials,
            credentials.accentBrightHex != nil || credentials.accentDarkHex != nil
        else { return nil }
        return AlohaThemeModifier.ServerTheme(
            brightHex: credentials.accentBrightHex, darkHex: credentials.accentDarkHex,
            textHex: credentials.accentTextHex)
    }

    private let store = KeychainStore(service: "social.aloha.app.watch")

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

    private func forget() {
        credentials = nil
        client = nil
        try? store.remove("credentials")
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
        // An empty context is the phone saying it has no account any more.
        guard let data = context[WatchPairing.contextKey] as? Data else {
            Task { @MainActor in self.forget() }
            return
        }
        guard let decoded = try? JSONDecoder().decode(Credentials.self, from: data) else { return }

        Task { @MainActor in
            self.adopt(decoded)
            self.persist(decoded)
        }
    }
}
