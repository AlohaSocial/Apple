// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaNetwork

private func form(_ endpoint: Endpoint) -> [URLQueryItem] {
    guard case .form(let items) = endpoint.body else { return [] }
    return items
}

private func value(_ items: [URLQueryItem], _ name: String) -> String? {
    items.first { $0.name == name }?.value
}

private let base = URL(string: "https://cloud.example.test/")!

@Suite("A profile narrowed on the server")
struct ProfileFilterEndpointTests {
    @Test("Posts without boosts ask for exclude_reblogs and keep replies out")
    func postsWithoutBoosts() {
        let endpoint = Endpoint.timelines.timeline(
            .profile(id: "7", filter: ProfilePostFilter(includeBoosts: false)), limit: 20)
        #expect(endpoint.path == "api/v1/accounts/7/statuses")
        #expect(value(endpoint.query, "exclude_reblogs") == "true")
        #expect(value(endpoint.query, "exclude_replies") == "true")
        #expect(value(endpoint.query, "only_media") == nil)
    }

    @Test("A kind of media implies only_media, so a server without media_type still narrows")
    func mediaKind() {
        let endpoint = Endpoint.timelines.timeline(
            .profile(id: "7", filter: ProfilePostFilter(mediaKind: .video)), limit: 20)
        #expect(value(endpoint.query, "media_type") == "video")
        #expect(value(endpoint.query, "only_media") == "true")
    }

    @Test("A hashtag goes out without its # and lowercased, as the tag route takes it")
    func tagged() {
        let filter = ProfilePostFilter(tagged: "#Sailing")
        let endpoint = Endpoint.timelines.timeline(.profile(id: "7", filter: filter), limit: 20)
        #expect(value(endpoint.query, "tagged") == Tag.normalise("#Sailing"))
        #expect(value(endpoint.query, "tagged")?.hasPrefix("#") == false)
    }

    @Test("Each narrowing is its own cache key")
    func storageKeys() {
        let posts = TimelineSource.profile(id: "7", filter: .posts).storageKey
        let noBoosts = TimelineSource.profile(
            id: "7", filter: ProfilePostFilter(includeBoosts: false)
        ).storageKey
        let tagged = TimelineSource.profile(id: "7", filter: ProfilePostFilter(tagged: "a"))
            .storageKey
        #expect(Set([posts, noBoosts, tagged]).count == 3)
    }
}

@Suite("Moving, and the import queue")
struct MigrationEndpointTests {
    @Test("Moving away is a Nextcloud session route; moving here and the queue take the token")
    func credentials() {
        #expect(Endpoint.migration.moveStatus.authentication == .nextcloudSession)
        #expect(
            Endpoint.migration.moveAway(to: "a@b", confirm: "me@here", bluesky: .keep)
                .authentication == .nextcloudSession)
        #expect(Endpoint.migration.undoMove.authentication == .nextcloudSession)
        #expect(Endpoint.migration.imports.authentication == .bearer)
        #expect(Endpoint.migration.inspectMoveIn(handle: "a@b").authentication == .bearer)
        #expect(
            Endpoint.migration.moveIn(handle: "a@b", follows: true, posts: false, fetchMedia: true)
                .authentication == .bearer)
    }

    @Test("Moving here sends the server's 1 and 0 for each switch")
    func moveInForm() {
        let items = form(
            Endpoint.migration.moveIn(handle: "a@b", follows: true, posts: false, fetchMedia: true))
        #expect(value(items, "handle") == "a@b")
        #expect(value(items, "follows") == "1")
        #expect(value(items, "posts") == "0")
        #expect(value(items, "fetch_media") == "1")
    }

    @Test("Moving away names the target, the typed-back handle and what becomes of Bluesky")
    func moveAwayForm() {
        let endpoint = Endpoint.migration.moveAway(to: "a@b", confirm: "me@here", bluesky: .move)
        #expect(endpoint.method == .post)
        #expect(value(form(endpoint), "target") == "a@b")
        #expect(value(form(endpoint), "confirm") == "me@here")
        #expect(value(form(endpoint), "bluesky") == "move")
    }

    @Test("Followers cannot be imported; the other lists queue at their own routes")
    func listRoutes() {
        let csv = Data("a@b\n".utf8)
        #expect(Endpoint.migration.queueImport(.followers, csv: csv, filename: "f.csv") == nil)
        #expect(
            Endpoint.migration.queueImport(.following, csv: csv, filename: "f.csv")?.path
                == "api/v1/migration/follows")
        #expect(
            Endpoint.migration.queueImport(.domainBlocks, csv: csv, filename: "f.csv")?.path
                == "api/v1/migration/domain_blocks")
        #expect(Endpoint.migration.export(.bookmarks).path == "api/v1/migration/export/bookmarks")
        #expect(
            Endpoint.migration.export(.domainBlocks).path
                == "api/v1/migration/export/domain_blocks")
    }
}

@Suite("Bluesky discovery")
struct BlueskyDiscoveryEndpointTests {
    @Test("Every discovery route goes out with the app password")
    func credentials() {
        #expect(Endpoint.bluesky.trends.authentication == .nextcloudSession)
        #expect(Endpoint.bluesky.suggestions.authentication == .nextcloudSession)
        #expect(Endpoint.bluesky.starterPack("x").authentication == .nextcloudSession)
        #expect(Endpoint.bluesky.followFrom("x").authentication == .nextcloudSession)
        #expect(Endpoint.bluesky.setHandle("x.example").authentication == .nextcloudSession)
        #expect(Endpoint.bluesky.clearHandle.method == .delete)
    }

