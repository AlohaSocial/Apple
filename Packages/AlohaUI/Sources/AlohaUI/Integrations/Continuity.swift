// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import CoreSpotlight
import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// Handoff and Spotlight, both resolving through `RouteResolver` so every entry
/// point behaves identically (docs/09 §11, §12).
public enum Continuity {
    public static let viewingTimeline = "social.aloha.app.viewingTimeline"
    public static let viewingStatus = "social.aloha.app.viewingStatus"
    public static let viewingProfile = "social.aloha.app.viewingProfile"
    public static let composing = "social.aloha.app.composing"

    public static let allActivityTypes = [
        viewingTimeline, viewingStatus, viewingProfile, composing,
    ]

    /// The activity type a screen advertises.
    public static func activityType(for route: Route) -> String {
        switch route {
        case .thread, .video: viewingStatus
        case .profile, .handle: viewingProfile
        default: viewingTimeline
        }
    }

    public static func activity(for route: Route, title: String) -> NSUserActivity {
        let activity = NSUserActivity(activityType: activityType(for: route))
        configure(activity, route: route, title: title, account: nil)
        return activity
    }

    /// Fills in an activity for one screen.
    ///
    /// The account travels with the route: a post id means nothing on another
    /// server, so the other device has to open it under the same account, or
    /// not at all. Where the screen has a web address the activity carries
    /// it too, so a device without the app opens the page in a browser.
    public static func configure(
        _ activity: NSUserActivity, route: Route, title: String,
        account: AccountIdentity?
    ) {
        activity.title = title
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        #if !os(macOS)
            activity.isEligibleForPrediction = true
        #endif
        var info: [String: Any] = [:]
        if let data = try? JSONEncoder().encode(route) { info["route"] = data }
        if let account { info["account"] = account.handle }
        activity.userInfo = info
        activity.webpageURL = account.flatMap { webpageURL(for: route, host: $0.host) }
    }

    /// A draft continues between devices; its media does not, because it may
    /// not exist on the other one — and the activity says so.
    public static func composingActivity(draft: String) -> NSUserActivity {
        let activity = NSUserActivity(activityType: composing)
        configureComposing(activity, draft: draft, account: nil)
        return activity
    }

    public static func configureComposing(
        _ activity: NSUserActivity, draft: String, account: AccountIdentity?
    ) {
        activity.title = String(localized: "Writing a post", comment: "Handoff title")
        activity.isEligibleForHandoff = true
        var info: [String: Any] = ["draft": draft]
        if let account { info["account"] = account.handle }
        activity.userInfo = info
    }

    public static func route(from activity: NSUserActivity) -> Route? {
        guard let data = activity.userInfo?["route"] as? Data else { return nil }
        return try? JSONDecoder().decode(Route.self, from: data)
    }

    public static func draft(from activity: NSUserActivity) -> String? {
        activity.userInfo?["draft"] as? String
    }

    /// The account an activity was advertised under, as its qualified handle.
    public static func accountHandle(from activity: NSUserActivity) -> String? {
        activity.userInfo?["account"] as? String
    }

    /// The public page for a screen, where Mastodon's web paths name one
    /// without a server-side lookup.
    static func webpageURL(for route: Route, host: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        switch route {
        case .hashtag(let name): components.path = "/tags/\(name)"
        case .handle(let handle):
            components.path = "/@\(handle.hasPrefix("@") ? String(handle.dropFirst()) : handle)"
        case .explore: components.path = "/explore"
        default: return nil
        }
        return components.url
    }

    /// A screen's Handoff title.
    static func title(for route: Route) -> String {
        switch route {
        case .thread, .video: String(localized: "Reading a post", comment: "Handoff title")
        case .profile, .handle:
            String(localized: "Looking at a profile", comment: "Handoff title")
        case .hashtag(let name):
            String(localized: "Reading #\(name)", comment: "Handoff title")
        default: String(localized: "Reading Aloha Social", comment: "Handoff title")
        }
    }
}

/// Which account a Handoff or Spotlight item belongs to.
public struct AccountIdentity: Sendable, Hashable {
    /// `@name@server`, the same on every device signed into the account.
    public let handle: String
    public let host: String

