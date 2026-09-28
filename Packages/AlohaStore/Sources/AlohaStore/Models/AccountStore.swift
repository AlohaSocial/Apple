// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import SwiftData

/// Account rows and their settings. Secrets never pass through here — they live
/// in the Keychain and are read by `CredentialStore`.
@ModelActor
public actor AccountStore {

    public struct Snapshot: Sendable, Hashable, Identifiable {
        public var id: UUID
        public var instanceHost: String
        public var apiBase: URL
        public var handle: String
        public var displayName: String
        public var avatarURL: URL?
        public var headerURL: URL?
        public var serverAccountID: String
        public var capabilities: ServerCapabilities
        public var settings: AccountSettings
        public var needsReauthentication: Bool
        public var sortIndex: Int

        public var qualifiedHandle: String {
            handle.contains("@") ? "@\(handle)" : "@\(handle)@\(instanceHost)"
        }

        public var bestDisplayName: String {
            displayName.isEmpty ? handle : displayName
        }

        /// The reader as an `Account`, so their own avatar draws through the
        /// same view — and falls back to the same monogram — as anybody else's.
        public var asAccount: Account {
            Account(
                id: serverAccountID,
                username: handle.split(separator: "@").first.map(String.init) ?? handle,
                acct: handle,
                displayName: displayName,
                avatar: avatarURL,
                header: headerURL)
        }
    }

    public func allAccounts() throws -> [Snapshot] {
        let descriptor = FetchDescriptor<AccountRecord>(
            sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.addedAt)])
        return try modelContext.fetch(descriptor).map(Self.snapshot)
    }

    public func account(id: UUID) throws -> Snapshot? {
        try record(id: id).map(Self.snapshot)
    }

    private func record(id: UUID) throws -> AccountRecord? {
        try modelContext.fetch(
            FetchDescriptor<AccountRecord>(predicate: #Predicate { $0.id == id })
        ).first
    }

    private static func snapshot(_ record: AccountRecord) -> Snapshot {
        Snapshot(
            id: record.id,
            instanceHost: record.instanceHost,
            apiBase: record.apiBase,
            handle: record.handle,
            displayName: record.displayName,
            avatarURL: record.avatarURL,
            headerURL: record.headerURL,
            serverAccountID: record.serverAccountID,
            capabilities: record.capabilities,
            settings: record.settings,
            needsReauthentication: record.needsReauthentication,
            sortIndex: record.sortIndex
        )
    }

    @discardableResult
    public func addAccount(
        id: UUID = UUID(),
        instanceHost: String,
        apiBase: URL,
        account: Account,
        capabilities: ServerCapabilities,
        settings: AccountSettings = AccountSettings()
    ) throws -> Snapshot {
        let nextIndex = try modelContext.fetchCount(FetchDescriptor<AccountRecord>())
        let record = AccountRecord(
            id: id,
            instanceHost: instanceHost,
            apiBase: apiBase,
            handle: account.acct,
            displayName: account.bestDisplayName,
            serverAccountID: account.id,
            capabilities: capabilities,
            settings: settings,
            sortIndex: nextIndex
        )
        record.avatarURLString = account.avatar?.absoluteString
        record.headerURLString = account.header?.absoluteString
        modelContext.insert(record)
        try modelContext.save()
        return Self.snapshot(record)
    }

    public func updateCapabilities(_ capabilities: ServerCapabilities, for id: UUID) throws {
        guard let record = try record(id: id) else { return }
        record.capabilities = capabilities
        record.apiBaseString = capabilities.apiBase.absoluteString
        try modelContext.save()
    }

    public func updateSettings(_ settings: AccountSettings, for id: UUID) throws {
        guard let record = try record(id: id) else { return }
        record.settings = settings
        try modelContext.save()
    }

    public func updateProfile(_ account: Account, for id: UUID) throws {
        guard let record = try record(id: id) else { return }
        record.handle = account.acct
        record.displayName = account.bestDisplayName
        record.avatarURLString = account.avatar?.absoluteString
        record.headerURLString = account.header?.absoluteString
        record.serverAccountID = account.id
        try modelContext.save()
    }

    /// A revoked token is a state, not a deletion: the row stays, marked, and
    /// the cache with it.
    public func setNeedsReauthentication(_ value: Bool, for id: UUID) throws {
        guard let record = try record(id: id) else { return }
        record.needsReauthentication = value
        try modelContext.save()
    }

    public func reorder(_ orderedIDs: [UUID]) throws {
        let records = try modelContext.fetch(FetchDescriptor<AccountRecord>())
        for record in records {
            if let index = orderedIDs.firstIndex(of: record.id) { record.sortIndex = index }
        }
        try modelContext.save()
    }
}
