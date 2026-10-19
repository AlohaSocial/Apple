// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaNetwork
import Foundation
import Observation
import WatchConnectivity
import WidgetKit

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

    /// The shared Keychain group, so the complications can read the token
    /// too (`WatchPairingStore` moves an older build's private copy over).
    private let store = WatchPairingStore()

    override init() {
        super.init()
        if let restored = store.load() { adopt(restored) }
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Asks the server for what the complications show and hands it to them.
    /// Called when the app comes to the front: the one moment the watch is
    /// certainly awake, on Wi-Fi or the phone's connection, and being looked at.
    func refreshComplications() async {
        guard let client, let accountID = credentials?.accountID else { return }
        let parser = StatusHTMLParser()
        guard
            let fresh = try? await WatchComplicationRefresher.fetch(
                client: client, accountID: accountID,
                plainText: { parser.plainText($0) })
        else { return }
        // The phone may have switched account while the request was out.
        guard credentials?.accountID == accountID else { return }
        fresh.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func adopt(_ credentials: Credentials) {
        // Another account's counts must not stay on the face for the
        // quarter-hour until the next refresh. Not at launch, where there is
        // no previous account: that would wipe the face on every start.
        if let previous = self.credentials?.accountID, previous != credentials.accountID {
            WatchComplicationSnapshot.clear()
            WidgetCenter.shared.reloadAllTimelines()
        }
        self.credentials = credentials
        self.client = APIClient(
            accountID: credentials.accountID,
            apiBase: credentials.apiBase,
            accessToken: credentials.token)
    }

    private func forget() {
        credentials = nil
        client = nil
        store.remove()
        WatchComplicationSnapshot.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The count the phone just polled. Only for the paired account, and
    /// only onto a snapshot that exists or a fresh one: the mentions keep
    /// the age they had.
    private func apply(unread count: Int, for accountID: UUID) {
        guard credentials?.accountID == accountID else { return }
        let current =
            WatchComplicationSnapshot.load(for: accountID)
            ?? WatchComplicationSnapshot(
                accountID: accountID, unreadCount: nil, mentions: [],
                updatedAt: .distantPast)
        current.applying(unreadCount: count).save()
        WidgetCenter.shared.reloadAllTimelines()
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
            self.store.save(decoded)
        }
    }

    /// `transferCurrentComplicationUserInfo` from the phone: the unread
    /// count, so the face moves when the phone's badge does.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let update = WatchComplicationSnapshot.unreadUpdate(from: userInfo) else { return }
        Task { @MainActor in self.apply(unread: update.count, for: update.accountID) }
    }
}
