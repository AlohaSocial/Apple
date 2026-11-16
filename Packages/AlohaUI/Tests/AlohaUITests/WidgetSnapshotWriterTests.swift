// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaStore
import Foundation
import Testing

@testable import AlohaUI

@Suite("Widget snapshot writer")
struct WidgetSnapshotWriterTests {
    private let accountID = UUID()
    private let me = Account(id: "me", username: "me", acct: "me", displayName: "Me")
    private let ana = Account(id: "ana", username: "ana", acct: "ana", displayName: "Ana")
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func merge(
        _ fetched: WidgetSnapshotWriter.Fetched, previous: WidgetSnapshot? = nil,
        aloha: Bool = true
    ) -> WidgetSnapshot {
        WidgetSnapshotWriter.merge(
            fetched, into: previous, accountID: accountID, handle: "@me@example.com",
            serverAccountID: "me", aloha: aloha, now: now)
    }

    private func status(
        _ id: String, by account: Account? = nil, content: String = "<p>Hello</p>",
        sensitive: Bool = false, media: [MediaAttachment] = [], poll: Poll? = nil,
        at date: Date? = nil
    ) -> Status {
        Status(
            id: id, createdAt: date ?? now, content: content, sensitive: sensitive,
            account: account ?? ana, mediaAttachments: media, poll: poll)
    }

    private func picture(_ name: String) -> MediaAttachment {
        MediaAttachment(
            id: name, type: .image, url: URL(string: "https://example.com/\(name).jpg"),
            previewURL: URL(string: "https://example.com/\(name)-small.jpg"))
    }

    private func scheduled(_ id: String, in seconds: TimeInterval) throws -> ScheduledStatus {
        let at = ISO8601DateFormatter().string(from: now.addingTimeInterval(seconds))
        let json = """
            {"id": "\(id)", "scheduled_at": "\(at)", "media_attachments": [],
             "params": {"text": "Post \(id)", "sensitive": false}}
            """
        return try AlohaJSON.decoder.decode(ScheduledStatus.self, from: Data(json.utf8))
    }

    @Test("A section whose request failed keeps its last answer")
    func keepsFailedSections() {
        let previous = WidgetSnapshot(
            accountID: accountID, handle: "@me", writtenAt: now.addingTimeInterval(-3600),
            messages: .init(unread: 2, conversations: []), followRequests: 3,
            notificationRequests: 1, openReports: 4)
        var fetched = WidgetSnapshotWriter.Fetched()
        fetched.reports = .failed
        let merged = merge(fetched, previous: previous)
        #expect(merged.messages == previous.messages)
        #expect(merged.followRequests == 3)
        #expect(merged.notificationRequests == 1)
        #expect(merged.openReports == 4)
        #expect(merged.writtenAt == now)
    }

    @Test("A refused report queue means the account does not moderate")
    func refusedReports() {
        let previous = WidgetSnapshot(accountID: accountID, handle: "@me", openReports: 4)
        var fetched = WidgetSnapshotWriter.Fetched()
        fetched.reports = .refused
        #expect(merge(fetched, previous: previous).openReports == nil)
        fetched.reports = .count(0)
        #expect(merge(fetched, previous: previous).openReports == 0)
    }

    @Test("Conversations name the other people and count the unread")
    func conversations() {
        var fetched = WidgetSnapshotWriter.Fetched()
        fetched.conversations = [
            Conversation(
                id: "1", accounts: [me, ana], unread: true, lastStatus: status("10")),
            Conversation(id: "2", accounts: [me], unread: false, lastStatus: status("11", by: me)),
        ]
        let messages = merge(fetched).messages
        #expect(messages?.unread == 1)
        #expect(messages?.conversations.map(\.names) == ["Ana", "@me@example.com"])
        #expect(messages?.conversations.first?.text == "Hello")
        #expect(messages?.conversations.first?.lastStatusID == "10")
    }

    @Test("Scheduled posts already past are dropped, the soonest first")
    func scheduledPosts() throws {
        var fetched = WidgetSnapshotWriter.Fetched()
        fetched.scheduled = [
            try scheduled("late", in: 7200), try scheduled("past", in: -60),
            try scheduled("soon", in: 600),
        ]
        #expect(merge(fetched).scheduled?.map(\.id) == ["soon", "late"])
    }

