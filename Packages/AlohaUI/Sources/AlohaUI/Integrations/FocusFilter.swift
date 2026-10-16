// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AlohaStore
import AppIntents
import Foundation

/// What the active Focus asks of the app: which account, which feed, and
/// whether anything but a mention may notify.
///
/// Stored, because the Focus is set by the system while the app may not be
/// running, and read wherever it applies — the shell when it comes to the
/// front, the notifier before it announces anything.
public struct FocusFilterState: Codable, Sendable, Hashable {
    /// The local account the Focus keeps the app on, or nil for any.
    public var accountID: UUID?
    /// The feed the app opens to under this Focus, or nil to leave it be.
    public var mode: FeedMode?
    /// Under this Focus only mentions notify.
    public var mentionsOnly: Bool

    public init(accountID: UUID? = nil, mode: FeedMode? = nil, mentionsOnly: Bool = false) {
        self.accountID = accountID
        self.mode = mode
        self.mentionsOnly = mentionsOnly
    }

    /// No Focus filter, or a Focus that asks for nothing.
    public static let none = FocusFilterState()

    static let key = "aloha.focusFilter"

    public static var current: FocusFilterState {
        guard let data = AppGroup.defaults.data(forKey: key),
            let state = try? JSONDecoder().decode(FocusFilterState.self, from: data)
        else { return .none }
        return state
    }

    static func store(_ state: FocusFilterState) {
        if state == .none {
            AppGroup.defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(state) {
            AppGroup.defaults.set(data, forKey: key)
        }
    }

    /// Whether a notification of this kind, for this account, may be raised
    /// under the Focus. Pure, so the rule is testable without a Focus.
    public func allows(kind: NotificationKind, accountID: UUID) -> Bool {
        if let required = self.accountID, required != accountID { return false }
        if mentionsOnly, kind != .mention { return false }
        return true
    }
}

/// The Focus filter Settings → Focus offers for Aloha Social.
public struct AlohaFocusFilter: SetFocusFilterIntent {
    public static let title = LocalizedStringResource(
        "Set Aloha Social filter", comment: "Focus filter title")
    public static let description = IntentDescription(
        LocalizedStringResource(
            "Choose the account and feed Aloha Social shows, and whether only mentions notify.",
            comment: "Focus filter description"))

    @Parameter(title: LocalizedStringResource("Account", comment: "Focus filter parameter"))
    public var account: SignedInAccountEntity?

    @Parameter(title: LocalizedStringResource("Open to", comment: "Focus filter parameter"))
    public var feed: FeedModeAppEnum?

    @Parameter(
        title: LocalizedStringResource("Only mentions notify", comment: "Focus filter parameter"),
        default: false)
    public var mentionsOnly: Bool

    public init() {}

    public var displayRepresentation: DisplayRepresentation {
        var parts: [String] = []
        if let account { parts.append(account.handle) }
        if mentionsOnly {
            parts.append(
                String(localized: "Mentions only", comment: "Focus filter summary"))
        }
        let title = LocalizedStringResource("Aloha Social", comment: "App name")
        return parts.isEmpty
            ? DisplayRepresentation(title: title)
            : DisplayRepresentation(title: title, subtitle: "\(parts.joined(separator: " · "))")
    }

    /// Notifications that arrive through the system — a push — are filtered
    /// by the account they carry in `filterCriteria`; the app's own are also
    /// checked before they are raised.
    public var appContext: FocusFilterAppContext {
        guard let account else { return FocusFilterAppContext(notificationFilterPredicate: nil) }
        return FocusFilterAppContext(
            notificationFilterPredicate: NSPredicate(format: "SELF == %@", account.id.uuidString))
    }

    /// The system calls this when the Focus turns on, and again with the
    /// defaults when it turns off — which stores "nothing asked".
    public func perform() async throws -> some IntentResult {
        FocusFilterState.store(
            FocusFilterState(
                accountID: account?.id, mode: feed?.modelValue, mentionsOnly: mentionsOnly))
        await IntentNavigation.announceFocusChange()
        return .result()
    }
}

/// One of the accounts signed in on this device — not somebody on the
/// fediverse, which is `PersonEntity`.
public struct SignedInAccountEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Account", comment: "App Intents type name"))
    public static let defaultQuery = SignedInAccountQuery()

    public let id: UUID
    public let handle: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(handle)")
    }
}

public struct SignedInAccountQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [SignedInAccountEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    @MainActor
    public func suggestedEntities() async throws -> [SignedInAccountEntity] {
        if let live = IntentContext.live {
            await live.loadIfNeeded()
            return live.sessions.map {
                SignedInAccountEntity(id: $0.id, handle: $0.snapshot.qualifiedHandle)
            }
        }
        let accounts = AccountStore(modelContainer: StoreContainer.make())
        return try await accounts.allAccounts().map {
            SignedInAccountEntity(id: $0.id, handle: $0.qualifiedHandle)
        }
    }
}

extension IntentNavigation {
    /// Posted when the Focus filter changed, for the shell to apply it.
    public static let focusChanged = Notification.Name("aloha.focusChanged")

    @MainActor
    static func announceFocusChange() async {
        NotificationCenter.default.post(name: focusChanged, object: nil)
    }
}
