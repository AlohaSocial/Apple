// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaStore

private func scratchDefaults() -> (UserDefaults, String) {
    let name = "aloha.tests.\(UUID().uuidString)"
    return (UserDefaults(suiteName: name) ?? .standard, name)
}

private func scratchDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "aloha-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Widget snapshot store")
struct WidgetSnapshotStoreTests {
    @Test("A snapshot reads back per account")
    func readsBack() throws {
        let store = WidgetSnapshotStore(directory: try scratchDirectory())
        let account = UUID()
        let snapshot = WidgetSnapshot(
            accountID: account, handle: "@ana@example.com",
            messages: WidgetSnapshot.Messages(unread: 2, conversations: []))
        try store.write(snapshot, images: [:])
        #expect(store.read(accountID: account) == snapshot)
        #expect(store.read(accountID: UUID()) == nil)
    }

    @Test("Pictures no snapshot names any more are removed")
    func prunesPictures() throws {
        let store = WidgetSnapshotStore(directory: try scratchDirectory())
        let account = UUID()
        let kept = WidgetSnapshotStore.imageName(
            for: try #require(URL(string: "https://example.com/a.jpg")), pixels: 96)
        let dropped = WidgetSnapshotStore.imageName(
            for: try #require(URL(string: "https://example.com/b.jpg")), pixels: 96)
        let row = WidgetSnapshot.ConversationRow(
            id: "1", names: "Ana", text: "Hi", date: Date(), unread: true, lastStatusID: "9",
            avatarFile: kept)
        try store.write(
            WidgetSnapshot(
                accountID: account, handle: "@ana",
                messages: WidgetSnapshot.Messages(unread: 1, conversations: [row])),
            images: [kept: Data([1]), dropped: Data([2])])
        #expect(store.hasImage(kept))
        #expect(!store.hasImage(dropped))

        store.remove(accountID: account)
        #expect(store.read(accountID: account) == nil)
        #expect(!store.hasImage(kept))
    }

    @Test("A picture's name depends on its address and its size")
    func imageNames() throws {
        let url = try #require(URL(string: "https://example.com/a.jpg"))
        let small = WidgetSnapshotStore.imageName(for: url, pixels: 96)
        #expect(small == WidgetSnapshotStore.imageName(for: url, pixels: 96))
        #expect(small != WidgetSnapshotStore.imageName(for: url, pixels: 720))
        #expect(small.hasPrefix("wimg-") && small.hasSuffix(".jpg"))
    }

    @Test("What the retired On this day widget left is removed on the next write")
    func removesRetiredFiles() throws {
        let directory = try scratchDirectory()
        let store = WidgetSnapshotStore(directory: directory)
        try Data([1]).write(to: directory.appending(path: "memories.json"))
        try Data([2]).write(to: directory.appending(path: "memory-109.jpg"))
        try store.write(WidgetSnapshot(accountID: UUID(), handle: "@ana"), images: [:])
        let left = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(!left.contains("memories.json"))
        #expect(!left.contains { $0.hasPrefix("memory-") })
    }

    @Test("A snapshot with the retired widgets' sections still reads")
    func readsOldSnapshot() throws {
        let directory = try scratchDirectory()
        let account = UUID()
        let json = """
            {"accountID":"\(account.uuidString)","handle":"@ana","writtenAt":0,
             "followRequests":2,"openReports":1,"people":[],"photoSets":[],
             "stats":{"followers":3,"history":[]},
             "messages":{"unread":1,"conversations":[]}}
            """
        try Data(json.utf8).write(
            to: directory.appending(path: "snapshot-\(account.uuidString).json"))
        let read = WidgetSnapshotStore(directory: directory).read(accountID: account)
        #expect(read?.messages?.unread == 1)
    }
}

@Suite("Widget photo sources")
struct WidgetPhotoSourceTests {
    @Test("Every source survives its key")
    func roundTrip() {
        let sources: [WidgetPhotoSource] = [
            .home, .hashtag("cats"), .account("109"), .list("7"),
        ]
        for source in sources {
            #expect(WidgetPhotoSource(key: source.key) == source)
        }
    }

    @Test("Hashtags are one source whatever their case")
    func hashtagCase() {
        #expect(WidgetPhotoSource.hashtag("Cats").key == WidgetPhotoSource.hashtag("cats").key)
    }

    @Test("A key without a value is no source")
    func malformed() {
        #expect(WidgetPhotoSource(key: "tag:") == nil)
        #expect(WidgetPhotoSource(key: "elsewhere:1") == nil)
    }
}

@Suite("Widget wants")
struct WidgetWantsTests {
    let account = UUID()

    @Test("A widget's account and sources are read back per account")
    func readsBack() {
        let (defaults, name) = scratchDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        WidgetWants.record(accountID: account, photoSources: [.hashtag("cats")], in: defaults)
        #expect(WidgetWants.accounts(in: defaults) == [account])
        #expect(WidgetWants.photoSources(for: account, in: defaults) == [.hashtag("cats")])
        #expect(WidgetWants.photoSources(for: UUID(), in: defaults).isEmpty)
    }

    @Test("A want not renewed for three days is dropped")
    func expires() {
        let (defaults, name) = scratchDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        let then = Date(timeIntervalSince1970: 1_000_000)
        WidgetWants.record(accountID: account, photoSources: [.home], now: then, in: defaults)
        let later = then.addingTimeInterval(WidgetWants.lifetime + 1)
        #expect(WidgetWants.accounts(now: later, in: defaults).isEmpty)
        #expect(WidgetWants.photoSources(for: account, now: later, in: defaults).isEmpty)
    }

    @Test("Signing out forgets the account's wants and nobody else's")
    func removesOneAccount() {
        let (defaults, name) = scratchDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        let other = UUID()
        WidgetWants.record(accountID: account, photoSources: [.list("1")], in: defaults)
        WidgetWants.record(accountID: other, photoSources: [.list("2")], in: defaults)
        WidgetWants.removeAll(accountID: account, in: defaults)
        #expect(WidgetWants.accounts(in: defaults) == [other])
        #expect(WidgetWants.photoSources(for: account, in: defaults).isEmpty)
        #expect(WidgetWants.photoSources(for: other, in: defaults) == [.list("2")])
    }
}

@Suite("Widget bookmarks")
struct WidgetBookmarksTests {
    let account = UUID()

    @Test("Bookmarks and favourites are kept apart")
    func separateLedgers() {
        let (defaults, name) = scratchDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        WidgetBookmarks.set(true, statusID: "1", accountID: account, in: defaults)
        #expect(WidgetBookmarks.state(statusID: "1", accountID: account, in: defaults) == true)
        #expect(WidgetFavourites.state(statusID: "1", accountID: account, in: defaults) == nil)
        WidgetBookmarks.clear(statusID: "1", accountID: account, in: defaults)
        #expect(WidgetBookmarks.state(statusID: "1", accountID: account, in: defaults) == nil)
    }

    @Test("Favourites written before the ledger was shared still read")
    func readsOldFavourites() throws {
        let (defaults, name) = scratchDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        let now = Date()
        let old: [String: [String: Any]] = [
            "\(account.uuidString)/9": [
                "favourited": true, "at": now.timeIntervalSinceReferenceDate,
            ]
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: old), forKey: "aloha.widgetFavourites")
        #expect(WidgetFavourites.state(statusID: "9", accountID: account, in: defaults) == true)
    }
}
