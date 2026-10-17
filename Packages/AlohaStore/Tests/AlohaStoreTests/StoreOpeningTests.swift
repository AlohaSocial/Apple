// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import SwiftData
import Testing

@testable import AlohaStore

private func scratchStore() throws -> (root: URL, store: URL) {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "aloha-open-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return (root, root.appending(path: "AlohaSocial.store"))
}

/// A store with one account in it, written the way a build from before the
/// migration plan wrote it: the plain schema, no plan.
private func seedStore(at url: URL) throws {
    let container = try ModelContainer(
        for: StoreContainer.schema,
        configurations: [ModelConfiguration(schema: StoreContainer.schema, url: url)])
    let context = ModelContext(container)
    context.insert(
        AccountRecord(
            instanceHost: "example.social", apiBase: URL(string: "https://example.social/")!,
            handle: "alice", displayName: "Alice", serverAccountID: "1",
            capabilities: .minimal(apiBase: URL(string: "https://example.social/")!)))
    let draft = DraftRecord(accountID: UUID(), text: "not sent yet")
    draft.queuedForSend = true
    context.insert(draft)
    try context.save()
}

private func accountCount(in container: ModelContainer) throws -> Int {
    try ModelContext(container).fetchCount(FetchDescriptor<AccountRecord>())
}

@Suite("Opening the shared store")
struct StoreOpeningTests {
    @Test("An extension never creates the store the app has not made yet")
    func extensionDoesNotCreate() throws {
        let (root, store) = try scratchStore()
        defer { try? FileManager.default.removeItem(at: root) }

        for role in [StoreContainer.Role.writer, .reader] {
            let opened = StoreContainer.open(at: store, role: role)
            #expect(opened.fallback == .noStoreYet)
        }
        #expect(!FileManager.default.fileExists(atPath: store.path))
    }

    @Test("The app creates it, and an extension then reads what the app wrote")
    func appCreatesExtensionReads() throws {
        let (root, store) = try scratchStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try seedStore(at: store)

        let reader = StoreContainer.open(at: store, role: .reader)
        #expect(reader.fallback == nil)
        #expect(try accountCount(in: reader.container) == 1)
    }

    @Test("A store written before the migration plan opens under it, data intact")
    func planOpensOlderStore() throws {
        let (root, store) = try scratchStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try seedStore(at: store)

        let opened = StoreContainer.open(at: store, role: .app)
        #expect(opened.fallback == nil)
        #expect(try accountCount(in: opened.container) == 1)
        let drafts = try ModelContext(opened.container).fetch(FetchDescriptor<DraftRecord>())
        #expect(drafts.map(\.text) == ["not sent yet"])
    }

    @Test("A file that cannot be read yet is left exactly as it is")
    func unreadableIsLeftAlone() throws {
        let (root, store) = try scratchStore()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644], ofItemAtPath: store.path)
            try? FileManager.default.removeItem(at: root)
        }
        // Plain bytes rather than a live database, whose own log could still
        // be landing in the file while the test reads it.
        let before = Data("a store that is there and cannot be read".utf8)
        try before.write(to: store)
        // What data protection does before the first unlock, as far as a
        // test can say it: the bytes are there and cannot be read.
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: store.path)

        for role in [StoreContainer.Role.app, .writer, .reader] {
            #expect(StoreContainer.open(at: store, role: role).fallback == .unreadable)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: store.path)
        #expect(try Data(contentsOf: store) == before)
    }

    @Test("An extension that cannot open the store leaves it for the app")
    func extensionNeverRebuilds() throws {
        let (root, store) = try scratchStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let garbage = Data("not a database at all".utf8)
        try garbage.write(to: store)

        #expect(StoreContainer.open(at: store, role: .writer).fallback == .unopenable)
        #expect(try Data(contentsOf: store) == garbage)
    }

    @Test("The app moves an unopenable store aside rather than deleting it")
    func appMovesAside() throws {
        let (root, store) = try scratchStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let garbage = Data("not a database at all".utf8)
        try garbage.write(to: store)

        let opened = StoreContainer.open(at: store, role: .app)

        #expect(opened.fallback == nil)
        #expect(try accountCount(in: opened.container) == 0)
        let aside = root.appending(path: "AlohaSocial.unopenable.store")
        #expect(try Data(contentsOf: aside) == garbage)
    }

    @Test("A reader cannot write to the app's store")
    func readerIsReadOnly() throws {
        let (root, store) = try scratchStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try seedStore(at: store)

        let reader = StoreContainer.open(at: store, role: .reader).container
        let context = ModelContext(reader)
        context.insert(DraftRecord(accountID: UUID(), text: "from a widget"))
        #expect(throws: (any Error).self) { try context.save() }
    }
}