    @Test("Following a pack's members sends dids[] and whether to keep its feeds")
    func followStarterPack() {
        let items = form(
            Endpoint.bluesky.followStarterPack("at://pack", dids: ["d1", "d2"], keepFeeds: true))
        #expect(value(items, "pack") == "at://pack")
        #expect(items.filter { $0.name == "dids[]" }.map(\.value) == ["d1", "d2"])
        #expect(value(items, "feeds") == "1")
    }

    @Test("A starter pack is asked for by its address, in the query")
    func starterPackQuery() {
        let endpoint = Endpoint.bluesky.starterPack("https://bsky.app/starter-pack/a/b")
        #expect(value(endpoint.query, "pack") == "https://bsky.app/starter-pack/a/b")
    }
}

@Suite("The smaller routes")
struct ServerExtrasEndpointTests {
    @Test("The files-comments switch is a JSON boolean")
    func filesComments() throws {
        guard case .json(let data) = Endpoint.readerSettings.setFilesComments(enabled: true).body
        else {
            Issue.record("not a JSON body")
            return
        }
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["enabled"] as? Bool == true)
    }

    @Test("One post on a filter goes by status_id, and comes off by the entry's own id")
    func filterStatuses() {
        let add = Endpoint.filters.addStatus("42", to: "9")
        #expect(add.path == "api/v2/filters/9/statuses")
        #expect(value(form(add), "status_id") == "42")
        #expect(
            Endpoint.filters.removeStatus(entryID: "5").path == "api/v2/filters/statuses/5")
    }
}

@Suite("New routes against the mock server")
struct ServerFeatureMockTests {
    private func client(
        _ configuration: MockAPIServer.Configuration = .nextcloudSocialWithRewrite
    ) -> APIClient {
        APIClient(
            accountID: UUID(), apiBase: base, accessToken: "token",
            transport: MockAPIServer(configuration: configuration))
    }

    @Test("A queued import answers 202 with the job, and the queue lists it")
    func queuedImport() async throws {
        let client = client()
        let csv = Data("example.com\n".utf8)
        let endpoint = try #require(
            Endpoint.migration.queueImport(.domainBlocks, csv: csv, filename: "d.csv"))
        let queued = try await client.decode(MigrationQueued.self, from: endpoint)
        let job = try #require(queued.job)
        #expect(job.kind == .domainBlocks)
        let list = try await client.decode(MigrationImportList.self, from: .migration.imports)
        #expect(list.imports.contains { $0.id == job.id })
        let after = try await client.decode(
            MigrationImportList.self, from: .migration.dismissImport(job.id))
        #expect(!after.imports.contains { $0.id == job.id })
    }

    @Test("Moving here reads the old account first, and says which lists are hidden there")
    func inspectMoveIn() async throws {
        let found = try await client().decode(
            MoveInInspection.self, from: .migration.inspectMoveIn(handle: "old@old.example")
        ).account
        #expect(found.acct == "old@old.example")
        #expect(found.following.readable)
        #expect(!found.posts.readable)
        #expect(found.finishable)
    }

    @Test("Moving away needs the app password, and the handle typed back")
    func moveAway() async throws {
        let client = client()
        await #expect(throws: APIError.self) {
            try await client.decode(AccountMoveStatus.self, from: .migration.moveStatus)
        }
        await client.updateNextcloudAuthorization("Basic eDp5")
        let before = try await client.decode(AccountMoveStatus.self, from: .migration.moveStatus)
        #expect(!before.hasMoved)
        await #expect(throws: APIError.self) {
            try await client.decode(
                AccountMoveStatus.self,
                from: .migration.moveAway(to: "a@new.example", confirm: "wrong", bluesky: .keep))
        }
        _ = try await client.decode(AccountMoveStatus.self, from: .migration.undoMove)
    }

    @Test("A starter pack's members are followed by DID")
    func followStarterPack() async throws {
        let client = client()
        await client.updateNextcloudAuthorization("Basic eDp5")
        let pack = try await client.decode(
            BlueskyStarterPackEnvelope.self, from: .bluesky.starterPack("https://bsky.app/x")
        ).pack
        #expect(pack.members.count == 2)
        let toFollow = pack.members.filter { !$0.following }.map(\.did)
        let result = try await client.decode(
            BlueskyStarterPackFollowResult.self,
            from: .bluesky.followStarterPack(pack.uri, dids: toFollow, keepFeeds: false))
        #expect(result.followed == toFollow)
    }

    @Test("Reactions are counted again on request")
    func reactions() async throws {
        let reactions = try await client().decode(
            [Status.Reaction].self, from: .statuses.reactions("1"))
        #expect(reactions.first?.name == "🎉")
        #expect(reactions.first?.me == true)
    }

    @Test("Stock Mastodon has none of Aloha Social's routes")
    func mastodonHasNone() async {
        await #expect(throws: APIError.self) {
            try await client(.mastodon43).decode(
                MigrationImportList.self, from: .migration.imports)
        }
    }
}
