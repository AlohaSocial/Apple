// SPDX-License-Identifier: MIT

import AlohaNetwork
import Foundation
import OSLog

/// Where synced drafts are kept. A protocol so the merge can be exercised end
/// to end against a folder in memory; `WebDAVDraftFolder` is the real one.
public protocol DraftSyncFolder: Sendable {
    /// Every draft file there, by id, with its `ETag`. An absent folder is
    /// an empty one, created on the way.
    func list() async throws -> [UUID: String?]
    func read(_ id: UUID) async throws -> Data
    /// Answers the new `ETag`, when the server gives one.
    func write(_ data: Data, for id: UUID) async throws -> String?
    func remove(_ id: UUID) async throws
}

/// `Aloha Social/Drafts/` in the account's own Nextcloud Files.
public struct WebDAVDraftFolder: DraftSyncFolder {
    public static let path = "Aloha Social/Drafts"

    private let client: WebDAVClient

    public init(client: WebDAVClient) {
        self.client = client
    }

    public func list() async throws -> [UUID: String?] {
        let files: [NextcloudFile]
        do {
            files = try await client.list(path: Self.path)
        } catch WebDAVClient.WebDAVError.notFound {
            try await client.createFolder(path: Self.path)
            return [:]
        }
        var result: [UUID: String?] = [:]
        for file in files where !file.isDirectory {
            // Anything else in the folder — a note the person left, a file
            // from a later build — is not this sync's to touch.
            guard let id = DraftSyncFile.id(fromFileName: file.name) else { continue }
            result[id] = file.etag
        }
        return result
    }

    public func read(_ id: UUID) async throws -> Data {
        try await client.download(path: filePath(id))
    }

    public func write(_ data: Data, for id: UUID) async throws -> String? {
        try await client.upload(data, to: filePath(id), contentType: "application/json")
    }

    public func remove(_ id: UUID) async throws {
        try await client.delete(path: filePath(id))
    }

    private func filePath(_ id: UUID) -> String {
        "\(Self.path)/\(DraftSyncFile.fileName(for: id))"
    }
}

/// Carries out one sync of one account's drafts: lists the folder, downloads
/// what changed, asks `DraftMerge` what to do, and does it (docs/14 §7).
public struct DraftSynchronizer: Sendable {
    public struct Outcome: Sendable, Hashable {
        /// The ledger to keep. Advanced only for what was actually done, so
        /// a step that failed is simply tried again next time.
        public var ledger: DraftSyncLedger
        /// Whether any draft here was written or deleted — what tells an
        /// open Drafts list to read again.
        public var changedLocally: Bool
        /// Conflict copies made this time.
        public var conflicts: Int
        /// Steps that did not complete; tried again next time.
        public var failures: Int
    }

    private let folder: any DraftSyncFolder
    private let store: SupportStore
    private let logger = Logger(subsystem: "social.aloha.app", category: "draftsync")

    public init(folder: any DraftSyncFolder, store: SupportStore) {
        self.folder = folder
        self.store = store
    }

    public func sync(
        accountID: UUID, ledger: DraftSyncLedger, excluding: Set<UUID> = [], now: Date = Date()
    ) async throws -> Outcome {
        let listing = try await folder.list()

        var remote: [UUID: DraftMerge.Remote] = [:]
        var skipped = excluding
        for (id, etag) in listing {
            try Task.checkCancellation()
            if let etag, let known = ledger.entries[id]?.etag, known == etag {
                remote[id] = DraftMerge.Remote(etag: etag, file: nil)
                continue
            }
            do {
                let file = try DraftSyncFile.decode(try await folder.read(id))
                guard file.format <= DraftSyncFile.currentFormat, file.id == id else {
                    skipped.insert(id)
                    continue
                }
                remote[id] = DraftMerge.Remote(etag: etag, file: file)
            } catch let error as WebDAVClient.WebDAVError {
                throw error
            } catch {
                // A file that will not read is left as it is rather than
                // written over: it may be a later build's, or a person's
                // hand edit, and either is theirs.
                logger.error("a synced draft file could not be read; leaving it")
                skipped.insert(id)
            }
        }

        let local = try await store.drafts(accountID: accountID)
        let steps = DraftMerge.plan(
            local: local, remote: remote, ledger: ledger, accountID: accountID, now: now,
            excluding: skipped)

        var outcome = Outcome(ledger: ledger, changedLocally: false, conflicts: 0, failures: 0)
        for step in steps {
            try Task.checkCancellation()
            if step.actions.contains(where: Self.isConflictCopy) { outcome.conflicts += 1 }
            for action in step.actions {
                guard await perform(action, into: &outcome) else {
                    outcome.failures += 1
                    break
                }
            }
        }
        outcome.ledger.lastSyncedAt = now
        return outcome
    }

    private static func isConflictCopy(_ action: DraftMerge.Action) -> Bool {
        if case .saveLocal(let draft, _, _) = action { return draft.isSyncConflictCopy }
        return false
    }

    /// Does one action and records it in the ledger. False when it could
    /// not be done, which ends its step.
    private func perform(_ action: DraftMerge.Action, into outcome: inout Outcome) async -> Bool {
        do {
            switch action {
            case .saveLocal(let draft, let expected, let etag):
                guard try await store.applySyncedDraft(draft, expected: expected) else {
                    return false
                }
                outcome.changedLocally = true
                outcome.ledger.entries[draft.id] = DraftSyncLedger.Entry(
                    stamp: draft.updatedAt, deleted: false, etag: etag)

            case .deleteLocal(let id, let expected, let tombstone, let etag):
                guard try await store.deleteSyncedDraft(id: id, expected: expected) else {
                    return false
                }
                outcome.changedLocally = true
                outcome.ledger.entries[id] = DraftSyncLedger.Entry(
                    stamp: tombstone.stamp, deleted: true, etag: etag)

            case .upload(let file):
                let etag = try await folder.write(try file.encoded(), for: file.id)
                outcome.ledger.entries[file.id] = DraftSyncLedger.Entry(
                    stamp: file.stamp, deleted: file.isTombstone, etag: etag)

            case .removeRemote(let id):
                try await folder.remove(id)
                outcome.ledger.entries[id] = nil

            case .remember(let id, let entry):
                outcome.ledger.entries[id] = entry
            }
            return true
        } catch {
            logger.error(
                "a draft sync step failed: \(String(describing: error), privacy: .private)")
            return false
        }
    }
}
