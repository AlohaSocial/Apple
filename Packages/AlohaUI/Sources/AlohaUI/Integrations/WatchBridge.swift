// SPDX-License-Identifier: MIT

import AlohaNetwork
import Foundation

#if os(iOS)
    import WatchConnectivity

    /// The phone's half of the watch link: it sends the active account, and
    /// its server's colour, as the application context (docs/09 §4).
    ///
    /// Application context rather than a message, because it is state, not an
    /// event: the system keeps only the latest and delivers it when the watch
    /// next wakes, so a switch made while the watch is off still arrives.
    @MainActor
    public final class WatchBridge: NSObject {
        public static let shared = WatchBridge()

        private var latest: WatchPairing?
        private var hasSent = false
        private var isActivated = false
        /// The last count handed to the complication, per account, so a poll
        /// that found nothing new spends none of the daily transfer budget.
        private var lastSentUnread: (accountID: UUID, count: Int)?

        public func activate() {
            guard WCSession.isSupported(), !isActivated else { return }
            isActivated = true
            WCSession.default.delegate = self
            WCSession.default.activate()
        }

        /// `nil` when there is no account, which tells the watch to forget it.
        public func send(_ pairing: WatchPairing?) {
            guard pairing != latest || !hasSent else { return }
            latest = pairing
            push()
        }

        /// The paired account's unread count, for the watch's complications.
        ///
        /// `transferCurrentComplicationUserInfo` is the one transfer that
        /// wakes the watch for a complication, and watchOS grants it about
        /// fifty times a day — so it goes only while a complication is on the
        /// face, only when the count moved, and never past the budget.
        public func sendUnread(_ counts: [UUID: Int]) {
            guard WCSession.isSupported(), let accountID = latest?.accountID,
                let count = counts[accountID]
            else { return }
            if let last = lastSentUnread, last.accountID == accountID, last.count == count {
                return
            }
            let session = WCSession.default
            guard session.activationState == .activated, session.isPaired,
                session.isWatchAppInstalled, session.isComplicationEnabled,
                session.remainingComplicationUserInfoTransfers > 0
            else { return }
            session.transferCurrentComplicationUserInfo(
                WatchComplicationSnapshot.unreadUserInfo(accountID: accountID, count: count))
            lastSentUnread = (accountID, count)
        }

        private func push() {
            guard WCSession.isSupported() else { return }
            let session = WCSession.default
            guard session.activationState == .activated, session.isPaired,
                session.isWatchAppInstalled
            else { return }

            var context: [String: Any] = [:]
            if let latest, let data = try? JSONEncoder().encode(latest) {
                context[WatchPairing.contextKey] = data
            }
            do {
                try session.updateApplicationContext(context)
                hasSent = true
            } catch {
                hasSent = false
            }
        }
    }

    extension WatchBridge: WCSessionDelegate {
        nonisolated public func session(
            _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
            error: (any Error)?
        ) {
            Task { @MainActor in self.push() }
        }

        /// The watch app being installed after the account was chosen is the
        /// common first-run order, so that is a reason to send again.
        nonisolated public func sessionWatchStateDidChange(_ session: WCSession) {
            Task { @MainActor in self.push() }
        }

        nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}

        /// Switching to another paired watch deactivates the session; the next
        /// one needs activating before it can be sent anything.
        nonisolated public func sessionDidDeactivate(_ session: WCSession) {
            WCSession.default.activate()
        }
    }
#endif
