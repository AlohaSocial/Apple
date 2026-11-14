// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AlohaStore
import AppIntents
import Foundation

// MARK: - Accounts

/// One of the accounts signed in on this device, picked from a list rather
/// than typed as a handle.
///
/// The widget's own copy of the app's `SignedInAccountEntity`, with the same
/// identity (the local account's UUID): the widget extension does not link
/// `AlohaUI`, whose size its memory budget cannot carry.
struct WidgetAccountEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Account", comment: "Widget configuration type name"))
    static let defaultQuery = WidgetAccountQuery()

    let id: UUID
    let handle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(handle)")
    }
}

struct WidgetAccountQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [WidgetAccountEntity] {
        await Self.all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetAccountEntity] {
        await Self.all()
    }

    @MainActor
    static func all() async -> [WidgetAccountEntity] {
        let store = AccountStore(modelContainer: StoreContainer.reader())
        let snapshots = (try? await store.allAccounts()) ?? []
        return snapshots.map { WidgetAccountEntity(id: $0.id, handle: $0.qualifiedHandle) }
    }
}

// MARK: - Feeds

/// Which cached timeline the Latest posts widget reads (docs/09 §8).
///
/// Each is a timeline the app caches under the home mode's key, so the widget
/// shows what the app last loaded and never fetches it itself. A feed the app
/// has not opened lately has nothing cached, and the widget says so.
enum WidgetFeed: String, AppEnum {
    case home, interests, local, federated, list

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Feed", comment: "Widget configuration type name"))
    static let caseDisplayRepresentations: [WidgetFeed: DisplayRepresentation] = [
        .home: DisplayRepresentation(
            title: LocalizedStringResource("Home", comment: "Widget feed choice")),
        .interests: DisplayRepresentation(
            title: LocalizedStringResource("For you", comment: "Widget feed choice")),
        .local: DisplayRepresentation(
            title: LocalizedStringResource("Local", comment: "Widget feed choice")),
        .federated: DisplayRepresentation(
            title: LocalizedStringResource("Federated", comment: "Widget feed choice")),
        .list: DisplayRepresentation(
            title: LocalizedStringResource("List", comment: "Widget feed choice")),
    ]

    /// The cache key the app stores this feed under: the mode, a colon and
    /// the source's storage key (`TimelineKey`).
    func timelineKey(listID: String?) -> String? {
        switch self {
        case .home: "home:\(TimelineSource.home.storageKey)"
        case .interests: "home:\(TimelineSource.interests.storageKey)"
        case .local: "home:\(TimelineSource.local.storageKey)"
        case .federated: "home:\(TimelineSource.federated.storageKey)"
        case .list: listID.map { "home:\(TimelineSource.list(id: $0).storageKey)" }
        }
    }
}

/// One of an account's lists.
///
/// Its id carries the account, so a list picked for one account is never read
/// under another. The titles are asked for while the widget is being set up —
/// the one moment a widget may talk to the server — and kept for the times
/// the server cannot be reached.
struct WidgetListEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("List", comment: "Widget configuration type name"))
    static let defaultQuery = WidgetListQuery()

    /// `<account UUID>/<list id>`.
    let id: String
    let title: String

    var listID: String? { id.split(separator: "/", maxSplits: 1).last.map(String.init) }
    var accountID: UUID? { id.split(separator: "/").first.flatMap { UUID(uuidString: String($0)) } }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct WidgetListQuery: EntityQuery {
    /// The account the lists are offered for: the one picked in the same
    /// configuration, or the active one.
    @IntentParameterDependency<WidgetAccount>(\.$account)
    var configuration

    func entities(for identifiers: [String]) async throws -> [WidgetListEntity] {
        let titles = Self.cachedTitles()
        return identifiers.map { id in
            WidgetListEntity(
                id: id,
                title: titles[id]
                    ?? String(localized: "List", comment: "Widget list with an unknown title"))
        }
    }

    func suggestedEntities() async throws -> [WidgetListEntity] {
        guard let snapshot = await WidgetData.account(id: configuration?.account.id),
            let token = try CredentialStore.shared.token(for: snapshot.id)
        else { return [] }
        let client = APIClient(
            accountID: snapshot.id, apiBase: snapshot.capabilities.apiBase, accessToken: token)
        let lists = try await client.decode(LossyArray<AccountList>.self, from: Endpoint.lists.all)
        let entities = lists.elements.map {
            WidgetListEntity(id: "\(snapshot.id.uuidString)/\($0.id)", title: $0.title)
        }
        Self.cache(entities)
        return entities
    }

    /// The extension's own defaults: the titles are only ever read here.
    private static let titlesKey = "aloha.widget.listTitles"

    private static func cachedTitles() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: titlesKey) as? [String: String] ?? [:]
    }

    private static func cache(_ entities: [WidgetListEntity]) {
        var titles = cachedTitles()
        for entity in entities { titles[entity.id] = entity.title }
        UserDefaults.standard.set(titles, forKey: titlesKey)
    }
}

// MARK: - Configurations

/// The Latest posts widget's configuration: whose posts, and which feed.
///
/// Keeps its name and its free-text `handle`, so a widget set up before the
/// account picker existed decodes as it was and still shows the account it
/// named; a picked account wins over a typed handle.
struct WidgetAccount: WidgetConfigurationIntent {
    static let title = LocalizedStringResource("Account and feed", comment: "Widget configuration")
    static let description = IntentDescription(
        LocalizedStringResource(
            "Which account and feed to show.", comment: "Widget configuration description"))

    @Parameter(title: LocalizedStringResource("Account", comment: "Widget configuration parameter"))
    var account: WidgetAccountEntity?

    @Parameter(
        title: LocalizedStringResource("Feed", comment: "Widget configuration parameter"),
        default: .home)
    var feed: WidgetFeed

    @Parameter(title: LocalizedStringResource("List", comment: "Widget configuration parameter"))
    var list: WidgetListEntity?

    /// Superseded by `account`; read only where `account` is unset.
    @Parameter(title: LocalizedStringResource("Handle", comment: "Widget configuration parameter"))
    var handle: String?

    static var parameterSummary: some ParameterSummary {
        When(\.$feed, .equalTo, .list) {
            Summary {
                \.$account
                \.$feed
                \.$list
            }
        } otherwise: {
            Summary {
                \.$account
                \.$feed
            }
        }
    }

    init() {}
}

/// Whose notifications: the Mentions and Unread widgets. Left unset, the
/// account the app last had active — and, for Unread, every account's total.
struct NotificationsWidgetAccount: WidgetConfigurationIntent {
    static let title = LocalizedStringResource("Account", comment: "Widget configuration")
    static let description = IntentDescription(
        LocalizedStringResource(
            "Which account to show.", comment: "Widget configuration description"))

    @Parameter(title: LocalizedStringResource("Account", comment: "Widget configuration parameter"))
    var account: WidgetAccountEntity?

    init() {}
}
