// SPDX-License-Identifier: MIT

import Foundation

/// Decides what one draft sync does. Pure: the drafts here, the files there
/// and the ledger in; a list of steps out. `DraftSynchronizer` carries them
/// out (docs/14 §7).
///
/// The rules, in the order they matter:
///
/// 1. **Text is never lost silently.** Two devices that changed one draft
///    differently both keep their words: the newer version keeps the draft,
///    the older becomes a copy beside it, marked as such. An edit made on one
///    device after another deleted the draft brings it back.
/// 2. **Newest wins** where the two sides agree, or where only one changed.
/// 3. **Deletions travel** as tombstones, and are applied only to a draft
///    that has not changed since this device last synced it.
public enum DraftMerge {

    /// A tombstone older than this is cleared from the folder. A device
    /// that stays offline longer than this and still has the draft brings
    /// it back, which is the safe way round to be wrong.
    public static let tombstoneLifetime: TimeInterval = 60 * 24 * 60 * 60

    /// Times survive the trip through the file only to the millisecond.
    static func sameTime(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) < 0.001
    }

    /// One file in the folder, as the synchroniser found it.
    public struct Remote: Sendable, Hashable {
        public var etag: String?
        /// Nil when the file was not downloaded because its `ETag` is the
        /// one in the ledger: it is what this device last synced.
        public var file: DraftSyncFile?

        public init(etag: String?, file: DraftSyncFile?) {
            self.etag = etag
            self.file = file
        }
    }

    public enum Action: Sendable, Hashable {
        /// Write this draft here, if the local copy is still `expected`
        /// (nil: absent). `etag` is the file's, for the ledger.
        case saveLocal(DraftSnapshot, expected: Date?, etag: String?)
        /// Delete the draft here, if it is still `expected`, because of
        /// this tombstone.
        case deleteLocal(UUID, expected: Date, tombstone: DraftSyncFile, etag: String?)
        /// Write this file there.
        case upload(DraftSyncFile)
        /// Remove the file there: an expired tombstone.
        case removeRemote(UUID)
        /// Only the ledger changes — a new `ETag` for an unchanged draft,
        /// or an entry that no longer names anything.
        case remember(UUID, DraftSyncLedger.Entry?)
    }

    /// Everything done about one draft. The actions run in order and stop
    /// at the first that fails, so a conflict copy that could not be saved
    /// is never followed by overwriting the version it was copying.
    public struct Step: Sendable, Hashable {
        public var id: UUID
        public var actions: [Action]
    }

    /// The steps that bring this device and the folder into agreement.
    ///
    /// `excluding` names drafts to leave entirely alone this time: one open
    /// in a composer, whose save on closing would otherwise land on top of
    /// whatever sync wrote, and files in a format this build cannot write.
    public static func plan(
        local: [DraftSnapshot],
        remote: [UUID: Remote],
        ledger: DraftSyncLedger,
        accountID: UUID,
        now: Date,
        excluding: Set<UUID> = [],
        makeID: () -> UUID = UUID.init
    ) -> [Step] {
        let localByID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let ids = Set(localByID.keys).union(remote.keys).union(ledger.entries.keys)
            .subtracting(excluding)

        // Sorted, so the same inputs always make the same plan.
        return ids.sorted { $0.uuidString < $1.uuidString }.compactMap { id in
            let actions = decide(
                local: localByID[id], remote: remote[id], base: ledger.entries[id],
                id: id, accountID: accountID, now: now, makeID: makeID)
            return actions.isEmpty ? nil : Step(id: id, actions: actions)
        }
    }

    /// What the folder holds for one draft, with what the ledger knows
    /// filled in where the file was not downloaded.
    private enum RemoteState {
        case absent
        case unchanged(deleted: Bool, stamp: Date)
        case file(DraftSyncFile, etag: String?)
    }

    private static func decide(
        local: DraftSnapshot?, remote: Remote?, base: DraftSyncLedger.Entry?,
        id: UUID, accountID: UUID, now: Date, makeID: () -> UUID
    ) -> [Action] {
        let state: RemoteState
        if let remote {
            if let file = remote.file {
                state = .file(file, etag: remote.etag)
            } else if let base {
                state = .unchanged(deleted: base.deleted, stamp: base.stamp)
            } else {
                // Not downloaded and nothing known about it: the synchroniser
                // never does this, and a guess here could only do harm.
                return []
            }
        } else {
            state = .absent
        }

        let localChanged: Bool = {
            guard let local else { return false }
            guard let base, !base.deleted else { return true }
            return !sameTime(local.updatedAt, base.stamp)
        }()
        let isExpired = { (stamp: Date) in now.timeIntervalSince(stamp) > tombstoneLifetime }

        switch state {
        case .absent:
            // Nothing there: put this device's draft there — new, or a file
            // somebody removed by hand, which is not a deletion this device
            // can be sure was meant.
            if let local { return [.upload(DraftSyncFile(local))] }
            return base == nil ? [] : [.remember(id, nil)]

        case .unchanged(let deleted, let stamp):
            if let local {
                // Changed here, or back from a deletion: either way, here
                // is newer than there.
                return localChanged || deleted ? [.upload(DraftSyncFile(local))] : []
            }
            if deleted {
                return isExpired(stamp) ? [.removeRemote(id)] : []
            }
            // Gone here and untouched there: deleted on this device.
            return [.upload(.tombstone(id, deletedAt: now))]

        case .file(let file, let etag):
            let remoteChanged: Bool = {
                guard let base else { return true }
                return base.deleted != file.isTombstone || !sameTime(base.stamp, file.stamp)
            }()
            let unchangedEntry = DraftSyncLedger.Entry(
                stamp: file.stamp, deleted: file.isTombstone, etag: etag)

            if file.isTombstone {
                guard let local else {
                    if isExpired(file.stamp) { return [.removeRemote(id)] }
                    return base == unchangedEntry ? [] : [.remember(id, unchangedEntry)]
                }
                // Deleted there. Applied only to a draft untouched here since
                // the last sync; one edited since is brought back instead.
                if !localChanged {
                    return [
                        .deleteLocal(id, expected: local.updatedAt, tombstone: file, etag: etag)
                    ]
                }
                return [.upload(DraftSyncFile(local))]
            }

            guard let incoming = file.snapshot(accountID: accountID) else { return [] }

            guard let local else {
                // New there; or deleted here while it was edited there, and
                // an edit outweighs a deletion; or deleted here and untouched
                // there, which is a deletion to pass on.
                if let base, !base.deleted, !remoteChanged {
                    return [.upload(.tombstone(id, deletedAt: now))]
                }
                return [.saveLocal(incoming, expected: nil, etag: etag)]
            }

            switch (localChanged, remoteChanged) {
            case (false, false):
                return base == unchangedEntry ? [] : [.remember(id, unchangedEntry)]
            case (true, false):
                return [.upload(DraftSyncFile(local))]
            case (false, true):
                return [.saveLocal(incoming, expected: local.updatedAt, etag: etag)]
            case (true, true):
                return resolveConflict(
                    local: local, incoming: incoming, etag: etag, makeID: makeID)
            }
        }
    }

    /// Both sides changed the draft since they last agreed.
    private static func resolveConflict(
        local: DraftSnapshot, incoming: DraftSnapshot, etag: String?, makeID: () -> UUID
    ) -> [Action] {
        let localIsNewer = local.updatedAt >= incoming.updatedAt

        // The same words on both: nothing to choose between. The newer time
        // stands, so the other side does not see a change next time.
        if DraftSyncFile.Content(local) == DraftSyncFile.Content(incoming) {
            return localIsNewer
                ? [.upload(DraftSyncFile(local))]
                : [.saveLocal(incoming, expected: local.updatedAt, etag: etag)]
        }

        // Different words. The newer keeps the draft; the older is kept as
        // a copy beside it, here and there, so neither device loses what
        // was typed on it.
        var copy = localIsNewer ? incoming : local
        copy.id = makeID()
        // A fresh key: the two are different posts now, and sharing one
        // would let the server swallow whichever went second.
        copy.idempotencyKey = UUID().uuidString
        copy.isSyncConflictCopy = true
        copy.queuedForSend = false
        let keepCopy: [Action] = [
            .saveLocal(copy, expected: nil, etag: nil),
            .upload(DraftSyncFile(copy)),
        ]
        return keepCopy
            + (localIsNewer
                ? [.upload(DraftSyncFile(local))]
                : [.saveLocal(incoming, expected: local.updatedAt, etag: etag)])
    }
}
