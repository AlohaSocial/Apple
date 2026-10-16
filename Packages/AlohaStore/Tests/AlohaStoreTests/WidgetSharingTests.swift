// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaStore

/// A defaults domain of its own per test, removed afterwards: the suites run
/// in parallel, and `.standard` is shared by all of them.
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

@Suite("Widget favourites")
struct WidgetFavouritesTests {
    let account = UUID()

    @Test("A tap is read back for its own post and account only")
    func readsBackPerPostAndAccount() {
        let (defaults, name) = scratchDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        WidgetFavourites.set(true, statusID: "1", accountID: account, in: defaults)
        #expect(WidgetFavourites.state(statusID: "1", accountID: account, in: defaults) == true)
        #expect(WidgetFavourites.state(statusID: "2", accountID: account, in: defaults) == nil)
        #expect(WidgetFavourites.state(statusID: "1", accountID: UUID(), in: defaults) == nil)
    }

    @Test("An unfavourite is remembered as false, not as nothing")
    func unfavouriteIsRemembered() {
        let (defaults, name) = scratchDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        WidgetFavourites.set(false, statusID: "1", accountID: account, in: defaults)
        #expect(WidgetFavourites.state(statusID: "1", accountID: account, in: defaults) == false)
    }

    @Test("After a day the cache has the server's word, and the tap is forgotten")
    func expires() {
        let (defaults, name) = scratchDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        let then = Date(timeIntervalSince1970: 1_000_000)
        WidgetFavourites.set(true, statusID: "1", accountID: account, now: then, in: defaults)
        let later = then.addingTimeInterval(WidgetFavourites.lifetime + 1)
        #expect(
            WidgetFavourites.state(statusID: "1", accountID: account, now: later, in: defaults)
                == nil)
    }

    @Test("A refused tap is taken back")
    func clear() {
        let (defaults, name) = scratchDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        WidgetFavourites.set(true, statusID: "1", accountID: account, in: defaults)
        WidgetFavourites.clear(statusID: "1", accountID: account, in: defaults)
        #expect(WidgetFavourites.state(statusID: "1", accountID: account, in: defaults) == nil)
    }
}

@Suite("Memories snapshot")
struct MemoriesSnapshotTests {
    private func memory(_ id: String, image: String? = nil) -> MemoriesSnapshot.Memory {
        MemoriesSnapshot.Memory(
            id: id, author: "Ana", text: "A day at the sea",
            createdAt: Date(timeIntervalSince1970: 0),
            imageFile: image)
    }

    @Test("What is written is what is read, with the pictures that came with it")
    func roundTrip() throws {
        let store = MemoriesSnapshotStore(directory: try scratchDirectory())
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let account = UUID()
        let snapshot = MemoriesSnapshot(
            accountID: account, day: "2026-10-16", memories: [memory("1"), memory("2")])
        try store.write(snapshot, images: ["1": Data([0xFF, 0xD8])])

        let read = try #require(store.read())
        #expect(read.accountID == account)
        #expect(read.day == "2026-10-16")
        #expect(read.memories.map(\.id) == ["1", "2"])
        #expect(read.memories[0].imageFile == "memory-1.jpg")
        #expect(read.memories[1].imageFile == nil)
        let url = try #require(store.imageURL(for: read.memories[0]))
        #expect(try Data(contentsOf: url) == Data([0xFF, 0xD8]))
    }

    @Test("A picture no memory names any more is removed")
    func removesStalePictures() throws {
        let store = MemoriesSnapshotStore(directory: try scratchDirectory())
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let account = UUID()
        try store.write(
            MemoriesSnapshot(accountID: account, day: "2026-10-15", memories: [memory("1")]),
            images: ["1": Data([1])])
        try store.write(
            MemoriesSnapshot(accountID: account, day: "2026-10-16", memories: [memory("2")]),
            images: ["2": Data([2])])

        let files = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        #expect(!files.contains("memory-1.jpg"))
        #expect(files.contains("memory-2.jpg"))
    }

    @Test("A stored day answers only for its own account and day")
    func isCurrent() throws {
        let store = MemoriesSnapshotStore(directory: try scratchDirectory())
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let account = UUID()
        #expect(!store.isCurrent(accountID: account, day: "2026-10-16"))
        try store.write(
            MemoriesSnapshot(accountID: account, day: "2026-10-16", memories: []), images: [:])
        #expect(store.isCurrent(accountID: account, day: "2026-10-16"))
        #expect(!store.isCurrent(accountID: account, day: "2026-10-17"))
        #expect(!store.isCurrent(accountID: UUID(), day: "2026-10-16"))
    }

    @Test("A server id cannot write outside the folder")
    func imageNameIsSafe() {
        #expect(MemoriesSnapshotStore.imageName(for: "../../etc/9") == "memory-etc9.jpg")
    }

    @Test("The day key is the local calendar day")
    func dayKey() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        // 23:30 UTC on the 15th is already the 16th in Berlin.
        let date = Date(timeIntervalSince1970: 1_792_107_000)
        #expect(MemoriesSnapshot.dayKey(for: date, calendar: calendar) == "2026-10-16")
    }
}
