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
        public static func signals(_ events: [String]) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/interests/signals",
                body: .form(.repeated("events", events)))
        }

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

// MARK: - Subscriptions

extension Endpoint {
    public enum subscriptions {
        public static var feeds: Endpoint { Endpoint(path: "api/v1/subscriptions") }

        /// A feed URL, or a YouTube channel link — the server works out which.
        public static func follow(url: String) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/subscriptions",
                body: .form([URLQueryItem(name: "url", value: url)]))
        }

        public static func unfollow(_ id: String) -> Endpoint {
            Endpoint(method: .delete, path: "api/v1/subscriptions/\(id)")
        }

        /// Newest first. `max_id` is the entry id to page below; the route
        /// sends no `Link` header, so the caller pages by the last row.
        public static func timeline(limit: Int = 40, maxID: String? = nil) -> Endpoint {
            Endpoint(
                path: "api/v1/subscriptions/timeline",
                query: [URLQueryItem(name: "limit", value: String(limit))]
                    + .optional("max_id", maxID))
        }

        /// Google Takeout's `subscriptions.csv`.
        public static func importTakeout(
            csv: Data, filename: String = "subscriptions.csv"
        ) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/subscriptions/takeout",
                body: .multipart(
                    Multipart(parts: [
                        Multipart.Part(
                            name: "file", filename: filename, mimeType: "text/csv", data: csv)
                    ])))
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
    public enum review {
        /// Your own posts waiting for a moderator.
        public static var held: Endpoint { Endpoint(path: "api/v1/review") }

        /// Withdraws the post: deleted, no moderation record made.
        public static func withdraw(_ id: String) -> Endpoint {
            Endpoint(method: .delete, path: "api/v1/review/\(id)")
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
