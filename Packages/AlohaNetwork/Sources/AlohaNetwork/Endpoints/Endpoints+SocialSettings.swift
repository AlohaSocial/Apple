// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

// Aloha Social's reader settings and the conversation controls that go with
// them. All of these are the Social app's own client API and take the bearer
// token, except where a route says otherwise. A stock Mastodon 404s every one,
// so the UI gates on `isNextcloudSocial` first.

// MARK: - Reader settings

extension Endpoint {
    public enum readerSettings {
        /// Whether posts that say they were made with AI are hidden:
        /// `{"hide": bool}`, off unless turned on (`AiContentService`).
        public static var aiContent: Endpoint { Endpoint(path: "api/v1/social/ai_content") }

        /// `hide` is required; a request unclear about a switch is a 422.
        public static func setAIContent(hide: Bool) -> Endpoint {
            Endpoint(
                method: .patch, path: "api/v1/social/ai_content", body: hideBody(hide))
        }

        /// Whether the server hides popularity counts: `{"hide": bool}`, and
        /// **hidden unless turned off** (`CountsService`). While hidden, every
        /// count on a post arrives as `0` (`HideCountsMiddleware`) — so a
        /// client that draws numbers has to know which zeros are real.
        public static var counts: Endpoint { Endpoint(path: "api/v1/social/counts") }

        public static func setCounts(hide: Bool) -> Endpoint {
            Endpoint(method: .patch, path: "api/v1/social/counts", body: hideBody(hide))
        }

        /// Who may start a conversation with the reader: `{"from": …}`.
        public static var directMessages: Endpoint {
            Endpoint(path: "api/v1/social/direct_messages")
        }

        public static func setDirectMessages(from audience: DirectMessageAudience) -> Endpoint {
            Endpoint(
                method: .patch, path: "api/v1/social/direct_messages",
                body: json(["from": audience.rawValue]))
        }

        /// How the server delivers the reader's Nextcloud notifications —
        /// the bell and push, not this app's own local notifications.
        public static var notificationDelivery: Endpoint {
            Endpoint(path: "api/v1/social/notification_delivery")
        }

        /// The whole setting goes back. Any subset is accepted, but an
        /// invalid value is a 422 and nothing is written, so sending what was
        /// read plus the change is what keeps one bad field from losing the
        /// rest (`NotificationController::deliveryUpdate`).
        public static func setNotificationDelivery(
            _ settings: NotificationDeliverySettings
        ) -> Endpoint {
            let data = (try? JSONEncoder().encode(settings)) ?? Data()
            return Endpoint(
                method: .patch, path: "api/v1/social/notification_delivery", body: .json(data))
        }

        /// A JSON boolean, not a form string: the server's `requiredFlag`
        /// takes either, but a JSON `true` cannot be misread.
        private static func hideBody(_ hide: Bool) -> Body {
            .json(Data((hide ? #"{"hide":true}"# : #"{"hide":false}"#).utf8))
        }

        private static func json(_ object: [String: String]) -> Body {
            .json((try? JSONEncoder().encode(object)) ?? Data())
        }
    }
}

// MARK: - Notification requests, beyond Mastodon's one-at-a-time

extension Endpoint {
    public enum notificationInbox {
        /// Accepts several senders at once, `id[]` being account ids. An id
        /// that names nobody is skipped, so a screenful never fails on one
        /// stale row (`NotificationController::decideMany`).
        public static func acceptAll(_ accountIDs: [String]) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/notifications/requests/accept",
                body: .form(.repeated("id", accountIDs)))
        }

        public static func dismissAll(_ accountIDs: [String]) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/notifications/requests/dismiss",
                body: .form(.repeated("id", accountIDs)))
        }

        /// The senders whose notifications always come through, whatever
        /// the policy says. `Account[]`.
        public static func allowed(limit: Int = 40) -> Endpoint {
            Endpoint(
                path: "api/v1/social/notifications/allowed",
                query: [URLQueryItem(name: "limit", value: String(min(max(1, limit), 80)))])
        }

        /// Puts a sender back under the policy. Answers `{}`.
        public static func removeAllowed(_ accountID: String) -> Endpoint {
            Endpoint(method: .delete, path: "api/v1/social/notifications/allowed/\(accountID)")
        }

        /// Puts away the one-time pointer to the policy (`notice` on the
        /// policy). Answers the policy.
        public static var dismissPolicyNotice: Endpoint {
            Endpoint(method: .post, path: "api/v1/social/notifications/policy/notice/dismiss")
        }
    }
}

// MARK: - Replies

extension Endpoint {
    public enum replyControls {
        /// Changes who may reply to a post of the reader's own. Sending only
        /// `reply_policy` leaves the quote policy as it is
        /// (`StatusApiController::statusInteractionPolicy`). Answers the Status.
        public static func setReplyPolicy(_ statusID: String, _ policy: ReplyPolicy) -> Endpoint {
            Endpoint(
                method: .put, path: "api/v1/statuses/\(statusID)/interaction_policy",
                body: .form([URLQueryItem(name: "reply_policy", value: policy.rawValue)]))
        }

        /// Hides a reply to one of the reader's own posts. `statusID` is the
        /// **reply**, not the post it answers. Answers the Status.
        public static func hide(_ statusID: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/statuses/\(statusID)/hide_reply")
        }

        public static func unhide(_ statusID: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/statuses/\(statusID)/unhide_reply")
        }
    }
}

// MARK: - Links, accounts, shared moderation lists

extension Endpoint {
    public enum socialExtras {
        /// The posts sharing one link: what a trending link card opens.
        /// An address nobody posted is an empty list, not an error.
        public static func linkTimeline(
            _ url: URL, limit: Int = defaultLimit, anchor: PageAnchor = .cold
        ) -> Endpoint {
            Endpoint(
                path: "api/v1/timelines/link",
                query: [URLQueryItem(name: "url", value: url.absoluteString)]
                    + pageItems(limit: limit, anchor: anchor),
                requiresAuthentication: false)
        }

        /// A local account as Aloha Social exports it, with the Bluesky handle
        /// the server published for it — which the Mastodon account route does
        /// not attach (`LocalController::attachBluesky`). A public page, so
        /// the bearer token is enough.
        public static func accountInfo(username: String) -> Endpoint {
            Endpoint(path: "api/v1/account/\(username)/info", requiresAuthentication: false)
        }
    }

    /// Shared mute and block lists, a Bluesky notion. `#[NoAdminRequired]`
    /// routes, so a Nextcloud session rather than the Social token.
    public enum moderationLists {
        public static var all: Endpoint {
            Endpoint(path: "api/v1/social/moderation_lists", authentication: .nextcloudSession)
        }

        /// A list by its bsky.app address or `at://` URI. A list that cannot
        /// be read is a 422 with the reason.
        public static func subscribe(url: String, kind: ModerationList.Kind) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/social/moderation_lists",
                body: .form([
                    URLQueryItem(name: "url", value: url),
                    URLQueryItem(name: "kind", value: kind.rawValue),
                ]),
                authentication: .nextcloudSession)
        }

        /// `uri` in the query: Nextcloud only reads a form body on the
        /// methods that are meant to have one.
        public static func unsubscribe(uri: String) -> Endpoint {
            Endpoint(
                method: .delete, path: "api/v1/social/moderation_lists",
                query: [URLQueryItem(name: "uri", value: uri)],
                authentication: .nextcloudSession)
        }
    }
}
