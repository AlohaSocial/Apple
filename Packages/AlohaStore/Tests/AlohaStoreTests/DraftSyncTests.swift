// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaStore

private let account = UUID()
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func draft(
    _ id: UUID, _ text: String, at time: Date = t0, accountID: UUID = account
) -> DraftSnapshot {
    DraftSnapshot(id: id, accountID: accountID, text: text, updatedAt: time)
}

private func draft(_ text: String, at time: Date = t0, accountID: UUID = account)
    -> DraftSnapshot
{
    draft(UUID(), text, at: time, accountID: accountID)
}

private func remote(_ file: DraftSyncFile, etag: String? = "e1") -> DraftMerge.Remote {
    DraftMerge.Remote(etag: etag, file: file)
}

private func entry(_ stamp: Date, deleted: Bool = false, etag: String? = "e1")
    -> DraftSyncLedger.Entry
{
    DraftSyncLedger.Entry(stamp: stamp, deleted: deleted, etag: etag)
}

private func actions(_ steps: [DraftMerge.Step]) -> [DraftMerge.Action] {
    steps.flatMap(\.actions)
}

@Suite("Draft merge")
struct DraftMergeTests {

    @Test("A draft only here is uploaded")
    func newLocalUploads() {
        let local = draft("Hello")
        let steps = DraftMerge.plan(
            local: [local], remote: [:], ledger: DraftSyncLedger(), accountID: account, now: t0)
        #expect(actions(steps) == [.upload(DraftSyncFile(local))])
    }

    @Test("A draft only there arrives here with the time it was written there")
    func newRemoteImports() throws {
        let written = draft("From the Mac", at: t0.addingTimeInterval(-60))
        let steps = DraftMerge.plan(
            local: [], remote: [written.id: remote(DraftSyncFile(written))],
            ledger: DraftSyncLedger(), accountID: account, now: t0)

        guard case .saveLocal(let saved, let expected, let etag)? = actions(steps).first else {
            Issue.record("expected a local save")
            return
        }
        #expect(saved.text == "From the Mac")
        #expect(saved.updatedAt == written.updatedAt)
        #expect(saved.accountID == account)
        #expect(expected == nil)
        #expect(etag == "e1")
    }

    @Test("Another device's account id is never carried over: ids are per device")
    func importUsesLocalAccount() {
        let elsewhere = draft("Hi", accountID: UUID())
        let steps = DraftMerge.plan(
            local: [], remote: [elsewhere.id: remote(DraftSyncFile(elsewhere))],
            ledger: DraftSyncLedger(), accountID: account, now: t0)
        guard case .saveLocal(let saved, _, _)? = actions(steps).first else {
            Issue.record("expected a local save")
            return
        }
        #expect(saved.accountID == account)
    }

    @Test("Nothing changed on either side does nothing")
    func unchanged() {
        let local = draft("Same")
        let ledger = DraftSyncLedger(entries: [local.id: entry(t0)])
        let steps = DraftMerge.plan(
            local: [local], remote: [local.id: DraftMerge.Remote(etag: "e1", file: nil)],
            ledger: ledger, accountID: account, now: t0)
        #expect(steps.isEmpty)
    }

    @Test("Changed only here: uploaded")
    func changedLocally() {
        let id = UUID()
        let local = draft(id, "Edited here", at: t0.addingTimeInterval(30))
        let ledger = DraftSyncLedger(entries: [id: entry(t0)])
        let steps = DraftMerge.plan(
            local: [local], remote: [id: DraftMerge.Remote(etag: "e1", file: nil)],
            ledger: ledger, accountID: account, now: t0)
        #expect(actions(steps) == [.upload(DraftSyncFile(local))])
    }

    @Test("Changed only there: saved here, if still as sync found it")
    func changedRemotely() {
        let id = UUID()
        let local = draft(id, "Old", at: t0)
        let there = draft(id, "Edited there", at: t0.addingTimeInterval(30))
        let ledger = DraftSyncLedger(entries: [id: entry(t0)])
        let steps = DraftMerge.plan(
            local: [local], remote: [id: remote(DraftSyncFile(there), etag: "e2")],
            ledger: ledger, accountID: account, now: t0)
        guard case .saveLocal(let saved, let expected, let etag)? = actions(steps).first else {
            Issue.record("expected a local save")
            return
        }
        #expect(saved.text == "Edited there")
        #expect(expected == t0)
        #expect(etag == "e2")
        #expect(actions(steps).count == 1)
    }

