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
    /// The canned answers offered above the reply field: the phone's list,
    /// or the built-in set until the phone sends one (docs/09 §4).
    private(set) var quickReplies: [String] = WatchQuickReplies.current()

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

    /// Activates the session at once: the app is launched in the background
    /// to receive the phone's pushes, and a session first activated by a
    /// view would leave them waiting until somebody opened the app.
    override init() {
        super.init()
        if let restored = store.load() { adopt(restored) }
        activate()
    }

    private func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// The `.watchConnectivity` background task: the system woke the app to
    /// deliver something from the phone, and suspends it again when the
    /// task returns — so it returns only once nothing is pending, and the
    /// delegate has had its turn to store what arrived. Bounded, because
    /// background time a watch grants is short and spent from a budget.
    func finishPendingTransfers() async {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while session.activationState != .activated || session.hasContentPending,
            ContinuousClock.now < deadline
        {
            try? await Task.sleep(for: .milliseconds(250))
        }
        // The delegate hands its work to the main actor; let it run before
        // the app is suspended.
        await Task.yield()
    }

    /// `refreshComplications`, unless the snapshot is only minutes old: the
    /// app comes to the front many times an hour, and the complications
    /// refresh on their own schedule besides.
    func refreshComplicationsIfDue() async {
        guard let accountID = credentials?.accountID,
            WatchComplicationSnapshot.appShouldRefresh(
                WatchComplicationSnapshot.load(for: accountID))
        else { return }
        await refreshComplications()
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

    /// The notifications list was seen: the server's marker moves to the
    /// newest of them, and the face's count follows. The count is asked of
    /// the server rather than set to zero — something may have arrived since
    /// the list loaded — unless the server cannot say, when what was just
    /// read is all the watch knows of.
    func markNotificationsRead(_ ids: [String]) async {
        guard let client, let accountID = credentials?.accountID else { return }
        let written: String?
        do {
            written = try await WatchNotificationMarker.markRead(ids, client: client)
        } catch {
            return
        }
        let count: Int
        if let fresh = try? await WatchComplicationRefresher.unreadCount(client: client) {
            count = fresh
        } else if written != nil {
            count = 0
        } else {
            return
        }
        apply(unread: count, conversations: nil, for: accountID)
    }

    private func adopt(_ credentials: Credentials) {
        // Another account's counts must not stay on the face for the
        // quarter-hour until the next refresh. Not at launch, where there is
        // no previous account: that would wipe the face on every start.
        if let previous = self.credentials?.accountID, previous != credentials.accountID {
            WatchComplicationSnapshot.clear()
            WidgetCenter.shared.reloadAllTimelines()
            // The lists would not show another account's posts anyway (each
            // file names its account), but they need not stay on the watch.
            WatchCache.clear()
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
        WatchCache.clear()
        WatchComplicationSnapshot.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The phone's list, or with nil the built-in set: the phone sends no
    /// list until somebody edits one.
    private func adopt(quickReplies phrases: [String]?) {
        WatchQuickReplies.store(phrases)
        quickReplies = WatchQuickReplies.current()
    }

    /// The count the phone just polled. Only for the paired account, and
    /// only onto a snapshot that exists or a fresh one: the mentions keep
    /// the age they had.
    private func apply(unread count: Int, conversations: Int?, for accountID: UUID) {
        guard credentials?.accountID == accountID else { return }
        let current =
            WatchComplicationSnapshot.load(for: accountID)
            ?? WatchComplicationSnapshot(
                accountID: accountID, unreadCount: nil, mentions: [],
                updatedAt: .distantPast)
        current.applying(unreadCount: count, conversations: conversations).save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension WatchLink: WCSessionDelegate {
    /// The quick replies from the context the phone last sent: one that
    /// arrived while the app was not running is delivered only as
    /// `receivedApplicationContext`. Not the credentials — a context never
    /// received is empty too, and that must not read as "forget the account".
    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard state == .activated else { return }
        let context = session.receivedApplicationContext
        guard !context.isEmpty else { return }
        let phrases = WatchQuickReplies.phrases(in: context)
        Task { @MainActor in self.adopt(quickReplies: phrases) }
    }

    nonisolated func session(
        _ session: WCSession, didReceiveApplicationContext context: [String: Any]
    ) {
        let phrases = WatchQuickReplies.phrases(in: context)
        Task { @MainActor in self.adopt(quickReplies: phrases) }

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
    /// count, and the unread conversations where the phone knows them, so
    /// the face moves when the phone's badges do.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let update = WatchComplicationSnapshot.unreadUpdate(from: userInfo) else { return }
        Task { @MainActor in
            self.apply(
                unread: update.count, conversations: update.conversations, for: update.accountID)
        }
    }
}
