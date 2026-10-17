// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AppIntents
import Foundation

/// The package's intents, entities and Focus filter, declared so the app's
/// App Intents metadata includes them: code in a Swift package is otherwise
/// invisible to Shortcuts, Siri and Spotlight, however it is linked.
public struct AlohaUIAppIntents: AppIntentsPackage {}

// MARK: - Posts

/// A post, as Shortcuts and Siri can name it: "open this post", or a post
/// passed from one action to the next.
///
/// Its id is the active account's server id for it, which is the only one a
/// client can look a post up by.
public struct PostEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Post", comment: "App Intents type name"))
    public static let defaultQuery = PostEntityQuery()

    public let id: String
    public let author: String
    public let text: String
    public let url: URL?

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(author)", subtitle: "\(text)")
    }

    init(_ status: Status) {
        let target = status.displayed
        self.id = target.id
        self.author = target.account.bestDisplayName
        self.text = IntentText.plain(target.content)
        self.url = target.url
    }
}

public struct PostEntityQuery: EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [PostEntity] {
        guard let context = await IntentContext.current() else { throw IntentError.noAccount }
        var found: [PostEntity] = []
        for id in identifiers {
            if let status = try? await context.client.decode(
                Status.self, from: Endpoint.statuses.status(id))
            {
                found.append(PostEntity(status))
            }
        }
        return found
    }

    /// What a person chose to keep is what they are likely to ask for.
    public func suggestedEntities() async throws -> [PostEntity] {
        guard let context = await IntentContext.current() else { throw IntentError.noAccount }
        let bookmarks = try await context.client.decode(
            LossyArray<Status>.self, from: Endpoint.timelines.timeline(.bookmarks, limit: 20))
        return bookmarks.elements.map(PostEntity.init)
    }

    public func entities(matching string: String) async throws -> [PostEntity] {
        guard let context = await IntentContext.current() else { throw IntentError.noAccount }
        let results = try await context.client.decode(
            SearchResults.self,
            from: Endpoint.search.search(string, type: "statuses", limit: 20))
        return results.statuses.map(PostEntity.init)
    }
}

// MARK: - People

/// Somebody on the fediverse, as the active account's server knows them.
public struct PersonEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Person", comment: "App Intents type name"))
    public static let defaultQuery = PersonEntityQuery()

    public let id: String
    public let name: String
    public let handle: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "@\(handle)")
    }

    init(_ account: Account) {
        self.id = account.id
        self.name = account.bestDisplayName
        self.handle = account.acct
    }
}

public struct PersonEntityQuery: EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [PersonEntity] {
        guard let context = await IntentContext.current() else { throw IntentError.noAccount }
        var found: [PersonEntity] = []
        for id in identifiers {
            if let account = try? await context.client.decode(
                Account.self, from: Endpoint.accounts.account(id))
            {
                found.append(PersonEntity(account))
            }
        }
        return found
    }

    /// The people you follow: the ones you are most likely to mean.
    public func suggestedEntities() async throws -> [PersonEntity] {
        guard let context = await IntentContext.current() else { throw IntentError.noAccount }
        let following = try await context.client.decode(
            LossyArray<Account>.self,
            from: Endpoint.accounts.following(context.serverAccountID, limit: 40))
        return following.elements.map(PersonEntity.init)
    }

    public func entities(matching string: String) async throws -> [PersonEntity] {
        guard let context = await IntentContext.current() else { throw IntentError.noAccount }
        let results = try await context.client.decode(
            SearchResults.self,
            from: Endpoint.search.search(string, type: "accounts", limit: 20))
        return results.accounts.map(PersonEntity.init)
    }
}

// MARK: - Intents that use them

public struct OpenPostIntent: AppIntent {
    public static let title = LocalizedStringResource(
        "Open a post in Aloha Social", comment: "App Intent title")
    public static let openAppWhenRun = true

    @Parameter(title: LocalizedStringResource("Post", comment: "App Intent parameter"))
    public var post: PostEntity

    public init() {}

    public func perform() async throws -> some IntentResult {
        await IntentNavigation.request(.thread(statusID: post.id))
        return .result()
    }
}

public struct OpenProfileIntent: AppIntent {
    public static let title = LocalizedStringResource(
        "Open a profile in Aloha Social", comment: "App Intent title")
    public static let openAppWhenRun = true

    @Parameter(title: LocalizedStringResource("Person", comment: "App Intent parameter"))
    public var person: PersonEntity

    public init() {}

    public func perform() async throws -> some IntentResult {
        await IntentNavigation.request(.profile(accountID: person.id))
        return .result()
    }
}

/// Status HTML, as one line of plain text for a Shortcuts row. Pure, and
/// used from entity initialisers the system runs off the main actor.
nonisolated enum IntentText {
    static func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
