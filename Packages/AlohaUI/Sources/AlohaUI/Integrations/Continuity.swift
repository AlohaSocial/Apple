// SPDX-License-Identifier: MIT

import AlohaModels
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Handoff and Spotlight, both resolving through `RouteResolver` so every entry
/// point behaves identically (docs/09 §11, §12).
public enum Continuity {
    public static let viewingTimeline = "com.nextcloud.alohasocial.viewingTimeline"
    public static let viewingStatus = "com.nextcloud.alohasocial.viewingStatus"
    public static let viewingProfile = "com.nextcloud.alohasocial.viewingProfile"
    public static let composing = "com.nextcloud.alohasocial.composing"

    public static let allActivityTypes = [
        viewingTimeline, viewingStatus, viewingProfile, composing,
    ]

    public static func activity(for route: Route, title: String) -> NSUserActivity {
        let type: String
        switch route {
        case .thread: type = viewingStatus
        case .profile, .handle: type = viewingProfile
        case .drafts: type = composing
        default: type = viewingTimeline
        }

        let activity = NSUserActivity(activityType: type)
        activity.title = title
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        #if !os(macOS)
            activity.isEligibleForPrediction = true
        #endif
        if let data = try? JSONEncoder().encode(route) {
            activity.userInfo = ["route": data]
        }
        return activity
    }

    /// A draft continues between devices; its media does not, because it may
    /// not exist on the other one — and the activity says so.
    public static func composingActivity(draft: String) -> NSUserActivity {
        let activity = NSUserActivity(activityType: composing)
        activity.title = String(localized: "Writing a post", comment: "Handoff title")
        activity.isEligibleForHandoff = true
        activity.userInfo = ["draft": draft]
        return activity
    }

    public static func route(from activity: NSUserActivity) -> Route? {
        guard let data = activity.userInfo?["route"] as? Data else { return nil }
        return try? JSONDecoder().decode(Route.self, from: data)
    }

    public static func draft(from activity: NSUserActivity) -> String? {
        activity.userInfo?["draft"] as? String
    }
}

/// Only what a person chose to keep is indexed. Putting a stranger's posts into
/// the device search index is not something anybody consented to (docs/09 §12).
public enum SpotlightIndexer {
    private static let domain = "com.nextcloud.alohasocial.bookmarks"

    public static func index(bookmarks: [Status], accountID: UUID) async {
        let items = bookmarks.map { status -> CSSearchableItem in
            let target = status.displayed
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = target.account.bestDisplayName
            attributes.contentDescription = plain(target.content)
            attributes.keywords = target.tags.map(\.name)
            attributes.contentURL = URL(
                string: "alohasocial://status/\(accountID.uuidString)/\(target.id)")

            return CSSearchableItem(
                uniqueIdentifier: "\(accountID.uuidString):\(target.id)",
                domainIdentifier: domain,
                attributeSet: attributes)
        }

        try? await CSSearchableIndex.default().indexSearchableItems(items)
    }

    /// Removing an account clears its index entries immediately and completely.
    public static func removeEverything(for accountID: UUID) async {
        try? await CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [domain])
    }

    private static func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