    @Test("Deleted here: a tombstone goes there")
    func deletedLocally() {
        let id = UUID()
        let ledger = DraftSyncLedger(entries: [id: entry(t0)])
        let now = t0.addingTimeInterval(100)
        let steps = DraftMerge.plan(
            local: [], remote: [id: DraftMerge.Remote(etag: "e1", file: nil)],
            ledger: ledger, accountID: account, now: now)
        #expect(actions(steps) == [.upload(.tombstone(id, deletedAt: now))])
    }

    @Test("Deleted there, untouched here: deleted here")
    func deletedRemotely() {
        let id = UUID()
        let local = draft(id, "Doomed", at: t0)
        let tombstone = DraftSyncFile.tombstone(id, deletedAt: t0.addingTimeInterval(50))
        let ledger = DraftSyncLedger(entries: [id: entry(t0)])
        let steps = DraftMerge.plan(
            local: [local], remote: [id: remote(tombstone, etag: "e2")],
            ledger: ledger, accountID: account, now: t0.addingTimeInterval(60))
        #expect(
            actions(steps) == [.deleteLocal(id, expected: t0, tombstone: tombstone, etag: "e2")])
    }

    @Test("Deleted there but edited here since: the edit comes back rather than being lost")
    func editOutweighsRemoteDeletion() {
        let id = UUID()
        let local = draft(id, "Still writing", at: t0.addingTimeInterval(40))
        let tombstone = DraftSyncFile.tombstone(id, deletedAt: t0.addingTimeInterval(50))
        let ledger = DraftSyncLedger(entries: [id: entry(t0)])
        let steps = DraftMerge.plan(
            local: [local], remote: [id: remote(tombstone, etag: "e2")],
            ledger: ledger, accountID: account, now: t0.addingTimeInterval(60))
        #expect(actions(steps) == [.upload(DraftSyncFile(local))])
    }

    @Test("Deleted here but edited there since: the edit comes back here")
    func editOutweighsLocalDeletion() {
        let id = UUID()
        let there = draft(id, "Edited on the iPad", at: t0.addingTimeInterval(40))
        let ledger = DraftSyncLedger(entries: [id: entry(t0)])
        let steps = DraftMerge.plan(
            local: [], remote: [id: remote(DraftSyncFile(there), etag: "e2")],
            ledger: ledger, accountID: account, now: t0.addingTimeInterval(60))
        guard case .saveLocal(let saved, let expected, _)? = actions(steps).first else {
            Issue.record("expected the draft back")
            return
        }
        #expect(saved.text == "Edited on the iPad")
        #expect(expected == nil)
    }

    @Test("Changed differently on both, newer here: the older is kept as a copy")
    func divergedLocalNewer() {
        let id = UUID()
        let copyID = UUID()
        let local = draft(id, "Phone version", at: t0.addingTimeInterval(90))
        let there = draft(id, "Mac version", at: t0.addingTimeInterval(30))
        let ledger = DraftSyncLedger(entries: [id: entry(t0)])
        let steps = DraftMerge.plan(
            local: [local], remote: [id: remote(DraftSyncFile(there), etag: "e2")],
            ledger: ledger, accountID: account, now: t0.addingTimeInterval(100),
            makeID: { copyID })

        let all = actions(steps)
        #expect(all.count == 3)
        guard case .saveLocal(let copy, let expected, _) = all[0],
            case .upload(let copyFile) = all[1],
            case .upload(let kept) = all[2]
        else {
            Issue.record("expected copy, copy upload, then the newer draft")
            return
        }
        #expect(copy.id == copyID)
        #expect(copy.text == "Mac version")
        #expect(copy.isSyncConflictCopy)
        #expect(copy.idempotencyKey != there.idempotencyKey)
        #expect(expected == nil)
        #expect(copyFile.id == copyID)
        #expect(kept == DraftSyncFile(local))
    }

    @Test("Changed differently on both, newer there: this device's words become the copy")
    func divergedRemoteNewer() {
        let id = UUID()
        let copyID = UUID()
        let local = draft(id, "Phone version", at: t0.addingTimeInterval(30))
        let there = draft(id, "Mac version", at: t0.addingTimeInterval(90))
        let ledger = DraftSyncLedger(entries: [id: entry(t0)])
        let steps = DraftMerge.plan(
            local: [local], remote: [id: remote(DraftSyncFile(there), etag: "e2")],
            ledger: ledger, accountID: account, now: t0.addingTimeInterval(100),
            makeID: { copyID })

        let all = actions(steps)
        guard all.count == 3, case .saveLocal(let copy, nil, _) = all[0],
            case .upload = all[1],
            case .saveLocal(let replaced, let expected, _) = all[2]
        else {
            Issue.record("expected the copy saved before the draft is replaced")
            return
        }
        #expect(copy.text == "Phone version")
        #expect(copy.isSyncConflictCopy)
        #expect(replaced.id == id)
        #expect(replaced.text == "Mac version")
        #expect(expected == local.updatedAt)
    }

    @Test("Changed on both to the same words: no copy, the newer time stands")
    func convergedEdits() {
        let id = UUID()
        let key = UUID().uuidString
        var local = draft(id, "Same words", at: t0.addingTimeInterval(30))
        local.idempotencyKey = key
        var there = draft(id, "Same words", at: t0.addingTimeInterval(90))
        there.idempotencyKey = key
        let ledger = DraftSyncLedger(entries: [id: entry(t0)])
        let steps = DraftMerge.plan(
            local: [local], remote: [id: remote(DraftSyncFile(there), etag: "e2")],
            ledger: ledger, accountID: account, now: t0)
        let all = actions(steps)
        #expect(all.count == 1)
        guard case .saveLocal(let saved, _, _) = all.first else {
            Issue.record("expected the newer time to be taken")
            return
        }
        #expect(saved.updatedAt == there.updatedAt)
    }

    @Test("A draft both sides have but the ledger forgot is compared by content")
    func lostLedger() {
        let id = UUID()
        let local = draft(id, "Mine", at: t0)
        let there = draft(id, "Theirs", at: t0.addingTimeInterval(10))
        let steps = DraftMerge.plan(
            local: [local], remote: [id: remote(DraftSyncFile(there))],
            ledger: DraftSyncLedger(), accountID: account, now: t0)
        // Different words with nothing to say which came first: both kept.
        #expect(actions(steps).count == 3)
    }

    @Test("An old tombstone is cleared from the folder")
    func expiredTombstone() {
        let id = UUID()
        let deletedAt = t0
        let ledger = DraftSyncLedger(entries: [id: entry(deletedAt, deleted: true)])
        let steps = DraftMerge.plan(
            local: [], remote: [id: DraftMerge.Remote(etag: "e1", file: nil)], ledger: ledger,
            accountID: account, now: t0.addingTimeInterval(DraftMerge.tombstoneLifetime + 1))
        #expect(actions(steps) == [.removeRemote(id)])
    }

    @Test("A recent tombstone stays, so an offline device still learns of the deletion")
    func recentTombstoneStays() {
        let id = UUID()
        let ledger = DraftSyncLedger(entries: [id: entry(t0, deleted: true)])
        let steps = DraftMerge.plan(
            local: [], remote: [id: DraftMerge.Remote(etag: "e1", file: nil)], ledger: ledger,
            accountID: account, now: t0.addingTimeInterval(3600))
        #expect(steps.isEmpty)
    }

    @Test("A file removed by hand is put back rather than taken as a deletion")
    func fileRemovedByHand() {
        let id = UUID()
        let local = draft(id, "Keep me", at: t0)
        let ledger = DraftSyncLedger(entries: [id: entry(t0)])
        let steps = DraftMerge.plan(
            local: [local], remote: [:], ledger: ledger, accountID: account, now: t0)
        #expect(actions(steps) == [.upload(DraftSyncFile(local))])
    }

    @Test("A draft open in a composer is left alone")
    func excludedDraft() {
        let id = UUID()
        let local = draft(id, "Open", at: t0)
        let there = draft(id, "Changed", at: t0.addingTimeInterval(30))
        let ledger = DraftSyncLedger(entries: [id: entry(t0)])
        let steps = DraftMerge.plan(
            local: [local], remote: [id: remote(DraftSyncFile(there))], ledger: ledger,
            accountID: account, now: t0, excluding: [id])
        #expect(steps.isEmpty)
    }

    @Test("A new ETag on an unchanged draft only updates the ledger")
    func etagRefresh() {
        let id = UUID()
        let local = draft(id, "Same", at: t0)
        let ledger = DraftSyncLedger(entries: [id: entry(t0, etag: nil)])
        let steps = DraftMerge.plan(
            local: [local], remote: [id: remote(DraftSyncFile(local), etag: "e9")],
            ledger: ledger, accountID: account, now: t0)
        #expect(actions(steps) == [.remember(id, entry(t0, etag: "e9"))])
    }
}

