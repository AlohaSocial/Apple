// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AlohaStore
import AppIntents
import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// Shortcuts, Siri and Spotlight all reach the app through these.
public struct PostStatusIntent: AppIntent {
    public static let title: LocalizedStringResource = "Post to Aloha Social"
    public static let description = IntentDescription("Posts a status from Aloha Social.")
    public static let openAppWhenRun = false
    /// Posting as someone takes their unlocked phone, not their voice: a
    /// spoken "yes" to the confirmation is no proof of who said it.
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    /// As many attachments as a post takes on every server this app knows.
    static let maximumMedia = 4

    @Parameter(title: "Text")
    public var text: String

    /// Left empty, the post goes out with the account's own default
    /// visibility, the same one the composer starts from, not as public.
    @Parameter(title: "Visibility")
    public var visibility: VisibilityAppEnum?

    /// Pictures or videos from an earlier step — a photo from the Photos
    /// action, a screenshot (docs/09 §7).
    @Parameter(
        title: LocalizedStringResource("Media", comment: "App Intent parameter"),
        supportedContentTypes: [.image, .movie])
    public var media: [IntentFile]?

    /// Left empty, the account the app has active.
    @Parameter(title: LocalizedStringResource("Account", comment: "App Intent parameter"))
    public var account: SignedInAccountEntity?

    public init() {}

    public init(text: String, visibility: VisibilityAppEnum? = nil) {
        self.text = text
        self.visibility = visibility
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let context = await IntentContext.current(accountID: account?.id) else {
            throw IntentError.noAccount
        }
        let visibility = visibility?.modelValue ?? context.defaultVisibility
        let files = Array((media ?? []).prefix(Self.maximumMedia))

        // A post is public speech under somebody's name: Siri or a Shortcut
        // says what will go out, and where, before it does — and before any
        // picture has left the device.
        if files.isEmpty {
            try await requestConfirmation(
                actionName: .post,
                dialog: "Post this as \(context.handle)? \(Self.preview(of: text))")
        } else {
            try await requestConfirmation(
                actionName: .post,
                dialog:
                    "Post this with \(files.count) attachments as \(context.handle)? \(Self.preview(of: text))"
            )
        }

        // The key is worked out from what will be posted before anything is
        // uploaded: a retried run re-uploads its pictures (the server drops
        // the unused copies), but the post itself still comes back as the
        // one already made.
        let digests = files.map { Self.digest(of: $0.data) }
        let mediaIDs = try await MediaUploads.upload(files, client: context.client)
        let draft = StatusPost(
            text: text,
            visibility: visibility,
            mediaIDs: mediaIDs,
            idempotencyKey: Self.idempotencyKey(
                accountID: context.accountID, text: text, visibility: visibility,
                mediaDigests: digests))

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
    /// window, which is what a duplicate is. The attachments are part of
    /// what is posted, so the same words with another picture are another
    /// post.
    static func idempotencyKey(
        accountID: UUID, text: String, visibility: Visibility, mediaDigests: [String] = [],
        now: Date = Date()
    ) -> String {
        let window = Int(now.timeIntervalSince1970 / 600)
        var material = "\(accountID.uuidString)|\(visibility.rawValue)|\(window)|\(text)"
        if !mediaDigests.isEmpty { material += "|" + mediaDigests.joined(separator: ",") }
        return digest(of: Data(material.utf8))
    }

    static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The opening of the post, for the confirmation: enough to recognise it.
    static func preview(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 80 else { return trimmed }
        return String(trimmed.prefix(80)) + "…"
    }
}

/// Uploads for an intent, which has no composer and no `MediaUploader`.
enum MediaUploads {
    /// How long a video the server is transcoding is waited for before the
    /// post is tried anyway; the server has the last word on whether it is
    /// ready.
    static let processingPolls = 10
    static let processingInterval: Duration = .seconds(3)

    static func upload(_ files: [IntentFile], client: APIClient) async throws -> [String] {
        var ids: [String] = []
        for file in files {
            let type =
                file.type ?? UTType(filenameExtension: (file.filename as NSString).pathExtension)
            let mimeType = type?.preferredMIMEType ?? "application/octet-stream"
            let filename = file.filename.isEmpty ? "shared" : file.filename
            var attachment: MediaAttachment
            do {
                attachment = try await client.decode(
                    MediaAttachment.self,
                    from: Endpoint.media.upload(
                        data: file.data, filename: filename, mimeType: mimeType,
                        description: nil, v2: true))
            } catch APIError.notFound {
                // Modern clients POST v2 and only fall back to v1 on a 404.
                attachment = try await client.decode(
                    MediaAttachment.self,
                    from: Endpoint.media.upload(
                        data: file.data, filename: filename, mimeType: mimeType,
                        description: nil, v2: false))
            }
            var polls = 0
            while attachment.url == nil, polls < processingPolls {
                try await Task.sleep(for: processingInterval)
                attachment = try await client.decode(
                    MediaAttachment.self, from: Endpoint.media.attachment(attachment.id))
                polls += 1
            }
            ids.append(attachment.id)
        }
        return ids
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

    /// Left empty, the account the app has active.
    @Parameter(title: LocalizedStringResource("Account", comment: "App Intent parameter"))
    public var account: SignedInAccountEntity?

    public init() {}

    /// Posts rather than lines of text, so a Shortcut can open one, favourite
    /// it or pass it on; Siri still reads each one's author and text.
    public func perform() async throws -> some IntentResult & ReturnsValue<[PostEntity]>
        & ProvidesDialog
    {
        guard let context = await IntentContext.current(accountID: account?.id) else {
            throw IntentError.noAccount
        }

        let page = try await context.client.decode(
            LossyArray<MastodonNotification>.self,
            from: Endpoint.notifications.flat(limit: min(max(count, 1), 20), types: ["mention"]))

        // A mention whose post has since been deleted has nothing to open.
        let posts = page.elements.compactMap { $0.status.map(PostEntity.init) }

        return .result(
            value: posts,
            dialog: posts.isEmpty
                ? "No mentions." : "You have \(posts.count) mentions.")
    }
}

/// Opens search with the words already in it (docs/09 §7).
///
/// The search screen takes a query and nothing else, so there is no type to
/// pick here: it shows posts, people and hashtags together, as it does when
/// a person types.
public struct SearchIntent: AppIntent {
    public static let title = LocalizedStringResource(
        "Search Aloha Social", comment: "App Intent title")
    public static let openAppWhenRun = true