    public init(handle: String, host: String) {
        self.handle = handle
        self.host = host
    }

    init(session: AccountSession) {
        self.init(handle: session.snapshot.qualifiedHandle, host: session.snapshot.instanceHost)
    }
}

/// Only what a person chose is indexed: their bookmarks, their own posts, and
/// the people they follow — names and handles, never those people's posts.
/// Putting a stranger's posts into the device search index is not something
/// anybody consented to (docs/09 §12).
@MainActor
public enum SpotlightIndexer {
    private static let logger = Logger(subsystem: "social.aloha.app", category: "spotlight")

    /// Once a day is plenty for an index of things that change by hand.
    static let refreshInterval: TimeInterval = 24 * 60 * 60

    /// Every item of one account lives under this domain, so removing the
    /// account removes them all: Core Spotlight deletes a domain together with
    /// its subdomains.
    static func domain(for accountID: UUID) -> String {
        "social.aloha.app.\(accountID.uuidString)"
    }

    /// The identifier is the item's own deep link, so a tap resolves through
    /// `RouteResolver` like every other way into the app.
    static func identifier(statusID: String, accountID: UUID) -> String {
        "\(RouteResolver.scheme)://status/\(accountID.uuidString)/\(statusID)"
    }

    static func identifier(profileID: String, accountID: UUID) -> String {
        "\(RouteResolver.scheme)://profile/\(accountID.uuidString)/\(profileID)"
    }

    /// Rebuilds one account's index when it is older than a day.
    public static func refreshIfStale(_ session: AccountSession, now: Date = Date()) async {
        let key = "aloha.spotlight.\(session.id.uuidString)"
        if let last = UserDefaults.standard.object(forKey: key) as? Date,
            now.timeIntervalSince(last) < refreshInterval
        {
            return
        }
        do {
            try await refresh(session)
            UserDefaults.standard.set(now, forKey: key)
        } catch {
            // The index is a convenience: a failure tries again next launch.
            logger.debug("index refresh failed: \(String(describing: error), privacy: .public)")
        }
    }

    static func refresh(_ session: AccountSession) async throws {
        let bookmarks = try await session.client.decode(
            LossyArray<Status>.self,
            from: Endpoint.timelines.timeline(.bookmarks, limit: 40)
        ).elements
        let ownPosts = try await session.client.decode(
            LossyArray<Status>.self,
            from: Endpoint.timelines.timeline(
                .account(
                    id: session.snapshot.serverAccountID, includeReplies: false,
                    onlyMedia: false),
                limit: 40)
        ).elements
        let following = try await session.client.decode(
            LossyArray<Account>.self,
            from: Endpoint.accounts.following(session.snapshot.serverAccountID, limit: 80)
        ).elements

        let domain = domain(for: session.id)
        let items =
            bookmarks.map { item(for: $0, accountID: session.id, domain: "\(domain).bookmarks") }
            + ownPosts.filter { $0.reblog == nil }.map {
                item(for: $0, accountID: session.id, domain: "\(domain).posts")
            }
            + following.map { item(for: $0, accountID: session.id, domain: "\(domain).following") }

        let index = CSSearchableIndex.default()
        // Replaced rather than added to, so an unbookmarked post or an
        // unfollowed account leaves the index on the next refresh.
        try await index.deleteSearchableItems(withDomainIdentifiers: [domain])
        try await index.indexSearchableItems(items)
    }

    /// Kept for the bookmarks screen, which knows the moment its list changes.
    public static func index(bookmarks: [Status], accountID: UUID) async {
        let domain = "\(domain(for: accountID)).bookmarks"
        let items = bookmarks.map { item(for: $0, accountID: accountID, domain: domain) }
        try? await CSSearchableIndex.default().indexSearchableItems(items)
    }

