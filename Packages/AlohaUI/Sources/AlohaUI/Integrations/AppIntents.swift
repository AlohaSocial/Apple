// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AlohaStore
import AppIntents
import CryptoKit
import Foundation

/// Shortcuts, Siri and Spotlight all reach the app through these.
public struct PostStatusIntent: AppIntent {
    public static let title: LocalizedStringResource = "Post to Aloha Social"
    public static let description = IntentDescription("Posts a status from Aloha Social.")
    public static let openAppWhenRun = false
    /// Posting as someone takes their unlocked phone, not their voice: a
    /// spoken "yes" to the confirmation is no proof of who said it.
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Text")
    public var text: String

    /// Left empty, the post goes out with the account's own default
    /// visibility, the same one the composer starts from, not as public.
    @Parameter(title: "Visibility")
    public var visibility: VisibilityAppEnum?

    public init() {}

    public init(text: String, visibility: VisibilityAppEnum? = nil) {
        self.text = text
        self.visibility = visibility
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let context = await IntentContext.current() else {
            throw IntentError.noAccount
        }
        let visibility = visibility?.modelValue ?? context.defaultVisibility

        // A post is public speech under somebody's name: Siri or a Shortcut
        // says what will go out, and where, before it does.
        try await requestConfirmation(
            actionName: .post,
            dialog: "Post this as \(context.handle)? \(Self.preview(of: text))")

        let draft = StatusPost(
            text: text,
            visibility: visibility,
            idempotencyKey: Self.idempotencyKey(
                accountID: context.accountID, text: text, visibility: visibility))

        _ = try await context.client.decode(Status.self, from: Endpoint.composing.post(draft))
        return .result(dialog: "Posted.")
    }

    /// The same post, from the same account, within the same ten minutes
    /// gets the same key.
    ///
    /// A random key per run cannot stop a double post: a Shortcut or Siri
    /// that retries runs `perform` again, with a new key. Derived from what is
    /// posted, the retry carries the key the first attempt did, and the
    /// server answers it with the post it already made. The cost is that the
    /// very same words cannot be posted twice from a Shortcut inside one
    /// window, which is what a duplicate is.
    static func idempotencyKey(
        accountID: UUID, text: String, visibility: Visibility, now: Date = Date()
    ) -> String {
        let window = Int(now.timeIntervalSince1970 / 600)
        let material = "\(accountID.uuidString)|\(visibility.rawValue)|\(window)|\(text)"
        return SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// The opening of the post, for the confirmation: enough to recognise it.
    static func preview(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 80 else { return trimmed }
        return String(trimmed.prefix(80)) + "…"
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
    /// Mentions include direct messages, which a locked phone must not read
    /// aloud to whoever is holding it.
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

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
    case home, photos, video, shorts

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Feed")
    public static let caseDisplayRepresentations: [FeedModeAppEnum: DisplayRepresentation] = [
        .home: "Home",
        .photos: "Photos",
        .video: "Video",
        .shorts: "Shorts",
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
        let serverAccountID: String
        let client: APIClient
        /// `@name@server`, for anything that asks before acting as them.
        let handle: String
        /// What the composer starts a new post as.
        let defaultVisibility: Visibility
    }

    /// The running app's environment, when the intent runs inside the app.
    ///
    /// Shortcuts and Siri run most intents in the app's own process, where
    /// building a second container against the same store file is the
    /// failure `AppEnvironment` exists to prevent. The live one is used
    /// whenever there is one.
    @MainActor static weak var live: AppEnvironment?

    @MainActor
    static func current() async -> Context? {
        if let live {
            await live.loadIfNeeded()
            if let session = live.activeSession {
                return Context(
                    accountID: session.id, serverAccountID: session.snapshot.serverAccountID,
                    client: session.client, handle: session.snapshot.qualifiedHandle,
                    defaultVisibility: session.settings.defaultVisibility)
            }
            return nil
        }

        let accounts = AccountStore(modelContainer: StoreContainer.reader())
        guard let snapshots = try? await accounts.allAccounts(),
            let active = activeSnapshot(from: snapshots)
        else { return nil }

        let credentials = CredentialStore.shared
        guard let token = (try? credentials.token(for: active.id)) ?? nil else { return nil }

        return Context(
            accountID: active.id,
            serverAccountID: active.serverAccountID,
            client: APIClient(
                accountID: active.id, apiBase: active.capabilities.apiBase, accessToken: token),
            handle: active.qualifiedHandle,
            defaultVisibility: active.settings.defaultVisibility)
    }

    private static func activeSnapshot(
        from snapshots: [AccountStore.Snapshot]
    ) -> AccountStore.Snapshot? {
        let stored = AppGroup.defaults.string(forKey: AppGroup.activeAccountKey)
            .flatMap(UUID.init(uuidString:))
        return snapshots.first { $0.id == stored } ?? snapshots.first
    }
}

/// An intent that opens the app hands its destination through here, and so
/// does a tapped notification.
///
/// The route is stored, then announced: a running shell takes it at once, and
/// one that is still launching takes it when it starts. Taking it consumes it,
/// so the two paths cannot open the same screen twice.
public enum IntentNavigation {
    private static let key = AppGroup.pendingRouteKey

    /// Posted when a route has been left for the shell to take.
    public static let routeRequested = Notification.Name("aloha.routeRequested")

    @MainActor
    public static func request(_ route: Route) async {
        enqueue(route)
    }

    @MainActor
    public static func enqueue(_ route: Route) {
        guard let data = try? JSONEncoder().encode(route) else { return }
        AppGroup.defaults.set(data, forKey: key)
        NotificationCenter.default.post(name: routeRequested, object: nil)
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
