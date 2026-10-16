// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// A typed, `Codable` destination — which makes state restoration, Handoff and
/// deep linking one mechanism rather than three (docs/01 §5).
public enum Route: Codable, Hashable, Sendable {
    case timeline(TimelineKey)
    case thread(statusID: String)
    case profile(accountID: String)
    case handle(String)
    case hashtag(String)
    case notifications
    case search(query: String?)
    case conversations
    case bookmarks
    case favourites
    case settings
    case drafts
    case explore
    case lists
    case filters
    case safety
    case notificationRequests
    case followRequests
    /// The notification policy screen (when the server supports it).
    case notificationPolicy
    /// One direct-message thread. Carries the conversation because Mastodon
    /// has no endpoint to fetch one by id.
    case conversation(Conversation)
    /// The watch page for a long-form video.
    case video(statusID: String)

    // Nextcloud Social surfaces the web app has and this app did not.
    /// "My interests": the hashtag feed the server learns, and its settings.
    case interests
    /// Feeds outside the fediverse (RSS, YouTube) the server reads for you.
    case subscriptions
    /// "On this day" memories and the weekly recap, with their settings.
    case memories
    /// Your own posts a moderator has not yet looked at.
    case heldPosts
    case starterPacks
    case starterPack(slug: String)
    /// Public posts from one place.
    case place(id: String)
    /// Your own archived posts: off your profile, not deleted.
    case archived
    case statistics
    case portfolio
    case migration
    case authorizedApps
    case featuredTags
    case editProfile
    /// Video channels, the PeerTube notion.
    case channels
    /// Albums. `nil` is the viewer's own.
    case collections(accountID: String?)
    case followers(accountID: String)
    case following(accountID: String)
    /// Photos an account is tagged in.
    case tagged(accountID: String)
    /// Posts quoting a status.
    case quotes(statusID: String)

    // Surfaces the web app has, or the server serves and nobody drew.
    /// "Your year": Mastodon's `#Wrapstodon`, which the web app has no page for.
    case annualReport
    /// What this server says about itself: activity, peers, published blocks.
    case serverInfo
    /// Deleting the Social account and keeping the Nextcloud one.
    case deleteAccount
    /// The moderator's hub. Every screen behind it 403s for anybody who is not
    /// an administrator of this Nextcloud, and says so.
    case moderation
    case moderationReports
    case moderationReport(id: String)
    case moderationAccounts
    case moderationTrends
}

/// The one place any entry point is parsed. Every scheme, universal link,
/// Handoff payload, intent and notification produces a `Route` and goes through
/// here, so they cannot behave differently (docs/09 §10).
public enum RouteResolver {
    public static let scheme = "alohasocial"

    /// Posted when `alohasocial://compose` is opened. The composer is a sheet
    /// from the shell rather than a navigation destination, so a deep link to
    /// it has to arrive as something the shell is watching for.
    public static let composeRequested = Notification.Name("alohasocial.compose.requested")

    /// Returns the Route the URL names, or nil where the URL asks for
    /// something that is not a destination — the sign-in callback, and the
    /// compose request.
    public static func route(for url: URL) -> Route? {
        guard url.scheme == scheme else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }

        switch url.host() {
        case "timeline":
            guard let modeName = components.first, let mode = FeedMode(rawValue: modeName)
            else { return .timeline(.home()) }
            let source: TimelineSource
            switch components.dropFirst().first {
            case "local": source = .local
            case "federated": source = .federated
            default: source = .home
            }
            return .timeline(TimelineKey(mode: mode, source: source))

        case "status":
            guard let id = components.last else { return nil }
            return .thread(statusID: id)

        case "profile":
            guard let id = components.last else { return nil }
            return .profile(accountID: id)

        case "tag":
            guard let name = components.first else { return nil }
            return .hashtag(name)

        case "search":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "q" }?.value
            return .search(query: query)

        case "moderation": return .moderation
        case "year": return .annualReport
        case "notifications": return .notifications
        case "bookmarks": return .bookmarks
        case "favourites": return .favourites
        case "settings": return .settings
        case "explore": return .explore
        case "lists": return .lists
        // "compose" opens the composer rather than any of the Routes: the
        // composer is presented as a sheet from the shell, not pushed onto a
        // navigation stack, so there is no destination to name. Sending the
        // person to Drafts — which is what this used to do — meant a widget
        // button labelled "New post" landed them in a list of things they had
        // not written yet (docs/09 §8).
        case "compose": return nil
        default: return nil
        }
    }

    /// A fediverse URL from anywhere else. It is resolved through the **active
    /// account's** server so the post opens with that reader's relationship
    /// state and working action buttons — the single most valuable link
    /// behaviour in a client of this kind (docs/09 §10).
    public static func isFediverseCandidate(_ url: URL) -> Bool {
        guard let scheme = url.scheme, scheme == "https" else { return false }
        let path = url.path()
        return path.contains("/@") || path.contains("/users/") || path.contains("/statuses/")
            || path.contains("/notice/") || path.contains("/objects/") || path.contains("/p/")
    }
}

extension Notification.Name {
    /// Posted by Handoff continuation in the app target and observed by the
    /// shell. Declared here so both sides name the same thing.
    public static let alohaOpenRoute = Notification.Name("aloha.openRoute")
}