    @Parameter(title: LocalizedStringResource("Search for", comment: "App Intent parameter"))
    public var query: String

    public init() {}

    public func perform() async throws -> some IntentResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        await IntentNavigation.request(.search(query: trimmed.isEmpty ? nil : trimmed))
        return .result()
    }
}

/// Favourites a post, for automations: "favourite my partner's posts", or a
/// post handed on from Latest mentions.
public struct FavouriteStatusIntent: AppIntent {
    public static let title = LocalizedStringResource(
        "Favourite a post in Aloha Social", comment: "App Intent title")
    public static let openAppWhenRun = false
    /// Acting in the account's name from a locked phone is what the Lock
    /// Screen's own notification actions refuse too (`LocalNotifier`). No
    /// confirmation: it is undone with one tap, and an automation that asks
    /// every time is not one.
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: LocalizedStringResource("Post", comment: "App Intent parameter"))
    public var post: PostEntity

    /// Off takes the favourite back.
    @Parameter(
        title: LocalizedStringResource("Favourite", comment: "App Intent parameter"),
        default: true)
    public var favourite: Bool

    /// Left empty, the account the app has active.
    @Parameter(title: LocalizedStringResource("Account", comment: "App Intent parameter"))
    public var account: SignedInAccountEntity?

    public init() {}

    /// Already idempotent on the server: favouriting a favourite is a no-op
    /// that answers the post, so a retried run needs no key of its own.
    public func perform() async throws -> some IntentResult & ReturnsValue<PostEntity>
        & ProvidesDialog
    {
        guard let context = await IntentContext.current(accountID: account?.id) else {
            throw IntentError.noAccount
        }
        let updated = try await context.client.decode(
            Status.self,
            from: Endpoint.statuses.action(post.id, favourite ? .favourite : .unfavourite))
        // In the app's process the cache follows, so a timeline on screen
        // shows the heart; an intent run elsewhere leaves it to the next sync.
        await IntentContext.noteUpdated(updated, accountID: context.accountID)
        return .result(
            value: PostEntity(updated),
            dialog: favourite ? "Favourited." : "Removed from favourites.")
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

    /// The account named, or the active one when none is: an intent with an
    /// Account parameter acts as that account, not as whichever the app
    /// happens to have open. A named account that is not signed in here is
    /// no account at all, never a quiet fallback to another one.
    @MainActor
    static func current(accountID: UUID? = nil) async -> Context? {
        if let live {
            await live.loadIfNeeded()
            let session =
                accountID.map { id in live.sessions.first { $0.id == id } }
                ?? live.activeSession
            if let session {
                return Context(
                    accountID: session.id, serverAccountID: session.snapshot.serverAccountID,
                    client: session.client, handle: session.snapshot.qualifiedHandle,
                    defaultVisibility: session.settings.defaultVisibility)
            }
            return nil
        }

        let accounts = AccountStore(modelContainer: StoreContainer.reader())
        guard let snapshots = try? await accounts.allAccounts(),
            let active =
                accountID.map({ id in snapshots.first { $0.id == id } })
                ?? activeSnapshot(from: snapshots)
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

    /// Writes a post an intent changed into the running app's cache, which
    /// also tells every list on screen (`TimelineStatusUpdate`).
    @MainActor
    static func noteUpdated(_ status: Status, accountID: UUID) async {
        guard let session = live?.sessions.first(where: { $0.id == accountID }) else { return }
        try? await session.timelineStore.updateStatus(accountID: accountID, status: status)
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
            intent: SearchIntent(),
            phrases: ["Search \(.applicationName)"],
            shortTitle: "Search",
            systemImageName: "magnifyingglass")

        AppShortcut(
            intent: OpenShortsIntent(),
            phrases: ["Open \(.applicationName) Shorts"],
            shortTitle: "Shorts",
            systemImageName: "play.square.stack")
    }
}
