// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation
import Testing

@testable import AlohaUI

@Suite("The send queue")
@MainActor
struct SendQueueTests {

    @Test("Queued posts go out in order, with the key they were saved with")
    func drainsInOrder() async throws {
        let (session, transport) = try await makeSession()
        for (index, text) in ["first", "second"].enumerated() {
            _ = try await session.supportStore.saveDraft(
                DraftSnapshot(
                    accountID: session.id, text: text, idempotencyKey: "key-\(index)",
                    queuedForSend: true, threadIndex: index))
        }

        let sent = await SendQueue.drain(session: session)

        #expect(sent == 2)
        let posts = await transport.posts
        #expect(posts.map(\.text) == ["first", "second"])
        // The saved key, not a new one: a first attempt that did land is then
        // recognised by the server instead of posted twice.
        #expect(posts.map(\.idempotencyKey) == ["key-0", "key-1"])
        #expect(try await session.supportStore.drafts(accountID: session.id).isEmpty)
    }

    @Test("Still offline: the queue stops and keeps everything")
    func transientFailureKeepsQueue() async throws {
        let (session, transport) = try await makeSession()
        await transport.failPosts(with: .transport(URLError(.notConnectedToInternet)))
        for index in 0..<2 {
            _ = try await session.supportStore.saveDraft(
                DraftSnapshot(
                    accountID: session.id, text: "post \(index)", queuedForSend: true,
                    threadIndex: index))
        }

        let sent = await SendQueue.drain(session: session)

        #expect(sent == 0)
        // One attempt, not two: the second must not overtake the first.
        #expect(await transport.posts.count == 1)
        #expect(try await session.supportStore.queuedDrafts(accountID: session.id).count == 2)
    }

    @Test("A refusal takes that post off the queue with the server's reason")
    func refusalLeavesDraft() async throws {
        let (session, transport) = try await makeSession()
        await transport.failPosts(with: .unprocessable(message: "Text is too long"))
        let id = try await session.supportStore.saveDraft(
            DraftSnapshot(accountID: session.id, text: "long", queuedForSend: true))

        _ = await SendQueue.drain(session: session)

        #expect(try await session.supportStore.queuedDrafts(accountID: session.id).isEmpty)
        let kept = try #require(try await session.supportStore.drafts(accountID: session.id).first)
        #expect(kept.id == id)
        #expect(kept.lastSendError == "Text is too long")
    }

    @Test("A queued thread posts its segments as a chain")
    func threadChains() async throws {
        let (session, transport) = try await makeSession()
        _ = try await session.supportStore.saveDraft(
            DraftSnapshot(
                accountID: session.id, text: "one", queuedForSend: true,
                threadSegments: ["two", "three"]))

        #expect(await SendQueue.drain(session: session) == 1)

        let posts = await transport.posts
        #expect(posts.map(\.text) == ["one", "two", "three"])
        #expect(posts[0].inReplyToID == nil)
        #expect(posts[1].inReplyToID != nil)
        #expect(posts[2].inReplyToID != posts[1].inReplyToID)
    }

    @Test("A queued thread that breaks part-way keeps only what is left")
    func queuedThreadResumes() async throws {
        let (session, transport) = try await makeSession()
        _ = try await session.supportStore.saveDraft(
            DraftSnapshot(
                accountID: session.id, text: "one", idempotencyKey: "thread",
                queuedForSend: true, threadSegments: ["two", "three"]))
        await transport.failPost(number: 2, with: .transport(URLError(.timedOut)))

        #expect(await SendQueue.drain(session: session) == 0)
        let left = try #require(
            try await session.supportStore.queuedDrafts(accountID: session.id).first)
        #expect(left.text == "two")
        #expect(left.threadSegments == ["three"])
        #expect(left.threadPosition == 1)

        await transport.stopFailing()
        #expect(await SendQueue.drain(session: session) == 1)

