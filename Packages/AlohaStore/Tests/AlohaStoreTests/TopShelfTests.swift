// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import Foundation
import Testing

@testable import AlohaStore

/// A post as the server sends it, with one attachment of `kind`.
private func post(
    _ id: String, content: String = "<p>A walk by the sea</p>", kind: String = "video",
    sensitive: Bool = false, spoiler: String = ""
) throws -> Status {
    let json = """
        {
          "id": "\(id)",
          "created_at": "2026-10-16T12:00:00.000Z",
          "content": "\(content)",
          "sensitive": \(sensitive),
          "spoiler_text": "\(spoiler)",
          "visibility": "public",
          "account": {"id": "1", "username": "alice", "acct": "alice", "display_name": "Alice"},
          "media_attachments": [
            {"id": "m\(id)", "type": "\(kind)", "url": "https://example.test/\(id).mp4",
             "preview_url": "https://example.test/\(id).jpg"}
          ]
        }
        """
    return try AlohaJSON.decoder.decode(Status.self, from: Data(json.utf8))
}

private func scratchDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "aloha-topshelf-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Top Shelf snapshot")
struct TopShelfSnapshotTests {
    let account = UUID()

    @Test("Continue watching carries progress and the resume position")
    func continueWatchingProgress() throws {
        let entry = ContinueWatchingItem(
            statusID: "1", position: 30, duration: 120, status: try post("1"))
        let snapshot = TopShelfSnapshot.make(
            accountID: account, continueWatching: [entry], following: [])

        let item = try #require(snapshot.sections.first?.items.first)
        #expect(snapshot.sections.map(\.kind) == [.continueWatching])
        #expect(item.progress == 0.25)
        #expect(item.position == 30)
        #expect(item.title == "A walk by the sea")
        #expect(item.imageURL == URL(string: "https://example.test/1.jpg"))
    }

    @Test("A video already in Continue watching is not repeated under Following")
    func noDuplicates() throws {
        let entry = ContinueWatchingItem(
            statusID: "1", position: 10, duration: 100, status: try post("1"))
        let snapshot = TopShelfSnapshot.make(
            accountID: account, continueWatching: [entry],
            following: [try post("1"), try post("2")])

        #expect(snapshot.sections.map(\.kind) == [.continueWatching, .following])
        #expect(snapshot.sections[1].items.map(\.id) == ["2"])
    }

    @Test("Sensitive media, content warnings and posts without video stay off the shelf")
    func leavesOutWhatCannotBeShown() throws {
        let snapshot = TopShelfSnapshot.make(
            accountID: account, continueWatching: [],
            following: [
                try post("1", sensitive: true),
                try post("2", spoiler: "Spiders"),
                try post("3", kind: "image"),
                try post("4"),
            ])

        #expect(snapshot.sections.flatMap(\.items).map(\.id) == ["4"])
    }

    @Test("A post that is only a video is titled by who posted it")
    func titleFallsBackToAuthor() throws {
        let snapshot = TopShelfSnapshot.make(
            accountID: account, continueWatching: [], following: [try post("1", content: "")])
        #expect(snapshot.sections.first?.items.first?.title == "Alice")
    }

    @Test("Nothing to show is no sections, not empty rows")
    func emptyHasNoSections() {
        let snapshot = TopShelfSnapshot.make(
            accountID: account, continueWatching: [], following: [])
        #expect(snapshot.sections.isEmpty)
    }

    @Test("A write reports a change only when what is shown changed")
    func writeReportsChanges() throws {
        let store = TopShelfSnapshotStore(directory: try scratchDirectory())
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let first = TopShelfSnapshot.make(
            accountID: account, continueWatching: [], following: [try post("1")],
            now: Date(timeIntervalSince1970: 1))
        let same = TopShelfSnapshot.make(
            accountID: account, continueWatching: [], following: [try post("1")],
            now: Date(timeIntervalSince1970: 2))
        let different = TopShelfSnapshot.make(
            accountID: account, continueWatching: [], following: [try post("2")])

        #expect(try store.write(first))
        #expect(try store.write(same) == false)
        #expect(store.read()?.createdAt == Date(timeIntervalSince1970: 2))
        #expect(try store.write(different))
    }
}

@Suite("Top Shelf links")
struct TopShelfLinkTests {
    @Test("Play and show links round-trip, with and without a position")
    func roundTrip() throws {
        for link in [
            TopShelfLink.play(statusID: "123", position: 42),
            .show(statusID: "123", position: nil),
        ] {
            let url = try #require(link.url)
            #expect(TopShelfLink(url: url) == link)
        }
    }

    @Test("The link reads as the app's own scheme")
    func spelling() {
        #expect(
            TopShelfLink.play(statusID: "9", position: 61.8).url?.absoluteString
                == "alohasocial://tv/play/9?t=61")
    }

    @Test("Links that are not the TV's are refused")
    func refusesOthers() throws {
        for raw in [
            "alohasocial://status/abc/1", "alohasocial://tv/rewind/1", "alohasocial://tv/play",
            "https://tv/play/1",
        ] {
            #expect(TopShelfLink(url: try #require(URL(string: raw))) == nil)
        }
    }
}

@Suite("TV account")
struct TVAccountStoreTests {
    private func scratchDefaults() -> (UserDefaults, String) {
        let name = "aloha.tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name) ?? .standard, name)
    }

    @Test("A sign-in from an older build moves into the shared stores when the app reads it")
    func adoptsLegacy() throws {
        let (shared, sharedName) = scratchDefaults()
        let (legacy, legacyName) = scratchDefaults()
        defer {
            UserDefaults.standard.removePersistentDomain(forName: sharedName)
            UserDefaults.standard.removePersistentDomain(forName: legacyName)
        }
        let sharedCredentials = CredentialStore(inMemory: true)
        let legacyCredentials = CredentialStore(inMemory: true)
        let id = UUID()
        let base = try #require(URL(string: "https://cloud.example.test/apps/social/"))
        legacy.set(id.uuidString, forKey: TVAccountStore.accountKey)
        legacy.set(base, forKey: TVAccountStore.apiBaseKey)
        try legacyCredentials.setToken("secret", for: id)

        let store = TVAccountStore(
            shared: shared, legacy: legacy, sharedCredentials: sharedCredentials,
            legacyCredentials: legacyCredentials)

        // The extension reads, never adopts.
        #expect(store.load() == nil)

        let account = try #require(store.load(adoptingLegacy: true))
        #expect(account == TVAccount(id: id, apiBase: base, token: "secret"))
        // The in-memory keychain is one store per service, so the two
        // credential stores cannot be told apart here; the defaults can, and
        // they are what the extension looks up first.
        #expect(shared.string(forKey: TVAccountStore.accountKey) == id.uuidString)
        #expect(store.load() == account)
    }

    @Test("A saved account is read back from the shared stores")
    func saveAndLoad() throws {
        let (shared, name) = scratchDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let store = TVAccountStore(
            shared: shared, legacy: shared, sharedCredentials: CredentialStore(inMemory: true),
            legacyCredentials: CredentialStore(inMemory: true))
        let account = TVAccount(
            id: UUID(), apiBase: try #require(URL(string: "https://example.test/")), token: "t")

        try store.save(account)
        #expect(store.load() == account)
    }
}
