// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// Posts that have left the cache — deleted, archived, or by somebody just
/// blocked or muted — so a list on screen can drop their rows at once rather
/// than at its next refresh.
///
/// The store used to delete them and say nothing: lists only heard about
/// updates, so a deleted post, or a blocked person's, stayed in front of the
/// reader until something reloaded. Lists that never read the cache (a
/// thread, a search) hold copies the store never had, which is why a block
/// names the author as well as the posts it found.
public struct TimelineStatusRemoval: Sendable, Hashable {
    public static let notification = Notification.Name("aloha.timelineStatusRemoval")
    public let accountID: UUID
    /// Posts gone by id. A boost of one goes with it.
    public let statusIDs: Set<String>
    /// Everything this author wrote, and everything they boosted, goes too.
    public let authorID: String?

    public init(accountID: UUID, statusIDs: Set<String> = [], authorID: String? = nil) {
        self.accountID = accountID
        self.statusIDs = statusIDs
        self.authorID = authorID
    }

    /// Whether a row showing this status has to go.
    public func removes(_ status: Status) -> Bool {
        if statusIDs.contains(status.id) || statusIDs.contains(status.displayed.id) {
            return true
        }
        guard let authorID else { return false }
        return status.account.id == authorID || status.displayed.account.id == authorID
    }

    func post() {
        NotificationCenter.default.post(name: Self.notification, object: self)
    }
}
