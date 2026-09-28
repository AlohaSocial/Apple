// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AlohaStore
import AppIntents
import Foundation

/// Shortcuts, Siri and Spotlight all reach the app through these.
public struct PostStatusIntent: AppIntent {
    public static let title: LocalizedStringResource = "Post to Aloha Social"
    public static let description = IntentDescription("Posts a status from Aloha Social.")
    public static let openAppWhenRun = false

    @Parameter(title: "Text")
    public var text: String

    @Parameter(title: "Visibility", default: .public)
    public var visibility: VisibilityAppEnum

    public init() {}

    public init(text: String, visibility: VisibilityAppEnum = .public) {
        self.text = text
        self.visibility = visibility
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let context = await IntentContext.current() else {
            throw IntentError.noAccount
        }

        let draft = StatusPost(
            text: text,
            visibility: visibility.modelValue,
            // Generated per run, so a Shortcut that retries cannot double-post.
            idempotencyKey: UUID().uuidString)

        _ = try await context.client.decode(Status.self, from: Endpoint.composing.post(draft))
        return .result(dialog: "Posted.")
    }
}

public struct OpenTimelineIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open a feed in Aloha Social"
    public static let openAppWhenRun = true

    @Parameter(title: "Feed", default: .home)
    public var mode: FeedModeAppEnum

    public init() {}

    public func perform() async throws -> some IntentResult {
        await IntentNavigation.request(.timeline(TimelineKey(mode: mode.modelValue, source: .home)))
        return .result()
    }
}

public struct LatestMentionsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show my Aloha mentions"
    public static let openAppWhenRun = false

    @Parameter(title: "How many", default: 5)
    public var count: Int

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<[String]>
        & ProvidesDialog
    {
        guard let context = await IntentContext.current() else {
            throw IntentError.noAccount
        }

        let page = try await context.client.decode(
            LossyArray<MastodonNotification>.self,
            from: Endpoint.notifications.flat(limit: min(max(count, 1), 20), types: ["mention"]))

        let lines = page.elements.map { notification -> String in
            let body = (notification.status?.displayed.content ?? "")
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(notification.account.bestDisplayName): \(body)"
        }

        return .result(
            value: lines,
            dialog: lines.isEmpty
                ? "No mentions." : "You have \(lines.count) mentions.")
    }
}

public struct OpenShortsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Aloha Shorts"
    public static let openAppWhenRun = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        await IntentNavigation.request(.timeline(TimelineKey(mode: .shorts, source: .federated)))
        return .result()
    }
}

// MARK: - Enumerations

public enum VisibilityAppEnum: String, AppEnum {
    case `public`, unlisted, followers, direct

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Visibility")
    public static let caseDisplayRepresentations: [VisibilityAppEnum: DisplayRepresentation] = [
        .public: "Public",
        .unlisted: "Unlisted",
        .followers: "Followers only",
        .direct: "Direct",
    ]

    var modelValue: Visibility {
        switch self {
        case .public: .public
        case .unlisted: .unlisted
        case .followers: .private
        case .direct: .direct
        }
    }
}

public enum FeedModeAppEnum: String, AppEnum {
    case home, photos, video, shorts, news, audio

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Feed")
    public static let caseDisplayRepresentations: [FeedModeAppEnum: DisplayRepresentation] = [
        .home: "Home",
        .photos: "Photos",
        .video: "Video",
        .shorts: "Shorts",
        .news: "News",
        .audio: "Audio",
    ]

    var modelValue: FeedMode {
        FeedMode(rawValue: rawValue) ?? .home
    }
}

public enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case noAccount

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noAccount: "Add an account in Aloha Social first."
        }
    }
}

/// Builds a client for the active account without standing the whole app up —
/// an intent runs in its own process and has no `AppEnvironment`.
enum IntentContext {
    struct Context {
        let accountID: UUID
        let client: APIClient
    }

    @MainActor
    static func current() async -> Context? {
        let container = StoreContainer.make()
        let accounts = AccountStore(modelContainer: container)
        guard let snapshots = try? await accounts.allAccounts(),
            let active = activeSnapshot(from: snapshots)
        else { return nil }

        let credentials = CredentialStore.shared
        guard let token = (try? credentials.token(for: active.id)) ?? nil else { return nil }

        return Context(
            accountID: active.id,
            client: APIClient(
                accountID: active.id, apiBase: active.capabilities.apiBase, accessToken: token))
    }

    private static func activeSnapshot(
        from snapshots: [AccountStore.Snapshot]
    ) -> AccountStore.Snapshot? {
        let stored = AppGroup.defaults.string(forKey: AppGroup.activeAccountKey)
            .flatMap(UUID.init(uuidString:))
        return snapshots.first { $0.id == stored } ?? snapshots.first
    }
}

/// An intent that opens the app hands its destination through here.
public enum IntentNavigation {
    private static let key = AppGroup.pendingRouteKey

    @MainActor
    public static func request(_ route: Route) async {
        guard let data = try? JSONEncoder().encode(route) else { return }
        AppGroup.defaults.set(data, forKey: key)
    }

    @MainActor
    public static func take() -> Route? {
        guard let data = AppGroup.defaults.data(forKey: key) else { return nil }
        AppGroup.defaults.removeObject(forKey: key)
        return try? JSONDecoder().decode(Route.self, from: data)
    }
}

public struct AlohaShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PostStatusIntent(),
            phrases: [
                "Post to \(.applicationName)",
                "Write a post in \(.applicationName)",
            ],
            shortTitle: "Post",
            systemImageName: "square.and.pencil")

        AppShortcut(
            intent: LatestMentionsIntent(),
            phrases: [
                "Show my \(.applicationName) mentions",
                "What did I miss in \(.applicationName)",
            ],
            shortTitle: "Mentions",
            systemImageName: "at")

        AppShortcut(
            intent: OpenShortsIntent(),
            phrases: ["Open \(.applicationName) Shorts"],
            shortTitle: "Shorts",
            systemImageName: "play.square.stack")
    }
}
