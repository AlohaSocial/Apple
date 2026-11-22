// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AlohaStore
import AppIntents
import Foundation

// MARK: - People

/// Somebody on the fediverse, as one account's server knows them: a Photo
/// frame's source.
///
/// Its id carries the local account, so a person picked under one account is
/// never looked up under another, where the same id is somebody else. Names
/// are asked for while the widget is being set up — the one moment a widget
/// may talk to the server — and kept for when it cannot be reached.
struct WidgetPersonEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Person", comment: "Widget configuration type name"))
    static let defaultQuery = WidgetPersonQuery()

    /// `<account UUID>/<server account id>`.
    let id: String
    let name: String
    let handle: String

    var personID: String? { id.split(separator: "/", maxSplits: 1).last.map(String.init) }
    var accountID: UUID? { id.split(separator: "/").first.flatMap { UUID(uuidString: String($0)) } }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(handle)")
    }
}

struct WidgetPersonQuery: EntityStringQuery {
    /// The account the people are offered for: the one picked in the Photo
    /// frame's settings, or the active one.
    @IntentParameterDependency<PhotoFrameConfiguration>(\.$account)
    var photoConfiguration

    private var pickedAccount: UUID? {
        photoConfiguration?.account.id
    }

    func entities(for identifiers: [String]) async throws -> [WidgetPersonEntity] {
        let cached = Self.cachedPeople()
        return identifiers.map { id in
            cached[id]
                ?? WidgetPersonEntity(
                    id: id,
                    name: String(
                        localized: "Person", comment: "Widget person with an unknown name"),
                    handle: "")
        }
    }

    /// The people the account follows, most recently followed first.
    func suggestedEntities() async throws -> [WidgetPersonEntity] {
        guard let (snapshot, client) = await Self.client(for: pickedAccount) else { return [] }
        let following = try await client.decode(
            LossyArray<Account>.self,
            from: Endpoint.accounts.following(snapshot.serverAccountID, limit: 80))
        return Self.entities(following.elements, accountID: snapshot.id)
    }

    /// Anybody the server can find by name or handle.
    func entities(matching string: String) async throws -> [WidgetPersonEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let (snapshot, client) = await Self.client(for: pickedAccount)
        else { return [] }
        let found = try await client.decode(
            LossyArray<Account>.self, from: Endpoint.accounts.search(query, limit: 20))
        return Self.entities(found.elements, accountID: snapshot.id)
    }

    @MainActor
    private static func client(
        for accountID: UUID?
    ) async -> (AccountStore.Snapshot, APIClient)? {
        guard let snapshot = await WidgetData.account(id: accountID),
            let token = try? CredentialStore.shared.token(for: snapshot.id)
        else { return nil }
        return (
            snapshot,
            APIClient(
                accountID: snapshot.id, apiBase: snapshot.capabilities.apiBase,
                accessToken: token)
        )
    }

    private static func entities(_ accounts: [Account], accountID: UUID) -> [WidgetPersonEntity] {
        let entities = accounts.map {
            WidgetPersonEntity(
                id: "\(accountID.uuidString)/\($0.id)", name: $0.bestDisplayName,
                handle: "@\($0.acct)")
        }
        cache(entities)
        return entities
    }

    /// The extension's own defaults: the names are only ever read here.
    private static let peopleKey = "aloha.widget.people"

    private static func cachedPeople() -> [String: WidgetPersonEntity] {
        let stored =
            UserDefaults.standard.dictionary(forKey: peopleKey) as? [String: [String]] ?? [:]
        return stored.compactMapValues { pair in
            pair.count == 3 ? WidgetPersonEntity(id: pair[0], name: pair[1], handle: pair[2]) : nil
        }
    }

    private static func cache(_ entities: [WidgetPersonEntity]) {
        var stored =
            UserDefaults.standard.dictionary(forKey: peopleKey) as? [String: [String]] ?? [:]
        for entity in entities { stored[entity.id] = [entity.id, entity.name, entity.handle] }
        UserDefaults.standard.set(stored, forKey: peopleKey)
    }
}

// MARK: - Photo frame

enum WidgetPhotoSourceChoice: String, AppEnum {
    case home, hashtag, person, list

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Photos from", comment: "Widget configuration type name"))
    static let caseDisplayRepresentations: [WidgetPhotoSourceChoice: DisplayRepresentation] = [
        .home: DisplayRepresentation(
            title: LocalizedStringResource("My Feed", comment: "Photo frame source")),
        .hashtag: DisplayRepresentation(
            title: LocalizedStringResource("A hashtag", comment: "Photo frame source")),
        .person: DisplayRepresentation(
            title: LocalizedStringResource("A person", comment: "Photo frame source")),
        .list: DisplayRepresentation(
            title: LocalizedStringResource("A list", comment: "Photo frame source")),
    ]
}

/// The Photo frame's configuration: whose server, and where the pictures
/// come from.
struct PhotoFrameConfiguration: WidgetConfigurationIntent {
    static let title = LocalizedStringResource("Photo frame", comment: "Widget configuration")
    static let description = IntentDescription(
        LocalizedStringResource(
            "Where the photos come from.", comment: "Widget configuration description"))

    @Parameter(title: LocalizedStringResource("Account", comment: "Widget configuration parameter"))
    var account: WidgetAccountEntity?

    @Parameter(
        title: LocalizedStringResource("Photos from", comment: "Widget configuration parameter"),
        default: .home)
    var source: WidgetPhotoSourceChoice

    @Parameter(title: LocalizedStringResource("Hashtag", comment: "Widget configuration parameter"))
    var hashtag: String?

    @Parameter(title: LocalizedStringResource("Person", comment: "Widget configuration parameter"))
    var person: WidgetPersonEntity?

    @Parameter(title: LocalizedStringResource("List", comment: "Widget configuration parameter"))
    var list: WidgetListEntity?

    static var parameterSummary: some ParameterSummary {
        Switch(\.$source) {
            Case(.hashtag) {
                Summary {
                    \.$account
                    \.$source
                    \.$hashtag
                }
            }
            Case(.person) {
                Summary {
                    \.$account
                    \.$source
                    \.$person
                }
            }
            Case(.list) {
                Summary {
                    \.$account
                    \.$source
                    \.$list
                }
            }
            DefaultCase {
                Summary {
                    \.$account
                    \.$source
                }
            }
        }
    }

    init() {}

    /// The source for the account shown, or nil where the choice needs a
    /// hashtag, person or list that is missing or belongs to another account.
    func photoSource(for accountID: UUID) -> WidgetPhotoSource? {
        switch source {
        case .home:
            return .home
        case .hashtag:
            let name = (hashtag ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            return name.isEmpty ? nil : .hashtag(name)
        case .person:
            guard let person, person.accountID == accountID, let id = person.personID else {
                return nil
            }
            return .account(id)
        case .list:
            guard let list, list.accountID == accountID, let id = list.listID else { return nil }
            return .list(id)
        }
    }
}