    @Test("The newest own poll is shown while open, and for a day after it closes")
    func polls() {
        let open = Poll(
            id: "p", expiresAt: now.addingTimeInterval(3600), votersCount: 3,
            options: [.init(title: "Yes", votesCount: 2), .init(title: "No", votesCount: 1)])
        let closedLongAgo = Poll(
            id: "q", expiresAt: now.addingTimeInterval(-2 * 86_400), expired: true)
        let text: (Status) -> String = { _ in "Question?" }

        let shown = WidgetSnapshotWriter.poll(
            in: [status("1"), status("2", by: me, poll: open)], now: now, text: text)
        #expect(shown?.statusID == "2")
        #expect(shown?.totalVotes == 3)
        #expect(shown?.voters == 3)

        let stale = WidgetSnapshotWriter.poll(
            in: [status("3", by: me, poll: closedLongAgo)], now: now, text: text)
        #expect(stale == nil)

        let boosted = Status(
            id: "4", createdAt: now, account: me,
            reblog: Box(status("5", by: ana, poll: open)))
        #expect(WidgetSnapshotWriter.poll(in: [boosted], now: now, text: text) == nil)
    }

    @Test("A person whose request failed keeps their last row, in the order picked")
    func people() {
        let previousAna = WidgetSnapshot.Person(
            id: "ana", name: "Ana", handle: "ana", avatarFile: nil, latestText: "Old",
            latestDate: nil, latestStatusID: nil, hasNewStory: false)
        let previous = WidgetSnapshot(accountID: accountID, handle: "@me", people: [previousAna])
        var fetched = WidgetSnapshotWriter.Fetched()
        let ben = Account(id: "ben", username: "ben", acct: "ben", displayName: "Ben")
        fetched.people = ["ben": .init(account: ben, latest: status("20", by: ben))]
        fetched.unseenStoryAuthors = ["ben"]
        fetched.wantedPeople = ["ana", "ben"]

        let people = merge(fetched, previous: previous).people
        #expect(people.map(\.id) == ["ana", "ben"])
        #expect(people.first?.latestText == "Old")
        #expect(people.last?.latestText == "Hello")
        #expect(people.last?.hasNewStory == true)
    }

    @Test("Photos skip pictures behind a warning and stop at the widget's count")
    func photos() {
        var fetched = WidgetSnapshotWriter.Fetched()
        let statuses =
            [status("warned", sensitive: true, media: [picture("w")])]
            + (1...8).map { status("\($0)", media: [picture("p\($0)")]) }
        fetched.photos = ["home": statuses]
        fetched.wantedSources = ["home"]

        var snapshot = merge(fetched)
        let wanted = WidgetSnapshotWriter.pictures(
            for: fetched, serverAccountID: "me", in: &snapshot)
        let photos = snapshot.photoSet(for: .home)?.photos ?? []
        #expect(photos.count == WidgetSnapshotWriter.photosPerSource)
        #expect(!photos.contains { $0.statusID == "warned" })
        #expect(Set(wanted.map(\.name)).isSuperset(of: photos.map(\.imageFile)))
        #expect(wanted.allSatisfy { $0.url.absoluteString.hasSuffix("-small.jpg") })
    }

    @Test("A fresh snapshot is kept unless a widget asks for something it lacks")
    func refreshDecision() {
        let fresh = WidgetSnapshot(
            accountID: accountID, handle: "@me", writtenAt: now.addingTimeInterval(-60),
            photoSets: [.init(sourceKey: "home", photos: [])])
        #expect(
            !WidgetSnapshotWriter.needsRefresh(fresh, people: [], sources: [.home], now: now))
        #expect(
            WidgetSnapshotWriter.needsRefresh(fresh, people: ["ana"], sources: [], now: now))
        #expect(
            WidgetSnapshotWriter.needsRefresh(
                fresh, people: [], sources: [.hashtag("cats")], now: now))

        let old = WidgetSnapshot(
            accountID: accountID, handle: "@me",
            writtenAt: now.addingTimeInterval(-WidgetSnapshotWriter.minimumInterval))
        #expect(WidgetSnapshotWriter.needsRefresh(old, people: [], sources: [], now: now))
    }

    @Test("Followers are recorded into the history each day")
    func followerHistory() {
        var fetched = WidgetSnapshotWriter.Fetched()
        var account = me
        account.followersCount = 42
        fetched.me = account
        let stats = merge(fetched).stats
        #expect(stats?.followers == 42)
        #expect(stats?.history.map(\.followers) == [42])
    }
}
