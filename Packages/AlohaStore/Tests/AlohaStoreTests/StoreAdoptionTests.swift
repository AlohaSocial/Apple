// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaStore

private func scratchDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "aloha-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Moving the local store into the app group")
struct StoreAdoptionTests {
    @Test("The store and its log move once, into a group that has none")
    func movesStoreAndLog() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let local = root.appending(path: "local/default.store")
        let shared = root.appending(path: "group/AlohaSocial.store")
        try FileManager.default.createDirectory(
            at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: local)
        try Data([2]).write(to: URL(fileURLWithPath: local.path + "-wal"))

        StoreContainer.adoptLocalStoreIfNeeded(into: shared, from: local, isApp: true)

        #expect(try Data(contentsOf: shared) == Data([1]))
        #expect(try Data(contentsOf: URL(fileURLWithPath: shared.path + "-wal")) == Data([2]))
        #expect(!FileManager.default.fileExists(atPath: local.path))
    }

    @Test("A group that already has a store keeps it")
    func keepsExistingGroupStore() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let local = root.appending(path: "default.store")
        let shared = root.appending(path: "AlohaSocial.store")
        try Data([1]).write(to: local)
        try Data([2]).write(to: shared)

        StoreContainer.adoptLocalStoreIfNeeded(into: shared, from: local, isApp: true)

        #expect(try Data(contentsOf: shared) == Data([2]))
        #expect(FileManager.default.fileExists(atPath: local.path))
    }

    @Test("An extension moves nothing")
    func extensionMovesNothing() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let local = root.appending(path: "default.store")
        let shared = root.appending(path: "AlohaSocial.store")
        try Data([1]).write(to: local)

        StoreContainer.adoptLocalStoreIfNeeded(into: shared, from: local, isApp: false)

        #expect(!FileManager.default.fileExists(atPath: shared.path))
    }
}