@Suite("Draft sync file")
struct DraftSyncFileTests {

    @Test("A draft survives the file, its time to the millisecond")
    func roundTrip() throws {
        var original = draft("Round trip", at: Date(timeIntervalSince1970: 1_800_000_000.123))
        original.spoilerText = "cw"
        original.visibility = .unlisted
        original.uploadedMediaIDs = ["m1", "m2"]
        original.pollOptions = ["Yes", "No"]
        original.placeName = "Lisbon"

        let file = try DraftSyncFile.decode(try DraftSyncFile(original).encoded())
        let back = try #require(file.snapshot(accountID: account))

        #expect(back.text == "Round trip")
        #expect(back.spoilerText == "cw")
        #expect(back.visibility == .unlisted)
        #expect(back.uploadedMediaIDs == ["m1", "m2"])
        #expect(back.pollOptions == ["Yes", "No"])
        #expect(back.placeName == "Lisbon")
        #expect(back.idempotencyKey == original.idempotencyKey)
        #expect(DraftMerge.sameTime(back.updatedAt, original.updatedAt))
    }

    @Test("Files on the device do not travel; their number does")
    func localFilesBecomeACount() throws {
        var original = draft("With a picture")
        original.localMediaPaths = ["/var/mobile/a.jpg", "/var/mobile/b.mov"]
        let file = try DraftSyncFile.decode(try DraftSyncFile(original).encoded())
        let back = try #require(file.snapshot(accountID: account))
        #expect(back.localMediaPaths.isEmpty)
        #expect(back.attachmentsLeftOnOtherDevice == 2)
        let json = String(decoding: try DraftSyncFile(original).encoded(), as: UTF8.self)
        #expect(json.contains("/var/mobile") == false)
    }

