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
            accountID: account, handle: "@ana@example.com", followRequests: 2, openReports: nil)
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
        let person = WidgetSnapshot.Person(
            id: "1", name: "Ana", handle: "ana", avatarFile: kept, latestText: nil,
            latestDate: nil, latestStatusID: nil, hasNewStory: false)
        try store.write(
            WidgetSnapshot(accountID: account, handle: "@ana", people: [person]),
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
}

@Suite("Widget follower history")
struct WidgetStatsTests {
    private func stats(_ samples: [(String, Int)]) -> WidgetSnapshot.Stats {
        WidgetSnapshot.Stats(
            followers: samples.last?.1 ?? 0,
            history: samples.map { WidgetSnapshot.Stats.Sample(day: $0.0, followers: $0.1) })
    }

    @Test("The change is measured from the sample a week back")
    func weekChange() {
        let history = stats([
            ("2026-11-01", 90), ("2026-11-07", 100), ("2026-11-10", 105), ("2026-11-14", 112),
        ])
        let change = history.followerChange(today: "2026-11-14")
        #expect(change?.change == 12)
        #expect(change?.days == 7)
    }

    @Test("A younger history counts from its first day")
    func youngHistory() {
        let history = stats([("2026-11-12", 50), ("2026-11-14", 53)])
        let change = history.followerChange(today: "2026-11-14")
        #expect(change?.change == 3)
        #expect(change?.days == 2)
    }

    @Test("One day is no change yet")
    func singleDay() {
        #expect(stats([("2026-11-14", 50)]).followerChange(today: "2026-11-14") == nil)
    }

    @Test("Recording replaces today's sample and keeps the history bounded")
    func recording() {
        var history = stats([("2026-11-14", 50)])
        history = history.recording(followers: 52, day: "2026-11-14")
        #expect(history.history.count == 1)
        #expect(history.history.last?.followers == 52)

        for day in 0..<40 {
            let key = String(format: "2027-%02d-%02d", 1 + day / 28, 1 + day % 28)
            history = history.recording(followers: day, day: key)
        }
        #expect(history.history.count == WidgetSnapshot.Stats.historyDays)
        #expect(history.history.last?.day == "2027-02-12")
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

    @Test("A widget's account, people and sources are read back per account")
    func readsBack() {
        let (defaults, name) = scratchDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        WidgetWants.record(
            accountID: account, people: ["2", "1"], photoSources: [.hashtag("cats")],
            in: defaults)
        #expect(WidgetWants.accounts(in: defaults) == [account])
        #expect(WidgetWants.people(for: account, in: defaults) == ["1", "2"])
        #expect(WidgetWants.photoSources(for: account, in: defaults) == [.hashtag("cats")])
        #expect(WidgetWants.people(for: UUID(), in: defaults).isEmpty)
    }

    @Test("A want not renewed for three days is dropped")
    func expires() {
        let (defaults, name) = scratchDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        let then = Date(timeIntervalSince1970: 1_000_000)
        WidgetWants.record(accountID: account, people: ["1"], now: then, in: defaults)
        let later = then.addingTimeInterval(WidgetWants.lifetime + 1)
        #expect(WidgetWants.accounts(now: later, in: defaults).isEmpty)
        #expect(WidgetWants.people(for: account, now: later, in: defaults).isEmpty)
    }

    @Test("Signing out forgets the account's wants and nobody else's")
    func removesOneAccount() {
        let (defaults, name) = scratchDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        let other = UUID()
        WidgetWants.record(accountID: account, people: ["1"], in: defaults)
        WidgetWants.record(accountID: other, people: ["2"], in: defaults)
        WidgetWants.removeAll(accountID: account, in: defaults)
        #expect(WidgetWants.accounts(in: defaults) == [other])
        #expect(WidgetWants.people(for: account, in: defaults).isEmpty)
        #expect(WidgetWants.people(for: other, in: defaults) == ["2"])
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
