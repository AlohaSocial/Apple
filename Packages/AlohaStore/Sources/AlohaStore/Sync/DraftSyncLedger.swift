// SPDX-License-Identifier: MIT

import Foundation

/// What this device last agreed with the Nextcloud about, draft by draft.
///
/// The merge is three-way: a draft has changed *here* when it differs from
/// its entry, and changed *there* when the file does. Without the entry a
/// deletion on this device would look like a draft that was never uploaded,
/// and an edit on one side could not be told from an edit on both.
public struct DraftSyncLedger: Codable, Sendable, Hashable {
    public struct Entry: Codable, Sendable, Hashable {
        /// The `updatedAt` both sides had — or for a tombstone, its
        /// `deletedAt`.
        public var stamp: Date
        public var deleted: Bool
        /// The file's `ETag` as last seen, so an unchanged file is not
        /// downloaded again. Nil when the server did not say, which costs
        /// one download next time and nothing else.
        public var etag: String?

        public init(stamp: Date, deleted: Bool, etag: String?) {
            self.stamp = stamp
            self.deleted = deleted
            self.etag = etag
        }
    }

    public var entries: [UUID: Entry]
    public var lastSyncedAt: Date?

    public init(entries: [UUID: Entry] = [:], lastSyncedAt: Date? = nil) {
        self.entries = entries
        self.lastSyncedAt = lastSyncedAt
    }
}

/// Keeps each account's ledger, in the app group's defaults beside the rest
/// of what an account leaves outside the store (`AccountTeardown` removes
/// it with the account).
public enum DraftSyncLedgerStore {
    public static func key(for accountID: UUID) -> String {
        "aloha.draftSync.\(accountID.uuidString)"
    }

    /// An unreadable ledger is an empty one: every draft is then compared
    /// by content, which costs a conflict copy at worst and never a draft.
    public static func ledger(for accountID: UUID, in defaults: UserDefaults) -> DraftSyncLedger {
        guard let data = defaults.data(forKey: key(for: accountID)),
            let ledger = try? JSONDecoder().decode(DraftSyncLedger.self, from: data)
        else { return DraftSyncLedger() }
        return ledger
    }

    public static func save(
        _ ledger: DraftSyncLedger, for accountID: UUID, in defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: key(for: accountID))
    }

    public static func remove(for accountID: UUID, in defaults: UserDefaults) {
        defaults.removeObject(forKey: key(for: accountID))
    }
}