    @Test("A sparse file still reads, each missing field its default")
    func sparseFile() throws {
        let json = """
            {"format":1,"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF",
             "updatedAt":"2026-11-15T10:00:00Z","draft":{"text":"Hand-written"}}
            """
        let file = try DraftSyncFile.decode(Data(json.utf8))
        let back = try #require(file.snapshot(accountID: account))
        #expect(back.text == "Hand-written")
        #expect(back.visibility == .public)
        #expect(back.idempotencyKey.isEmpty == false)
    }

    @Test("A tombstone has no draft")
    func tombstone() throws {
        let id = UUID()
        let file = try DraftSyncFile.decode(
            try DraftSyncFile.tombstone(id, deletedAt: t0).encoded())
        #expect(file.isTombstone)
        #expect(file.snapshot(accountID: account) == nil)
    }

    @Test("File names carry the id, and nothing else is taken for a draft")
    func fileNames() {
        let id = UUID()
        #expect(DraftSyncFile.id(fromFileName: DraftSyncFile.fileName(for: id)) == id)
        #expect(DraftSyncFile.id(fromFileName: "notes.txt") == nil)
        #expect(DraftSyncFile.id(fromFileName: "readme.json") == nil)
    }
}

/// A Drafts folder in memory, shared by two "devices".
private actor MemoryFolder: DraftSyncFolder {
    private var files: [UUID: (data: Data, etag: String)] = [:]
    private var counter = 0

    func list() async throws -> [UUID: String?] {
        files.mapValues { Optional($0.etag) }
    }

    func read(_ id: UUID) async throws -> Data {
        guard let file = files[id] else { throw CocoaError(.fileNoSuchFile) }
        return file.data
    }

    func write(_ data: Data, for id: UUID) async throws -> String? {
        counter += 1
        files[id] = (data, "etag-\(counter)")
        return "etag-\(counter)"
    }

    func remove(_ id: UUID) async throws {
        files[id] = nil
    }

    func file(_ id: UUID) throws -> DraftSyncFile? {
        try files[id].map { try DraftSyncFile.decode($0.data) }
    }
}

/// One device: its own store, its own account id, its own ledger.
private final class Device: @unchecked Sendable {
    let store = SupportStore(modelContainer: StoreContainer.make(inMemory: true))
    let accountID = UUID()
    var ledger = DraftSyncLedger()
    let folder: MemoryFolder

    init(folder: MemoryFolder) { self.folder = folder }

    func sync(at now: Date) async throws -> DraftSynchronizer.Outcome {
        let outcome = try await DraftSynchronizer(folder: folder, store: store)
            .sync(accountID: accountID, ledger: ledger, now: now)
        ledger = outcome.ledger
        return outcome
    }

    func drafts() async throws -> [DraftSnapshot] {
        try await store.drafts(accountID: accountID)
    }
}

@Suite("Draft sync between two devices")
struct DraftSyncEndToEndTests {