        let posts = await transport.posts
        // "one" once; "two" twice — its first attempt timed out — under the
        // same key both times, so a server that kept it says so.
        #expect(posts.map(\.text) == ["one", "two", "two", "three"])
        #expect(posts.map(\.idempotencyKey) == ["thread", "thread-1", "thread-1", "thread-2"])
        #expect(posts[2].inReplyToID == left.inReplyToID)
        #expect(try await session.supportStore.drafts(accountID: session.id).isEmpty)
    }

    @Test("A refused segment comes off the queue as what is left, with the reason")
    func refusedSegmentLeavesTheRest() async throws {
        let (session, transport) = try await makeSession()
        _ = try await session.supportStore.saveDraft(
            DraftSnapshot(
                accountID: session.id, text: "one", queuedForSend: true,
                threadSegments: ["two", "three"]))
        await transport.failPost(number: 2, with: .unprocessable(message: "Too long"))

        _ = await SendQueue.drain(session: session)

        #expect(try await session.supportStore.queuedDrafts(accountID: session.id).isEmpty)
        let kept = try #require(try await session.supportStore.drafts(accountID: session.id).first)
        #expect(kept.text == "two")
        #expect(kept.lastSendError == "Too long")
        #expect(await transport.posts.map(\.text) == ["one", "two"])
    }

    @Test("A queued post keeps everything the composer would have sent")
    func queuedPostKeepsExtras() async throws {
        let (session, _) = try await makeSession()
        var draft = DraftSnapshot(accountID: session.id, text: "From the team")
        draft.postAs = "team@cloud.example.test"
        draft.placeName = "Lisbon"
        draft.placeCountry = "Portugal"
        draft.replyPolicy = ReplyPolicy.followers.rawValue
        draft.videoTitle = "Waves"
        _ = try await session.supportStore.saveDraft(draft)

        let stored = try #require(
            try await session.supportStore.drafts(accountID: session.id).first)
        let post = try await stored.statusPost(session: session, total: 1)

        #expect(post.postAs == "team@cloud.example.test")
        #expect(post.placeName == "Lisbon")
        #expect(post.placeCountry == "Portugal")
        #expect(post.videoTitle == "Waves")
    }
}

@Suite("A thread that fails part-way")
@MainActor
struct ThreadFailureTests {
    @Test("Retrying in the composer never posts the first post again")
    func composerRetryResumes() async throws {
        let (session, transport) = try await makeSession()
        let model = ComposerModel(session: session)
        model.text = "one"
        model.threadSegments = ["two", "three"]
        await transport.failPost(number: 2, with: .transport(URLError(.timedOut)))

        #expect(await model.post(skippingAltTextCheck: true) == false)
        await transport.stopFailing()
        #expect(await model.post(skippingAltTextCheck: true))

        let posts = await transport.posts
        #expect(posts.map(\.text) == ["one", "two", "two", "three"])
        #expect(posts.filter { $0.text == "one" }.count == 1)
        // The segment keeps its key between attempts.
        #expect(posts[1].idempotencyKey == posts[2].idempotencyKey)
        #expect(try await session.supportStore.drafts(accountID: session.id).isEmpty)
    }

    @Test("What the composer saves after a part-way failure is the rest of the thread")
    func composerSavesTheRest() async throws {
        let (session, transport) = try await makeSession()
        let model = ComposerModel(session: session)
        model.text = "one"
        model.threadSegments = ["two", "three"]
        await transport.failPost(number: 2, with: .transport(URLError(.timedOut)))

        _ = await model.post(skippingAltTextCheck: true)

        let saved = try #require(
            try await session.supportStore.queuedDrafts(accountID: session.id).first)
        #expect(saved.text == "two")
        #expect(saved.threadSegments == ["three"])
        #expect(saved.threadPosition == 1)
        #expect(saved.inReplyToID != nil)

        // And the queue finishes it without the first post.
        await transport.stopFailing()
        #expect(await SendQueue.drain(session: session) == 1)
        #expect(await transport.posts.map(\.text) == ["one", "two", "two", "three"])
    }
}

@Suite("Drafts and redrafts in the composer")
@MainActor
struct ComposerRestoreTests {

    @Test("A reopened draft saves back as the same draft, unchanged")
    func draftRoundTrip() async throws {
        let (session, _) = try await makeSession()
        let draft = DraftSnapshot(
            accountID: session.id, text: "Half a thought", spoilerText: "politics",
            visibility: .private, language: "de", inReplyToID: "40",
            pollOptions: ["Yes", "No"], pollMultiple: true,
            scheduledAt: Date(timeIntervalSince1970: 1_900_000_000),
            idempotencyKey: "kept", quotedID: "41", threadSegments: ["and more"])

        let model = ComposerModel(session: session, draft: draft)
        let saved = model.draftSnapshot

        #expect(saved.id == draft.id)
        #expect(saved.text == draft.text)
        #expect(saved.spoilerText == "politics")
        #expect(saved.visibility == .private)
        #expect(saved.language == "de")
        #expect(saved.inReplyToID == "40")
        #expect(saved.quotedID == "41")
        #expect(saved.pollOptions == ["Yes", "No"])
        #expect(saved.pollMultiple)
        #expect(saved.scheduledAt == draft.scheduledAt)
        #expect(saved.threadSegments == ["and more"])
        // Untouched words keep their key.
        #expect(saved.idempotencyKey == "kept")
    }

