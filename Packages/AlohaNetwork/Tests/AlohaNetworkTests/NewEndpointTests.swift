// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaNetwork

private func formItems(_ endpoint: Endpoint) -> [URLQueryItem] {
    guard case .form(let items) = endpoint.body else { return [] }
    return items
}

private func value(_ endpoint: Endpoint, _ name: String) -> String? {
    formItems(endpoint).first { $0.name == name }?.value
}

@Suite("Filter editing")
struct FilterEndpointTests {

    private let keywords: [Endpoint.filters.KeywordDraft] = [
        .init(id: "9", keyword: "spoilers", wholeWord: true),
        .init(keyword: "ending"),
        .init(id: "4", keyword: "gone", destroy: true),
    ]

    @Test("Keywords go out in Rails' nested-attributes shape")
    func nestedAttributes() {
        let endpoint = Endpoint.filters.create(
            title: "Spoilers", context: [.home, .public], action: .hide,
            expiresIn: 3600, keywords: keywords)

        #expect(endpoint.method == .post)
        #expect(endpoint.path == "api/v2/filters")
        #expect(value(endpoint, "keywords_attributes[0][keyword]") == "spoilers")
        #expect(value(endpoint, "keywords_attributes[0][whole_word]") == "1")
        #expect(value(endpoint, "keywords_attributes[0][id]") == "9")
        // A new keyword carries no id, which is how the server knows to add it.
        #expect(value(endpoint, "keywords_attributes[1][keyword]") == "ending")
        #expect(value(endpoint, "keywords_attributes[1][id]") == nil)
        #expect(value(endpoint, "keywords_attributes[1][whole_word]") == "0")
    }

    @Test("A removed keyword is sent with _destroy rather than left out")
    func destroyIsExplicit() {
        // The server leaves what it is not told about alone, so omitting a
        // removed keyword would keep it.
        let endpoint = Endpoint.filters.update(
            "3", title: "Spoilers", context: [.home], action: .warn,
            expiresIn: nil, keywords: keywords)
        #expect(endpoint.method == .put)
        #expect(endpoint.path == "api/v2/filters/3")
        #expect(value(endpoint, "keywords_attributes[2][_destroy]") == "1")
        #expect(value(endpoint, "keywords_attributes[2][id]") == "4")
    }

    @Test("Clearing an expiry sends an empty value, not nothing")
    func expiryIsAlwaysSent() {
        // Omitting it would keep an expiry the editor has just cleared.
        let cleared = Endpoint.filters.update(
            "3", title: "T", context: [.home], action: .warn, expiresIn: nil, keywords: [])
        #expect(value(cleared, "expires_in") == "")

        let set = Endpoint.filters.create(
            title: "T", context: [.home], action: .warn, expiresIn: 1800, keywords: [])
        #expect(value(set, "expires_in") == "1800")
    }

    @Test("Contexts are repeated as context[] and unknown ones are dropped")
    func contexts() {
        let endpoint = Endpoint.filters.create(
            title: "T", context: [.home, .notifications, .unknownCase], action: .warn,
            expiresIn: nil, keywords: [])
        let sent = formItems(endpoint).filter { $0.name == "context[]" }.compactMap(\.value)
        #expect(sent == ["home", "notifications"])
    }
}

@Suite("Moderation routes")
struct ModerationEndpointTests {

    @Test("The reports queue defaults to unresolved")
    func reports() {
        let endpoint = Endpoint.moderation.reports()
        #expect(endpoint.path == "api/v1/admin/reports")
        #expect(endpoint.query.first { $0.name == "resolved" }?.value == "false")
    }

    @Test("An account action carries the report it was taken from")
    func actionResolvesItsReport() {
        let endpoint = Endpoint.moderation.act(
            on: "12", action: .suspend, note: "spam", reportID: "7")
        #expect(endpoint.method == .post)
        #expect(endpoint.path == "api/v1/admin/accounts/12/action")
        #expect(value(endpoint, "type") == "suspend")
        #expect(value(endpoint, "text") == "spam")
        #expect(value(endpoint, "report_id") == "7")
    }

    @Test("An action with no note and no report sends neither")
    func actionWithoutExtras() {
        let endpoint = Endpoint.moderation.act(on: "12", action: .silence)
        #expect(value(endpoint, "type") == "silence")
        #expect(value(endpoint, "text") == nil)
        #expect(value(endpoint, "report_id") == nil)
    }

    @Test("`any` is the absence of a filter, not a filter of its own")
    func anyIsOmitted() {
        let unfiltered = Endpoint.moderation.accounts()
        #expect(unfiltered.query.first { $0.name == "origin" } == nil)
        #expect(unfiltered.query.first { $0.name == "status" } == nil)

        let filtered = Endpoint.moderation.accounts(origin: .remote, standing: .suspended)
        #expect(filtered.query.first { $0.name == "origin" }?.value == "remote")
        #expect(filtered.query.first { $0.name == "status" }?.value == "suspended")
    }

    @Test("A trend decision names its kind in the path")
    func trendDecisions() {
        #expect(
            Endpoint.moderation.rejectTrend(.tags, id: "nextcloud").path
                == "api/v1/admin/trends/tags/nextcloud/reject")
        #expect(
            Endpoint.moderation.approveTrend(.statuses, id: "9").path
                == "api/v1/admin/trends/statuses/9/approve")
    }
}

