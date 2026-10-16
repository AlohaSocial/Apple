// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaModels

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try AlohaJSON.decoder.decode(type, from: Data(json.utf8))
}

@Suite("The import queue and moving")
struct MigrationQueueDecodingTests {
    @Test("A job decodes as ImportJob::jsonSerialize exports it")
    func job() throws {
        let job = try decode(
            MigrationImport.self,
            #"""
            {"id": 12, "kind": "domain_blocks", "status": "running", "total": 10, "done": 4,
             "skipped": 1, "failed": 0, "report": {"followed": 4}, "options": {},
             "created_at": "2026-10-16T10:00:00Z", "updated_at": "2026-10-16T10:01:00Z"}
            """#)
        #expect(job.id == "12")
        #expect(job.kind == .domainBlocks)
        #expect(job.status == .running)
        #expect(job.status.isActive)
        #expect(job.progress == 0.5)
        #expect(job.report.lines.first?.key == "followed")
        #expect(job.createdAt != nil)
    }

    @Test("A kind or status newer than the app is kept, not a failure")
    func unknownValues() throws {
        let job = try decode(
            MigrationImport.self, #"{"id": "3", "kind": "photos_v2", "status": "paused"}"#)
        #expect(job.kind == .other("photos_v2"))
        #expect(job.status == .unknown)
        #expect(job.progress == nil)
        #expect(!job.status.isActive)
    }

    @Test("A queued answer carries the job, and follow-from the account it found")
    func queued() throws {
        let answer = try decode(
            MigrationQueued.self,
            #"""
            {"import": {"id": 1, "kind": "bluesky_follows", "status": "queued"},
             "account": {"did": "did:plc:x", "handle": "x.bsky.social"}}
            """#)
        #expect(answer.job?.kind == .blueskyFollows)
        #expect(answer.account?.handle == "x.bsky.social")
    }

    @Test("An older server's synchronous report is not mistaken for a queued job")
    func synchronousReport() throws {
        let answer = try decode(MigrationQueued.self, #"{"followed": 3, "skipped": 0}"#)
        #expect(answer.job == nil)
    }

    @Test("A broken job does not take the list down")
    func lossyList() throws {
        let list = try decode(
            MigrationImportList.self,
            #"{"imports": [{"id": 1, "kind": "follows", "status": "done"}, {"kind": "x"}]}"#)
        #expect(list.imports.count == 1)
    }

    @Test("Never moved is no date, not 1970; a move carries both dates")
    func moveStatus() throws {
        let never = try decode(
            AccountMoveStatus.self, #"{"moved_to": null, "moved_at": null, "can_move_at": 0}"#)
        #expect(!never.hasMoved)
        #expect(never.movedAt == nil)
        #expect(never.canMoveAt == nil)
        let moved = try decode(
            AccountMoveStatus.self,
            #"""
            {"moved_to": "https://new.example/users/a", "moved_at": 1760000000,
             "can_move_at": 1762592000, "target": {"acct": "a@new.example", "url": "https://new.example/@a"}}
            """#)
        #expect(moved.hasMoved)
        #expect(moved.movedAt == Date(timeIntervalSince1970: 1_760_000_000))
        #expect(moved.target?.acct == "a@new.example")
    }

    @Test("The old account says which of its lists can be read")
    func candidate() throws {
        let found = try decode(
            MoveInInspection.self,
            #"""
            {"account": {"id": "https://old.example/users/a", "acct": "a@old.example", "name": "",
             "url": "", "avatar": "", "following": {"total": 3, "readable": true},
             "posts": {"total": 9, "readable": false}, "finishable": false}}
            """#
        ).account
        #expect(found.name == "")
        #expect(found.following.total == 3)
        #expect(found.following.readable)
        #expect(!found.posts.readable)
        #expect(found.avatar == nil)
    }

    @Test("A finish nobody started is none")
    func finishStatus() throws {
        let none = try decode(MoveInFinishStatus.self, #"{"status": "none", "acct": "", "at": 0}"#)
        #expect(none.status == .none)
        let failed = try decode(
            MoveInFinishStatus.self, #"{"status": "failed", "error": "took too long"}"#)
        #expect(failed.status == .failed)
        #expect(failed.error == "took too long")
    }
}

@Suite("Bluesky discovery")
struct BlueskyDiscoveryDecodingTests {
    @Test("A trend is a feed or a search")
    func trends() throws {
        let list = try decode(
            BlueskyTrendList.self,
            #"""
            {"trends": [{"topic": "a", "label": "A", "feed": "at://f", "search": ""},
                        {"topic": "b", "label": "", "feed": "", "search": "b"}]}
            """#)
        #expect(list.trends.count == 2)
        #expect(list.trends[0].feed == "at://f")
        #expect(list.trends[1].title == "b")
    }

    @Test("A suggestion's account-like shape and its escaped note are read")
    func suggestion() throws {
        let list = try decode(
            BlueskySuggestionList.self,
            #"""
            {"accounts": [{"id": "did:plc:c", "acct": "carol.bsky.social",
             "display_name": "Carol", "avatar": "", "note": "Birds &amp; boats"}]}
            """#)
        let person = try #require(list.accounts.first)
        #expect(person.did == "did:plc:c")
        #expect(person.handle == "carol.bsky.social")
        #expect(person.displayName == "Carol")
        #expect(person.note == "Birds & boats")
    }

    @Test("A starter pack with its creator, members and feeds")
    func starterPack() throws {
        let pack = try decode(
            BlueskyStarterPackEnvelope.self,
            #"""
            {"pack": {"uri": "at://p", "url": "https://bsky.app/starter-pack/c/p", "name": "P",
             "description": "", "joined": 4,
             "creator": {"did": "did:plc:c", "handle": "c.bsky.social", "name": "", "avatar": ""},
             "members": [{"did": "did:plc:1", "handle": "1.bsky.social", "name": "One",
                          "avatar": "", "description": "Hi", "following": true}],
             "feeds": [{"uri": "at://f", "type": "feed", "name": "F", "description": "",
                        "avatar": "", "creator": ""}]}}
            """#
        ).pack
        #expect(pack.joined == 4)
        #expect(pack.creator?.displayName == "c.bsky.social")
        #expect(pack.members.first?.following == true)
        #expect(pack.members.first?.note == "Hi")
        #expect(pack.feeds.count == 1)
    }

    @Test("A fediverse starter pack says where it comes from; the instance's own say nothing")
    func starterPackOrigin() throws {
        let read = try decode(
            StarterPack.self,
            #"""
            {"slug": "s", "name": "S", "handles": [], "size": 7, "source": "fediverse",
             "curator": "cura@mastodon.social", "url": "https://mastodon.social/@cura/c",
             "topic": "art", "language": "en", "unresolved": ["x@y"]}
            """#)
        #expect(read.source == .fediverse)
        #expect(read.curator == "cura@mastodon.social")
        #expect(read.topic == "art")
        #expect(read.unresolved == ["x@y"])
        let own = try decode(
            StarterPack.self,
            #"{"slug": "o", "name": "O", "source": null, "curator": null, "url": null}"#)
        #expect(own.source == nil)
        #expect(own.curator == nil)
        #expect(own.url == nil)
    }
}

@Suite("Statistics, and the smaller entities")
struct ServerExtrasDecodingTests {
    @Test("The new statistics blocks decode; an older answer without them still does")
    func statistics() throws {
        let stats = try decode(
            AccountStatistics.self,
            #"""
            {"engagement": {"likes": 3, "quotes": 2},
             "engagement_sources": {"servers": [{"host": "a.example", "count": 5}],
                                    "local_share": 40.0, "counted": 5},
             "audience": {"instances": [{"host": "b.example", "count": 2}], "local_share": 0,
                          "starter_pack_joins": 6, "by_month": {}, "counted": 2, "capped": false},
             "reach": {"followers": 9, "instances": 4,
                       "networks": [{"network": "bluesky", "posts": 3}]},
             "best": [{"id": 77, "url": "https://x", "published_at": "2026-10-01",
                       "excerpt": "Hello", "likes": 5, "boosts": 1, "replies": 2, "quotes": 1,
                       "score": 9}]}
            """#)
        #expect(stats.engagement["quotes"] == 2)
        #expect(stats.engagementSources?.servers.first?.host == "a.example")
        #expect(stats.engagementSources?.localShare == 40)
        #expect(stats.audience?.starterPackJoins == 6)
        #expect(stats.reach?.instances == 4)
        #expect(stats.reach?.networks.first?.posts == 3)
        #expect(stats.best.first?.id == "77")
        #expect(stats.best.first?.quotes == 1)

        let older = try decode(AccountStatistics.self, #"{"engagement": {"likes": 1}}"#)
        #expect(older.best.isEmpty)
        #expect(older.reach == nil)
        #expect(older.audience == nil)
    }

    @Test("The files-comments switch, and its absence")
    func filesComments() throws {
        #expect(try decode(FilesCommentsSetting.self, #"{"enabled": true}"#).enabled)
        #expect(!(try decode(FilesCommentsSetting.self, "{}").enabled))
    }

    @Test("A profile filter round-trips as the cache stores its timeline source")
    func profileSourceCodable() throws {
        let source = TimelineSource.profile(
            id: "7", filter: ProfilePostFilter(includeBoosts: false, tagged: "Art"))
        let data = try JSONEncoder().encode(source)
        #expect(try JSONDecoder().decode(TimelineSource.self, from: data) == source)
        guard case .profile(_, let filter) = source else { return }
        #expect(filter.tagged == "art")
    }
}