    @Test("Written on one, edited on the other, deleted on the first: all three travel")
    func lifecycle() async throws {
        let folder = MemoryFolder()
        let phone = Device(folder: folder)
        let mac = Device(folder: folder)

        let id = try await phone.store.saveDraft(
            DraftSnapshot(accountID: phone.accountID, text: "Started on the phone"))
        _ = try await phone.sync(at: Date())

        let arrived = try await mac.sync(at: Date())
        #expect(arrived.changedLocally)
        #expect(try await mac.drafts().map(\.text) == ["Started on the phone"])

        var onMac = try #require(try await mac.drafts().first)
        onMac.text = "Finished on the Mac"
        try await mac.store.saveDraft(onMac)
        _ = try await mac.sync(at: Date())

        _ = try await phone.sync(at: Date())
        #expect(try await phone.drafts().map(\.text) == ["Finished on the Mac"])
        #expect(try await phone.drafts().first?.id == id)

        try await phone.store.deleteDraft(id: id)
        _ = try await phone.sync(at: Date())
        #expect(try await folder.file(id)?.isTombstone == true)

        _ = try await mac.sync(at: Date())
        #expect(try await mac.drafts().isEmpty)

        // Settled: another round on each does nothing.
        let settled = try await phone.sync(at: Date())
        #expect(settled.changedLocally == false)
        #expect(settled.failures == 0)
    }

    @Test("Edited differently on both while apart: each device ends with both versions")
    func divergence() async throws {
        let folder = MemoryFolder()
        let phone = Device(folder: folder)
        let mac = Device(folder: folder)

        try await phone.store.saveDraft(
            DraftSnapshot(accountID: phone.accountID, text: "Draft"))
        _ = try await phone.sync(at: Date())
        _ = try await mac.sync(at: Date())

        var onPhone = try #require(try await phone.drafts().first)
        onPhone.text = "Phone's ending"
        try await phone.store.saveDraft(onPhone)

        try await Task.sleep(for: .milliseconds(20))
        var onMac = try #require(try await mac.drafts().first)
        onMac.text = "Mac's ending"
        try await mac.store.saveDraft(onMac)

        _ = try await phone.sync(at: Date())
        let conflicted = try await mac.sync(at: Date())
        #expect(conflicted.conflicts == 1)
        _ = try await phone.sync(at: Date())

        let phoneTexts = Set(try await phone.drafts().map(\.text))
        let macTexts = Set(try await mac.drafts().map(\.text))
        #expect(phoneTexts == ["Phone's ending", "Mac's ending"])
        #expect(macTexts == phoneTexts)
        // The newer version kept the draft; the older is the marked copy.
        let copy = try #require(try await mac.drafts().first { $0.isSyncConflictCopy })
        #expect(copy.text == "Phone's ending")
    }

    @Test("A draft saved while sync was deciding is not overwritten")
    func concurrentSaveWins() async throws {
        let device = Device(folder: MemoryFolder())
        let id = try await device.store.saveDraft(
            DraftSnapshot(accountID: device.accountID, text: "Typed just now"))
        let seen = try #require(try await device.store.draft(id: id)).updatedAt

        try await Task.sleep(for: .milliseconds(5))
        var newer = try #require(try await device.store.draft(id: id))
        newer.text = "Typed a moment later"
        try await device.store.saveDraft(newer)

        let stale = DraftSnapshot(
            id: id, accountID: device.accountID, text: "From elsewhere", updatedAt: Date())
        let written = try await device.store.applySyncedDraft(stale, expected: seen)
        #expect(written == false)
        #expect(try await device.store.draft(id: id)?.text == "Typed a moment later")
    }

    @Test("A draft queued to send here stays queued when another device's edit arrives")
    func queueStateStaysLocal() async throws {
        let device = Device(folder: MemoryFolder())
        var queued = DraftSnapshot(accountID: device.accountID, text: "Offline post")
        queued.queuedForSend = true
        let id = try await device.store.saveDraft(queued)
        let seen = try #require(try await device.store.draft(id: id)).updatedAt

        let incoming = DraftSnapshot(
            id: id, accountID: device.accountID, text: "Edited elsewhere",
            updatedAt: seen.addingTimeInterval(10))
        #expect(try await device.store.applySyncedDraft(incoming, expected: seen))
        let stored = try #require(try await device.store.draft(id: id))
        #expect(stored.text == "Edited elsewhere")
        #expect(stored.queuedForSend)
        #expect(DraftMerge.sameTime(stored.updatedAt, seen.addingTimeInterval(10)))
    }
}