    /// Removing an account clears its index entries immediately and completely
    /// — and only that account's.
    public static func removeEverything(for accountID: UUID) async {
        try? await CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [domain(for: accountID)])
        UserDefaults.standard.removeObject(forKey: "aloha.spotlight.\(accountID.uuidString)")
    }

    private static func item(
        for status: Status, accountID: UUID, domain: String
    ) -> CSSearchableItem {
        let target = status.displayed
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = target.account.bestDisplayName
        attributes.contentDescription = plain(target.content)
        attributes.keywords = target.tags.map(\.name)
        let identifier = identifier(statusID: target.id, accountID: accountID)
        attributes.contentURL = URL(string: identifier)
        return CSSearchableItem(
            uniqueIdentifier: identifier, domainIdentifier: domain, attributeSet: attributes)
    }

    private static func item(
        for account: Account, accountID: UUID, domain: String
    ) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .contact)
        attributes.title = account.bestDisplayName
        attributes.contentDescription = "@\(account.acct)"
        attributes.keywords = [account.acct, account.username]
        let identifier = identifier(profileID: account.id, accountID: accountID)
        attributes.contentURL = URL(string: identifier)
        return CSSearchableItem(
            uniqueIdentifier: identifier, domainIdentifier: domain, attributeSet: attributes)
    }

    private static func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Where Handoff and Spotlight arrive, for both apps.
///
/// One modifier rather than a copy in each app's entry point, so the iPhone,
/// the iPad and the Mac cannot resume the same activity differently.
public struct ContinuityReceiver: ViewModifier {
    /// Passed in rather than read from the SwiftUI environment: the apps apply
    /// this outside the `.environment(_:)` that injects it.
    private let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public func body(content: Content) -> some View {
        content
            .onContinueUserActivity(Continuity.viewingStatus, perform: resume)
            .onContinueUserActivity(Continuity.viewingProfile, perform: resume)
            .onContinueUserActivity(Continuity.viewingTimeline, perform: resume)
            .onContinueUserActivity(Continuity.composing, perform: resumeComposing)
            .onContinueUserActivity(CSSearchableItemActionType, perform: resumeSearchItem)
    }

    private func resume(_ activity: NSUserActivity) {
        guard let route = Continuity.route(from: activity) else { return }
        // An activity from a build that did not name its account opens under
        // the active one, as it always did. One that names an account this
        // device does not have cannot open a post by its id at all.
        if let handle = Continuity.accountHandle(from: activity) {
            guard selectAccount(handle: handle) || !route.isServerSpecific else { return }
        }
        IntentNavigation.enqueue(route)
    }

    private func resumeComposing(_ activity: NSUserActivity) {
        _ = selectAccount(handle: Continuity.accountHandle(from: activity))
        NotificationCenter.default.post(
            name: RouteResolver.composeRequested, object: nil,
            userInfo: ["draft": Continuity.draft(from: activity) ?? ""])
    }

    private func resumeSearchItem(_ activity: NSUserActivity) {
        guard
            let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
            let url = URL(string: identifier),
            let destination = RouteResolver.destination(for: url)
        else { return }
        if let accountID = destination.accountID { environment.setActiveAccount(accountID) }
        IntentNavigation.enqueue(destination.route)
    }

    /// Switches to the account the activity was advertised under. Returns
    /// whether this device has that account at all.
    private func selectAccount(handle: String?) -> Bool {
        guard let handle else { return false }
        guard
            let session = environment.sessions.first(where: {
                $0.snapshot.qualifiedHandle.caseInsensitiveCompare(handle) == .orderedSame
            })
        else { return false }
        environment.setActiveAccount(session.id)
        return true
    }
}

/// Advertises a screen for Handoff.
struct ContinuityAdvertiser: ViewModifier {
    let route: Route
    let session: AccountSession

    func body(content: Content) -> some View {
        content.userActivity(Continuity.activityType(for: route)) { activity in
            Continuity.configure(
                activity, route: route, title: Continuity.title(for: route),
                account: AccountIdentity(session: session))
        }
    }
}

extension Route {
    /// Whether the route names something by one server's id, which another
    /// account — on another server — cannot open.
    var isServerSpecific: Bool {
        switch self {
        case .thread, .video, .profile, .conversation, .quotes, .followers, .following,
            .tagged, .place, .moderationReport, .collections(accountID: .some):
            true
        default: false
        }
    }
}
