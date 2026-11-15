// SPDX-License-Identifier: MIT

import AlohaNetwork
import AlohaStore
import Foundation
import OSLog
import Observation

/// Keeps each account's drafts in step with its own Nextcloud, where the
/// person has connected one and left the switch on (docs/14 §7).
///
/// Syncs when the app comes to the front, in the background refresh, and a
/// moment after a draft is saved or deleted — the moment, so a composer
/// that saves on every pause is one sync and not ten. The merge itself is
/// `DraftMerge`; this decides when, with which credentials, and says how it
/// went.
@MainActor
@Observable
public final class DraftSync {
    public static let shared = DraftSync()

    /// How the last sync of one account went, for Settings and Drafts.
    public struct State: Sendable, Hashable {
        public var lastSyncedAt: Date?
        public var lastError: String?
        public var isSyncing = false
        /// Moves on whenever sync wrote or deleted a draft here, so an open
        /// Drafts list knows to read again.
        public var revision = 0
    }

    public private(set) var states: [UUID: State] = [:]

    public func state(for accountID: UUID) -> State {
        states[accountID] ?? State()
    }

    @ObservationIgnored private weak var environment: AppEnvironment?
    @ObservationIgnored private var running: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var scheduled: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var openDrafts: [OpenDraft] = []
    private let logger = Logger(subsystem: "social.aloha.app", category: "draftsync")

    /// A draft on screen in a composer, held weakly by the composer that has
    /// it, so a composer that goes away stops holding it without being told.
    private struct OpenDraft {
        weak var owner: AnyObject?
        let id: UUID
    }

    private init() {}

    /// Called once the environment has its accounts: from here on a draft
    /// saved or deleted anywhere in the app is followed by a sync.
    public func attach(to environment: AppEnvironment) async {
        guard self.environment !== environment else { return }
        self.environment = environment
        await environment.support.onDraftsChanged { accountID in
            Task { @MainActor in DraftSync.shared.scheduleSync(accountID: accountID) }
        }
    }

    /// Whether this account's drafts sync at all.
    public func isEnabled(for session: AccountSession) -> Bool {
        session.hasNextcloudConnection && session.settings.syncsDraftsThroughNextcloud
            && !session.needsReauthentication
    }

    /// A composer has this draft on screen. Sync leaves it alone until the
    /// composer is gone: the composer saves what it shows when it closes,
    /// and that save would land on top of anything sync wrote meanwhile.
    public func noteOpen(_ draftID: UUID, by owner: AnyObject) {
        openDrafts.removeAll { $0.owner == nil || $0.owner === owner }
        openDrafts.append(OpenDraft(owner: owner, id: draftID))
    }

    private var openDraftIDs: Set<UUID> {
        Set(openDrafts.filter { $0.owner != nil }.map(\.id))
    }

    // MARK: - When

    /// Every account that syncs, one after another. `ifOlderThan` skips an
    /// account synced more recently than that — coming back to the app
    /// twice in a minute need not ask twice.
    public func syncAll(ifOlderThan interval: TimeInterval = 0) async {
        guard let environment else { return }
        for session in environment.sessions where isEnabled(for: session) {
            guard !Task.isCancelled else { return }
            if let last = state(for: session.id).lastSyncedAt,
                Date().timeIntervalSince(last) < interval
            {
                continue
            }
            await sync(session)
        }
    }

    /// The same, giving up when `budget` runs out: what the background
    /// refresh can spare (docs/12 §8).
    public func syncAll(ifOlderThan interval: TimeInterval, within budget: Duration) async {
        let work = Task { await syncAll(ifOlderThan: interval) }
        let deadline = Task {
            try? await Task.sleep(for: budget)
            work.cancel()
        }
        await work.value
        deadline.cancel()
    }

    /// A short while after a save or a deletion, so a burst of saves is one
    /// sync. One already under way read the drafts before this change, so
    /// this one waits for it and then runs again.
    func scheduleSync(accountID: UUID) {
        scheduled[accountID]?.cancel()
        scheduled[accountID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            while let current = self.running[accountID] { await current.value }
            guard let session = self.environment?.sessions.first(where: { $0.id == accountID }),
                self.isEnabled(for: session)
            else { return }
            await self.sync(session)
        }
    }

    /// One sync of one account, or the one already running.
    public func sync(_ session: AccountSession) async {
        if let current = running[session.id] {
            await current.value
            return
        }
        let task = Task { await perform(session) }
        running[session.id] = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        running[session.id] = nil
    }

    // MARK: - How

    private func perform(_ session: AccountSession) async {
        guard isEnabled(for: session), let environment,
            let credentials = (try? environment.credentials.nextcloudCredentials(for: session.id))
                ?? nil
        else { return }

        let id = session.id
        var state = self.state(for: id)
        state.isSyncing = true
        states[id] = state

        let folder = WebDAVDraftFolder(
            client: WebDAVClient(credentials: credentials, transport: environment.transport))
        let synchroniser = DraftSynchronizer(folder: folder, store: session.supportStore)
        let ledger = DraftSyncLedgerStore.ledger(for: id, in: AppGroup.defaults)

        do {
            let outcome = try await synchroniser.sync(
                accountID: id, ledger: ledger, excluding: openDraftIDs)
            DraftSyncLedgerStore.save(outcome.ledger, for: id, in: AppGroup.defaults)
            state.lastSyncedAt = outcome.ledger.lastSyncedAt
            state.lastError =
                outcome.failures > 0
                ? String(
                    localized: "Some drafts couldn't be synced. They'll be tried again.",
                    comment: "Draft sync partly failed")
                : nil
            if outcome.changedLocally { state.revision += 1 }
            if outcome.conflicts > 0 {
                logger.notice("draft sync kept \(outcome.conflicts, privacy: .public) conflict copies")
            }
        } catch WebDAVClient.WebDAVError.unauthorised {
            state.lastError = String(
                localized: "Your Nextcloud connection has expired. Reconnect it in Settings.",
                comment: "WebDAV auth failure")
        } catch is CancellationError {
            // Out of time in the background; the next sync carries on.
        } catch APIError.cancelled {
            // The same, from the transport.
        } catch {
            logger.error("draft sync failed: \(String(describing: error), privacy: .private)")
            state.lastError = String(
                localized: "Drafts couldn't be synced with your Nextcloud. They'll be tried again.",
                comment: "Draft sync failed")
        }
        state.isSyncing = false
        states[id] = state
    }

    /// Forgets an account's sync state with the account.
    func forget(_ accountID: UUID) {
        scheduled[accountID]?.cancel()
        scheduled[accountID] = nil
        running[accountID]?.cancel()
        states[accountID] = nil
    }
}