    @Test("A reopened draft can post before its uploads are looked up, and keeps them")
    func postBeforeLookups() async throws {
        let (session, transport) = try await makeSession()
        let draft = DraftSnapshot(
            accountID: session.id, text: "", uploadedMediaIDs: ["m1", "m2"])
        let model = ComposerModel(session: session, draft: draft)

        // Offline, the lookups `prepare()` makes take minutes to give up.
        #expect(model.isUploading == false)
        #expect(model.canPost)
        #expect(model.draftSnapshot.uploadedMediaIDs == ["m1", "m2"])

        _ = await model.post(skippingAltTextCheck: true)
        #expect(await transport.posts.last?.mediaIDs == ["m1", "m2"])
    }

    @Test("Editing a reopened draft gives it a new key")
    func editedDraftNewKey() async throws {
        let (session, _) = try await makeSession()
        let model = ComposerModel(
            session: session,
            draft: DraftSnapshot(accountID: session.id, text: "Hi", idempotencyKey: "kept"))

        model.text = "Hi there"

        #expect(model.draftSnapshot.idempotencyKey != "kept")
    }

    @Test("A redraft starts from the source text and the post's settings")
    func redraftPrefill() async throws {
        let (session, _) = try await makeSession()
        var status = Status(id: "77", account: Account(id: "1", username: "alice", acct: "alice"))
        status.visibility = .unlisted
        status.language = "fr"
        status.inReplyToID = "70"
        let source = try AlohaJSON.decoder.decode(
            StatusSource.self,
            from: Data(#"{"id":"77","text":"Bonjour *monde*","spoiler_text":"cw"}"#.utf8))

        let model = ComposerModel(session: session, redrafting: status, source: source)

        #expect(model.text == "Bonjour *monde*")
        #expect(model.spoilerText == "cw")
        #expect(model.showsContentWarningField)
        #expect(model.visibility == .unlisted)
        #expect(model.language == "fr")
        #expect(model.redrafting?.id == "77")
        #expect(model.draftSnapshot.inReplyToID == "70")
    }

    @Test("A redraft deletes the original only after the new post is made")
    func redraftDeletesAfterPosting() async throws {
        let (session, transport) = try await makeSession()
        let status = Status(id: "77", account: Account(id: "1", username: "alice", acct: "alice"))
        let source = try AlohaJSON.decoder.decode(
            StatusSource.self, from: Data(#"{"id":"77","text":"Again","spoiler_text":""}"#.utf8))
        let model = ComposerModel(session: session, redrafting: status, source: source)

        #expect(await model.post(skippingAltTextCheck: true))

        let log = await transport.log
        let post = try #require(log.firstIndex { $0 == "POST api/v1/statuses" })
        let delete = try #require(log.firstIndex { $0 == "DELETE api/v1/statuses/77" })
        #expect(post < delete)
    }
}

@Suite("Scheduling a post")
@MainActor
struct SchedulingTests {
    @Test("Mastodon's answer to a scheduled post reads as scheduled, not as a failure")
    func decodesScheduledAnswer() throws {
        // Verbatim the shape `REST::ScheduledStatusSerializer` writes: no
        // account, no content, which no `Status` can be read from.
        let json = #"""
            {"id":"3221","scheduled_at":"2026-11-02T09:00:00.000Z","params":{"poll":null,
            "text":"Later","language":"en","media_ids":null,"sensitive":null,
            "visibility":"public","idempotency":null,"scheduled_at":null,
            "spoiler_text":null,"application_id":3,"in_reply_to_id":null,
            "with_rate_limit":false},"media_attachments":[]}
            """#
        let response = try PostResponse(
            decoding: Data(json.utf8), scheduledAt: Date(timeIntervalSince1970: 1_793_610_000))

        guard case .scheduled(let scheduled) = response else {
            Issue.record("expected a scheduled post, got \(response)")
            return
        }
        #expect(scheduled.id == "3221")
        #expect(scheduled.params.text == "Later")
    }

    @Test("A scheduled post is a success, and leaves no draft behind")
    func composerSchedules() async throws {
        let (session, transport) = try await makeSession()
        let model = ComposerModel(session: session)
        model.text = "See you tomorrow"
        let when = Date().addingTimeInterval(24 * 3600)
        model.scheduledAt = when

        #expect(await model.post(skippingAltTextCheck: true))

        #expect(model.errorMessage == nil)
        let scheduledFor = try #require(model.scheduledFor)
        #expect(abs(scheduledFor.timeIntervalSince(when)) < 1)
        #expect(await transport.posts.count == 1)
        #expect(try await session.supportStore.drafts(accountID: session.id).isEmpty)
        // It is on the server's list, which is where the person finds it.
        let listed = try await session.client.decode(
            [ScheduledStatus].self, from: Endpoint.composing.scheduled)
        #expect(listed.map(\.params.text) == ["See you tomorrow"])
    }

    @Test("A time already past posts at once, and that counts as posted too")
    func pastTimePostsNow() async throws {
        let (session, _) = try await makeSession()
        let model = ComposerModel(session: session)
        model.text = "Late already"
        model.scheduledAt = Date().addingTimeInterval(-60)

        #expect(await model.post(skippingAltTextCheck: true))
        #expect(model.scheduledFor == nil)
        #expect(try await session.supportStore.drafts(accountID: session.id).isEmpty)
    }

    @Test("The send queue schedules a queued post once and only once")
    func queueSchedulesOnce() async throws {
        let (session, transport) = try await makeSession()
        _ = try await session.supportStore.saveDraft(
            DraftSnapshot(
                accountID: session.id, text: "Queued for later",
                scheduledAt: Date().addingTimeInterval(3600), queuedForSend: true))

        #expect(await SendQueue.drain(session: session) == 1)
        #expect(await SendQueue.drain(session: session) == 0)

        #expect(await transport.posts.count == 1)
        #expect(try await session.supportStore.drafts(accountID: session.id).isEmpty)
    }

    @Test("A thread is not scheduled, from the composer or from the queue")
    func threadsAreNotScheduled() async throws {
        let (session, transport) = try await makeSession()
        let model = ComposerModel(session: session)
        model.text = "one"
        model.threadSegments = ["two"]
        model.scheduledAt = Date().addingTimeInterval(3600)

        #expect(await model.post(skippingAltTextCheck: true) == false)
        #expect(model.errorMessage == ComposerModel.threadCannotBeScheduled)

        let id = try await session.supportStore.saveDraft(
            DraftSnapshot(
                accountID: session.id, text: "one",
                scheduledAt: Date().addingTimeInterval(3600), queuedForSend: true,
                threadSegments: ["two"]))
        _ = await SendQueue.drain(session: session)

        #expect(await transport.posts.isEmpty)
        let kept = try #require(try await session.supportStore.drafts(accountID: session.id).first)
        #expect(kept.id == id)
        #expect(kept.lastSendError == ComposerModel.threadCannotBeScheduled)
    }
}

@Suite("Posting while an upload is under way")
@MainActor
struct UploadInFlightTests {
    @Test("Nothing posts while a file is still going up")
    func postWaitsForUpload() async throws {
        let (session, transport) = try await makeSession()
        await transport.holdUploads()
        let model = ComposerModel(session: session)
        model.text = "With a video"

        let upload = Task {
            await model.uploader.add(
                data: Data(repeating: 1, count: 64), filename: "wave.mp4", mimeType: "video/mp4")
        }
        while model.uploader.activeUploads == 0 { await Task.yield() }

        #expect(model.canPost == false)
        // `post()` minds the gate itself: a shortcut or an intent never
        // passes the button.
        #expect(await model.post(skippingAltTextCheck: true) == false)
        #expect(await transport.posts.isEmpty)

        await transport.releaseUploads()
        await upload.value

        #expect(model.canPost)
        #expect(await model.post(skippingAltTextCheck: true))
        #expect(await transport.posts.count == 1)
    }

    @Test("Closing mid-upload keeps the file: it joins the same draft once it lands")
    func closingKeepsUpload() async throws {
        let (session, transport) = try await makeSession()
        await transport.holdUploads()
        let model = ComposerModel(session: session)
        model.text = "Half written"

        let upload = Task {
            await model.uploader.add(
                data: Data(repeating: 1, count: 64), filename: "wave.mp4", mimeType: "video/mp4")
        }
        while model.uploader.activeUploads == 0 { await Task.yield() }

        // What closing does: save now, then again when the upload settles.
        await model.saveDraftIfNeeded()
        let settling = Task { await model.saveDraftWhenUploadsSettle() }
        await transport.releaseUploads()
        await upload.value
        await settling.value

        let drafts = try await session.supportStore.drafts(accountID: session.id)
        #expect(drafts.count == 1)
        #expect(drafts.first?.text == "Half written")
        #expect(drafts.first?.uploadedMediaIDs == ["media-1"])
    }

    @Test("A late save after closing never undoes the same draft reopened and edited")
    func lateSaveYields() async throws {
        let (session, transport) = try await makeSession()
        await transport.holdUploads()
        let model = ComposerModel(session: session)
        model.text = "Half written"

        let upload = Task {
            await model.uploader.add(
                data: Data(repeating: 1, count: 64), filename: "wave.mp4", mimeType: "video/mp4")
        }
        while model.uploader.activeUploads == 0 { await Task.yield() }
        await model.saveDraftIfNeeded()
        let settling = Task { await model.saveDraftWhenUploadsSettle() }

        // Reopened from Drafts while the file is still going up, and finished.
        let saved = try #require(try await session.supportStore.drafts(accountID: session.id).first)
        let reopened = ComposerModel(session: session, draft: saved)
        reopened.text = "Fully written"
        await reopened.saveDraftIfNeeded()

        await transport.releaseUploads()
        await upload.value
        await settling.value

        let drafts = try await session.supportStore.drafts(accountID: session.id)
        #expect(drafts.map(\.text) == ["Fully written"])
    }

    @Test("A late save after closing never brings back a draft posted since")
    func lateSaveAfterPost() async throws {
        let (session, transport) = try await makeSession()
        await transport.holdUploads()
        let model = ComposerModel(session: session)
        model.text = "Half written"

        let upload = Task {
            await model.uploader.add(
                data: Data(repeating: 1, count: 64), filename: "wave.mp4", mimeType: "video/mp4")
        }
        while model.uploader.activeUploads == 0 { await Task.yield() }
        await model.saveDraftIfNeeded()
        let settling = Task { await model.saveDraftWhenUploadsSettle() }

        let saved = try #require(try await session.supportStore.drafts(accountID: session.id).first)
        let reopened = ComposerModel(session: session, draft: saved)
        #expect(await reopened.post(skippingAltTextCheck: true))

        await transport.releaseUploads()
        await upload.value
        await settling.value

        #expect(try await session.supportStore.drafts(accountID: session.id).isEmpty)
    }
}

@Suite("A shared movie handed over as a file")
@MainActor
struct FileUploadTests {
    private func file(size: UInt64) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "shared-test-\(UUID().uuidString).mp4")
        #expect(FileManager.default.createFile(atPath: url.path(), contents: Data("wave".utf8)))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: size)
        try handle.close()
        return url
    }

    @Test("It goes up from the file and is attached")
    func uploadsFromFile() async throws {
        let (session, transport) = try await makeSession()
        let model = ComposerModel(session: session)
        let url = try file(size: 1024)
        defer { try? FileManager.default.removeItem(at: url) }

        await model.uploader.add(fileAt: url, filename: "wave.mp4", mimeType: "video/mp4")

        #expect(model.uploader.attachments.map(\.id) == ["media-1"])
        #expect(await transport.log.contains("POST api/v2/media"))
    }

    @Test("One over the server's limit is refused by its size on disk, before any upload")
    func refusesBySize() async throws {
        let (session, transport) = try await makeSession()
        let model = ComposerModel(session: session)
        // Sparse: the size is on disk without the bytes being written.
        let url = try file(size: 200 * 1024 * 1024)
        defer { try? FileManager.default.removeItem(at: url) }

        await model.uploader.add(fileAt: url, filename: "long.mp4", mimeType: "video/mp4")

        #expect(model.uploader.attachments.isEmpty)
        #expect(model.uploader.errorMessage != nil)
        #expect(await transport.log.contains("POST api/v2/media") == false)
    }
}

@Suite("Saving the draft on the way to the background")
@MainActor
struct BackgroundDraftTests {
    @Test("A save on the way out and the one on closing are the same draft")
    func oneDraft() async throws {
        let (session, _) = try await makeSession()
        let model = ComposerModel(session: session)
        model.text = "Before the call"

        await model.preserveDraft()
        model.text = "Before the call, and after"
        await model.saveDraftIfNeeded()

        let drafts = try await session.supportStore.drafts(accountID: session.id)
        #expect(drafts.map(\.text) == ["Before the call, and after"])
    }

    @Test("A post that went out leaves no draft, whatever is saved after it")
    func postedLeavesNothing() async throws {
        let (session, _) = try await makeSession()
        let model = ComposerModel(session: session)
        model.text = "Out it goes"
        await model.preserveDraft()

        #expect(await model.post(skippingAltTextCheck: true))
        // The held-for-review notice keeps the composer up, and the app can
        // go to the background under it.
        await model.preserveDraft()
        await model.saveDraftIfNeeded()

        #expect(try await session.supportStore.drafts(accountID: session.id).isEmpty)
    }

    @Test("Emptying the box after a save takes that draft away")
    func emptiedDraftGoes() async throws {
        let (session, _) = try await makeSession()
        let model = ComposerModel(session: session)
        model.text = "Second thoughts"
        await model.preserveDraft()

        model.text = ""
        await model.saveDraftIfNeeded()

        #expect(try await session.supportStore.drafts(accountID: session.id).isEmpty)
    }

    @Test("A post waiting for the network stays queued when saved again")
    func queuedStaysQueued() async throws {
        let (session, transport) = try await makeSession()
        await transport.failPosts(with: .transport(URLError(.notConnectedToInternet)))
        let model = ComposerModel(session: session)
        model.text = "From the tunnel"

        #expect(await model.post(skippingAltTextCheck: true) == false)
        await model.preserveDraft()

        let queued = try await session.supportStore.queuedDrafts(accountID: session.id)
        #expect(queued.map(\.text) == ["From the tunnel"])
    }

    @Test("A post the queue sent while the composer stayed open is not queued again")
    func queueSentItOnce() async throws {
        let (session, transport) = try await makeSession()
        await transport.failPosts(with: .transport(URLError(.notConnectedToInternet)))
        let model = ComposerModel(session: session)
        model.text = "From the tunnel"
        #expect(await model.post(skippingAltTextCheck: true) == false)

        // Back online: the queue sends it, and the composer is still up.
        await transport.stopFailing()
        #expect(await SendQueue.drain(session: session) == 1)
        let attempts = await transport.posts.count

        // The app goes to the background under it and comes back.
        await model.preserveDraft()
        #expect(await SendQueue.drain(session: session) == 0)
        #expect(await transport.posts.count == attempts)

        // And closing leaves no draft of what went out.
        await model.saveDraftIfNeeded()
        #expect(try await session.supportStore.drafts(accountID: session.id).isEmpty)
    }

    @Test("Post after the queue sent it closes the composer without posting again")
    func postAfterQueueSent() async throws {
        let (session, transport) = try await makeSession()
        await transport.failPosts(with: .transport(URLError(.notConnectedToInternet)))
        let model = ComposerModel(session: session)
        model.text = "From the tunnel"
        #expect(await model.post(skippingAltTextCheck: true) == false)

        await transport.stopFailing()
        #expect(await SendQueue.drain(session: session) == 1)
        let attempts = await transport.posts.count

        #expect(await model.post(skippingAltTextCheck: true))
        #expect(await transport.posts.count == attempts)
    }
}

@Suite("Opening a reply")
@MainActor
struct ReplyPrefillTests {
    private func reply() -> Status {
        Status(id: "90", account: Account(id: "2", username: "bob", acct: "bob"))
    }

    @Test("An empty reply starts with the mentions")
    func mentionsFillEmptyBox() async throws {
        let (session, _) = try await makeSession()
        let model = ComposerModel(session: session, replyTo: reply())

        await model.prepare()

        #expect(model.text == "@bob ")
    }

    @Test("What was typed before the composer finished preparing is kept")
    func typedTextKept() async throws {
        let (session, _) = try await makeSession()
        let model = ComposerModel(session: session, replyTo: reply())
        model.text = "Already typing"

        await model.prepare()

        #expect(model.text == "Already typing")
    }

    @Test("Preparing again does not undo what was chosen since")
    func preparesOnce() async throws {
        let (session, _) = try await makeSession()
        let model = ComposerModel(session: session, replyTo: reply())
        await model.prepare()

        model.text = ""
        model.visibility = .direct
        await model.prepare()

        #expect(model.text.isEmpty)
        #expect(model.visibility == .direct)
    }
}

// MARK: - Support

@MainActor
private func makeSession() async throws -> (AccountSession, RecordingTransport) {
    let server = MockAPIServer(configuration: .mastodon43, statusCount: 3)
    let transport = RecordingTransport(server: server)
    let container = StoreContainer.make(inMemory: true)
    let accounts = AccountStore(modelContainer: container)
    let base = try #require(URL(string: "https://cloud.example.test/"))
    let snapshot = try await accounts.addAccount(
        instanceHost: "cloud.example.test", apiBase: base,
        account: Account(id: "1", username: "alice", acct: "alice"),
        capabilities: .minimal(apiBase: base))
    let session = AccountSession(
        snapshot: snapshot, token: "test-token", transport: transport,
        timelines: TimelineStore(modelContainer: container),
        support: SupportStore(modelContainer: container), accounts: accounts)
    return (session, transport)
}

/// The mock server, with every request written down and posts made to fail
/// on demand.
private actor RecordingTransport: HTTPTransport {
    struct Post: Sendable {
        var text: String?
        var inReplyToID: String?
        var idempotencyKey: String?
        var mediaIDs: [String] = []
    }

    let server: MockAPIServer
    private(set) var posts: [Post] = []
    private(set) var log: [String] = []
    private var postFailure: APIError?
    /// Only this post (1-based, counting every attempt) fails, when set.
    private var failingPostNumber: Int?

    init(server: MockAPIServer) { self.server = server }

    func failPosts(with error: APIError) {
        postFailure = error
        failingPostNumber = nil
    }

    func failPost(number: Int, with error: APIError) {
        postFailure = error
        failingPostNumber = number
    }

    func stopFailing() {
        postFailure = nil
        failingPostNumber = nil
    }

    /// Media uploads wait here until released, while uploads are held.
    private var uploadsHeld = false
    private var heldUploads: [CheckedContinuation<Void, Never>] = []
    private var uploadCount = 0

    func holdUploads() { uploadsHeld = true }

    func releaseUploads() {
        uploadsHeld = false
        for upload in heldUploads { upload.resume() }
        heldUploads = []
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path().trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        log.append("\(method) \(path)")

        // The mock server has no upload route; an upload is answered here,
        // with a finished attachment, once it is let through.
        if method == "POST", path == "api/v2/media", let url = request.url {
            if uploadsHeld { await withCheckedContinuation { heldUploads.append($0) } }
            uploadCount += 1
            let body = #"""
                {"id":"media-\#(uploadCount)","type":"video","url":"https://cloud.example.test/m.mp4",
                "preview_url":"https://cloud.example.test/m.jpg","remote_url":null,
                "description":"A wave","blurhash":null,"meta":{}}
                """#
            return (
                Data(body.utf8),
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }

        if method == "POST", path == "api/v1/statuses" {
            let fields = Self.form(request.httpBody)
            posts.append(
                Post(
                    text: fields["status"], inReplyToID: fields["in_reply_to_id"],
                    idempotencyKey: request.value(forHTTPHeaderField: "Idempotency-Key"),
                    mediaIDs: Self.mediaIDs(request.httpBody)))
            if let postFailure, failingPostNumber == nil || failingPostNumber == posts.count {
                throw postFailure
            }
        }
        return try await server.send(request)
    }

    private static func mediaIDs(_ body: Data?) -> [String] {
        guard let body, let string = String(data: body, encoding: .utf8) else { return [] }
        var components = URLComponents()
        components.percentEncodedQuery = string
        return (components.queryItems ?? []).filter { $0.name == "media_ids[]" }
            .compactMap(\.value)
    }

    private static func form(_ body: Data?) -> [String: String] {
        guard let body, let string = String(data: body, encoding: .utf8) else { return [:] }
        var components = URLComponents()
        components.percentEncodedQuery = string.replacingOccurrences(of: "+", with: "%20")
        var fields: [String: String] = [:]
        for item in components.queryItems ?? [] { fields[item.name] = item.value }
        return fields
    }
}
