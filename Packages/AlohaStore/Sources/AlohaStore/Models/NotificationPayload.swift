// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// What a stored notification carries so a local alert can be written without
/// a second fetch.
///
/// It lives beside `NotificationRecord` rather than in the app's sync layer,
/// because the widget decodes the same bytes and the widget target must not
/// pull in the whole UI module to read five fields.
public struct NotificationPayload: Codable, Sendable, Hashable {
    public var title: String
    public var body: String
    public var avatarURL: URL?
    public var accountHandle: String
    public var statusID: String?
    /// The post's visibility, so a direct message wears the direct-message
    /// category (Reply with no Boost) and its reply stays direct. Optional,
    /// so bytes stored by an older build still decode.
    public var visibility: Visibility?

    /// Whether the post is a direct message.
    public var isDirect: Bool { visibility == .direct }

    public init(
        title: String, body: String, avatarURL: URL?, accountHandle: String,
        statusID: String?, visibility: Visibility? = nil
    ) {
        self.title = title
        self.body = body
        self.avatarURL = avatarURL
        self.accountHandle = accountHandle
        self.statusID = statusID
        self.visibility = visibility
    }

    public static func encode(_ notification: MastodonNotification) -> Data {
        let payload = NotificationPayload(
            title: notification.account.bestDisplayName,
            body: Self.preview(notification.status),
            avatarURL: notification.account.preferredAvatarURL,
            accountHandle: notification.account.acct,
            statusID: notification.status?.id,
            visibility: notification.status?.displayed.visibility)
        return (try? AlohaJSON.encoder.encode(payload)) ?? Data()
    }

    public static func encode(
        group: NotificationGroup, results: GroupedNotificationsResults
    ) -> Data {
        let first = group.sampleAccountIDs.compactMap { results.account(id: $0) }.first
        let status = group.statusID.flatMap { results.status(id: $0) }
        let payload = NotificationPayload(
            title: first?.bestDisplayName ?? "",
            body: Self.preview(status),
            avatarURL: first?.preferredAvatarURL,
            accountHandle: first?.acct ?? "",
            statusID: group.statusID,
            visibility: status?.displayed.visibility)
        return (try? AlohaJSON.encoder.encode(payload)) ?? Data()
    }

    public static func decode(_ data: Data) -> NotificationPayload? {
        try? AlohaJSON.decoder.decode(NotificationPayload.self, from: data)
    }

    private static func preview(_ status: Status?) -> String {
        guard let status else { return "" }
        let target = status.displayed
        if !target.spoilerText.isEmpty { return target.spoilerText }
        return target.content
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