@Suite("Routes the app had wrong or lacked")
struct AddedEndpointTests {

    @Test("Pixelfed names a story with sid, never in the path")
    func storyExtras() {
        // `/api/v1/stories/{id}/viewers` does not exist on the server at all;
        // it 404s however reasonable it looks.
        #expect(Endpoint.storyExtras.viewers("8").path == "api/v1.2/stories/viewers")
        #expect(Endpoint.storyExtras.viewers("8").query.first?.name == "sid")
        #expect(Endpoint.storyExtras.viewers("8").query.first?.value == "8")
        #expect(Endpoint.storyExtras.reactions("8").path == "api/v1.2/stories/reactions")
        #expect(Endpoint.storyExtras.react("8", reaction: "🎉").path == "api/v1.2/stories/react")
        #expect(value(Endpoint.storyExtras.react("8", reaction: "🎉"), "sid") == "8")
        #expect(Endpoint.storyExtras.comment("8", caption: "hi").path == "api/v1.2/stories/comment")
        // Self-expire is the one v1.1 route of the four.
        #expect(Endpoint.storyExtras.selfExpire("8").path == "api/v1.1/stories/self-expire/8")
        #expect(Endpoint.storyExtras.selfExpire("8").method == .post)
    }

    @Test("A story reaction is clipped to what the server accepts")
    func reactionLength() {
        let long = String(repeating: "🎉", count: 40)
        #expect(value(Endpoint.storyExtras.react("1", reaction: long), "reaction")?.count == 20)
    }

    @Test("Deleting the Social account goes out on the Nextcloud credential")
    func deleteAccount() {
        let endpoint = Endpoint.socialAccount.delete(confirm: "@ada@cloud.example")
        #expect(endpoint.method == .post)
        #expect(endpoint.path == "api/v1/account/delete")
        #expect(endpoint.authentication == .nextcloudSession)
        #expect(value(endpoint, "confirm") == "@ada@cloud.example")
    }

    @Test("Everything else still goes out on the bearer token")
    func defaultAuthentication() {
        #expect(Endpoint.instance.peers.authentication == .bearer)
        #expect(Endpoint.filters.all.authentication == .bearer)
        #expect(Endpoint.moderation.reports().authentication == .bearer)
    }

    @Test("The three about-this-server routes need no viewer")
    func instanceAboutIsPublic() {
        #expect(!Endpoint.instance.peers.requiresAuthentication)
        #expect(!Endpoint.instance.activity.requiresAuthentication)
        #expect(!Endpoint.instance.domainBlocks.requiresAuthentication)
    }

    @Test("Annual report routes are built per year")
    func annualReports() {
        #expect(Endpoint.annualReports.all.path == "api/v1/annual_reports")
        #expect(Endpoint.annualReports.year(2025).path == "api/v1/annual_reports/2025")
        #expect(Endpoint.annualReports.state(2025).path == "api/v1/annual_reports/2025/state")
        #expect(Endpoint.annualReports.generate(2025).method == .post)
        #expect(Endpoint.annualReports.markRead(2025).path == "api/v1/annual_reports/2025/read")
    }

    @Test("A status's link preview is a public detail-screen request")
    func statusCard() {
        let endpoint = Endpoint.statuses.card("42")
        #expect(endpoint.path == "api/v1/statuses/42/card")
        #expect(!endpoint.requiresAuthentication)
    }

    @Test("The directory sends an order and never `local`")
    func directory() {
        let active = Endpoint.search.directory()
        #expect(active.path == "api/v1/directory")
        #expect(active.query.first { $0.name == "order" }?.value == "active")
        // Accepted by the server and ignored, so it is not sent.
        #expect(active.query.first { $0.name == "local" } == nil)
        #expect(!active.requiresAuthentication)

        let new = Endpoint.search.directory(order: .new, limit: 200, offset: -5)
        #expect(new.query.first { $0.name == "order" }?.value == "new")
        // Clamped to what the server will build, and never a negative offset.
        #expect(new.query.first { $0.name == "limit" }?.value == "50")
        #expect(new.query.first { $0.name == "offset" }?.value == "0")
    }

    @Test("Who a direct message can be started with")
    func directMessageMutuals() {
        #expect(Endpoint.timelines.directMessageMutuals.path == "api/v1.1/direct/compose/mutuals")
    }

    @Test("A collection item is removed by path, not by form body")
    func collectionItemRemoval() {
        // The server's route is `/items/{status_id}`; a DELETE to `/items`
        // carrying the id in the body matches nothing.
        let endpoint = Endpoint.collectionsExtra.removeItem("4", statusID: "91")
        #expect(endpoint.method == .delete)
        #expect(endpoint.path == "api/v1/collections/4/items/91")
        #expect(endpoint.body == nil)
    }

    @Test("Conversations can be emptied and cleared")
    func conversations() {
        #expect(Endpoint.timelines.markAllConversationsRead.method == .post)
        #expect(Endpoint.timelines.markAllConversationsRead.path == "api/v1/conversations/read_all")
        #expect(Endpoint.timelines.deleteConversation("5").method == .delete)
        #expect(Endpoint.timelines.deleteConversation("5").path == "api/v1/conversations/5")
    }
}
