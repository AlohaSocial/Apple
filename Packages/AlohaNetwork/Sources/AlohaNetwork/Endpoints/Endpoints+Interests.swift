// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

// Nextcloud Social's own reading surfaces: interests, outside feeds, memories,
// the review queue, and the reader's side of announcements. None of these
// exist on Mastodon, so every caller gates on `isNextcloudSocial` first.

// MARK: - My interests

extension Endpoint {
    public enum interests {
        public static var state: Endpoint { Endpoint(path: "api/v1/interests") }

        public static func add(_ tag: String) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/interests",
                body: .form([URLQueryItem(name: "tag", value: tag)]))
        }

        public static func remove(_ tag: String) -> Endpoint {
            Endpoint(method: .delete, path: "api/v1/interests/\(encoded(tag))")
        }

        public static func move(_ tag: String, to position: Int) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/interests/\(encoded(tag))/move",
                body: .form([URLQueryItem(name: "position", value: String(position))]))
        }

        public static func pin(_ tag: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/interests/\(encoded(tag))/pin")
        }

        public static func unpin(_ tag: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/interests/\(encoded(tag))/unpin")
        }

        public static var reset: Endpoint {
            Endpoint(method: .post, path: "api/v1/interests/reset")
        }

        /// Only the fields passed are changed; the rest keep their value.
        public static func settings(
            learning: Bool? = nil, paused: Bool? = nil, languages: [String]? = nil,
            noticeAcknowledged: Bool? = nil
        ) -> Endpoint {
            var items: [URLQueryItem] = []
            if let learning {
                items.append(URLQueryItem(name: "learning", value: learning ? "1" : "0"))
            }
            if let paused { items.append(URLQueryItem(name: "paused", value: paused ? "1" : "0")) }
            if let languages {
                // An empty list has to reach the server as a field, or it
                // reads as "leave the languages alone".
                items +=
                    languages.isEmpty
                    ? [URLQueryItem(name: "languages", value: "")]
                    : .repeated("languages", languages)
            }
            if let noticeAcknowledged {
                items.append(
                    URLQueryItem(name: "noticeAcknowledged", value: noticeAcknowledged ? "1" : "0"))
            }
            return Endpoint(method: .put, path: "api/v1/interests/settings", body: .form(items))
        }

        /// Reading signals, batched. The server answers 204 whether or not it
        /// is learning, so a caller never needs to know.
        ///
        /// A JSON body, `{"events": [{status_id, kind, ms, context}]}`: the
        /// server skips every event that is not an object
        /// (`InterestService::recordEvents`), so a form of strings taught it
        /// nothing. At most 100 per request; anything learnable only.
        public static func signals(_ events: [InterestSignal]) -> Endpoint {
            struct Body: Encodable {
                let events: [InterestSignal]
            }
            let learnable = Array(events.filter(\.isLearnable).prefix(maximumSignals))
            let data = (try? JSONEncoder().encode(Body(events: learnable))) ?? Data()
            return Endpoint(method: .post, path: "api/v1/interests/signals", body: .json(data))
        }

        /// The server's own cap per request (`InterestService::MAX_EVENTS`).
        public static let maximumSignals = 100

        /// "Show fewer like this", and its undo.
        public static func fewerLikeThis(_ statusID: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/interests/less/\(statusID)")
        }

        public static func undoFewerLikeThis(_ statusID: String) -> Endpoint {
            Endpoint(method: .delete, path: "api/v1/interests/less/\(statusID)")
        }

        /// The feed itself. Pages by `max_id` with a `Link` header.
        public static func timeline(
            limit: Int = defaultLimit, anchor: PageAnchor = .cold
        ) -> Endpoint {
            Endpoint(
                path: "api/v1/timelines/interests", query: pageItems(limit: limit, anchor: anchor))
        }

        private static func encoded(_ tag: String) -> String {
            tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
        }
    }
}

// MARK: - Memories

extension Endpoint {
    public enum memories {
        /// Posts of yours from this calendar day in earlier years.
        public static var onThisDay: Endpoint { Endpoint(path: "api/v1/memories/on_this_day") }

        public static var recap: Endpoint { Endpoint(path: "api/v1/memories/recap") }

        public static func setRecap(enabled: Bool) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/memories/recap",
                body: .form([URLQueryItem(name: "enabled", value: enabled ? "1" : "0")]))
        }
    }
}

// MARK: - Review queue

extension Endpoint {
    /// Nextcloud session routes (`ReviewController`: `#[NoAdminRequired]`,
    /// no `#[PublicPage]`), so they carry the app password, not the token.
    public enum review {
        /// Your own posts waiting for a moderator.
        public static var held: Endpoint {
            Endpoint(path: "api/v1/review", authentication: .nextcloudSession)
        }

        /// Withdraws the post: deleted, no moderation record made.
        public static func withdraw(_ id: String) -> Endpoint {
            Endpoint(
                method: .delete, path: "api/v1/review/\(id)", authentication: .nextcloudSession)
        }
    }
}

// MARK: - Announcements, the reader's side

extension Endpoint {
    public enum announcementsExtra {
        /// The same list as `safety.announcements`, decoded with reactions.
        public static var all: Endpoint { Endpoint(path: "api/v1/announcements") }

        public static func dismiss(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/announcements/\(id)/dismiss")
        }

        public static func react(_ id: String, emoji: String) -> Endpoint {
            Endpoint(method: .put, path: "api/v1/announcements/\(id)/reactions/\(encoded(emoji))")
        }

        public static func unreact(_ id: String, emoji: String) -> Endpoint {
            Endpoint(
                method: .delete, path: "api/v1/announcements/\(id)/reactions/\(encoded(emoji))")
        }

        /// An emoji in a path has to be percent-encoded to survive the trip.
        private static func encoded(_ emoji: String) -> String {
            emoji.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? emoji
        }
    }
}
