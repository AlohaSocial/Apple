// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

// Nextcloud Social's per-status extras: archive, delivery, quotes, dislikes,
// places (docs/02 §2). Every one of these sits behind a capability check in
// the UI; a stock Mastodon answers 404 to all of them.

extension Endpoint {
    public enum statusExtras {
        // MARK: Archive (Pixelfed)

        /// Off the profile, not deleted, not federated.
        public static func archive(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/pixelfed/v1/archive/add/\(id)")
        }
        public static func unarchive(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/pixelfed/v1/archive/remove/\(id)")
        }
        public static func archived(
            limit: Int = defaultLimit, anchor: PageAnchor = .cold
        ) -> Endpoint {
            Endpoint(
                path: "api/pixelfed/v1/archive/list", query: pageItems(limit: limit, anchor: anchor)
            )
        }

        // MARK: Delivery

        /// Author only: where the post got to, server by server.
        public static func delivery(_ id: String) -> Endpoint {
            Endpoint(path: "api/v1/statuses/\(id)/delivery")
        }

        // MARK: Quotes

        public static func quotes(
            _ id: String, limit: Int = defaultLimit, anchor: PageAnchor = .cold
        ) -> Endpoint {
            Endpoint(
                path: "api/v1/statuses/\(id)/quotes", query: pageItems(limit: limit, anchor: anchor)
            )
        }
        public static func setQuotePolicy(_ id: String, _ policy: QuoteApprovalPolicy) -> Endpoint {
            Endpoint(
                method: .put, path: "api/v1/statuses/\(id)/interaction_policy",
                body: .form([URLQueryItem(name: "quote_approval_policy", value: policy.rawValue)]))
        }
        /// Withdraws a quote already made. The quoting post stays, shown as
        /// withdrawn on its own server.
        public static func revokeQuote(_ id: String, quoting: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/statuses/\(id)/quotes/\(quoting)/revoke")
        }

        // MARK: Dislike (PeerTube)

        /// **No server route answers these yet.**
        ///
        /// The server publishes `dislikes_count` and `disliked` on a video
        /// status and federates what PeerTube sends, but `DislikeService` is
        /// wired to no controller, so both of these 404. They are kept because
        /// the field exists and the route is the obvious next thing the server
        /// grows; the row shows the count read-only until it does
        /// (`StatusMetric`).
        public static func dislike(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/statuses/\(id)/dislike")
        }
        public static func undislike(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/statuses/\(id)/undislike")
        }

        // MARK: Places

        public static func place(_ id: String) -> Endpoint {
            Endpoint(path: "api/v1/places/\(id)", requiresAuthentication: false)
        }
        public static func placeStatuses(
            _ id: String, limit: Int = defaultLimit, anchor: PageAnchor = .cold
        ) -> Endpoint {
            Endpoint(
                path: "api/v1/places/\(id)/statuses",
                query: pageItems(limit: limit, anchor: anchor), requiresAuthentication: false)
        }
    }

    /// Writing to albums; reading them is `Endpoint.collections`.
    public enum collectionsExtra {
        public static func create(_ draft: CollectionDraft) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/collections", body: .form(items(draft)))
        }
        public static func update(_ id: String, _ draft: CollectionDraft) -> Endpoint {
            Endpoint(method: .put, path: "api/v1/collections/\(id)", body: .form(items(draft)))
        }
        public static func delete(_ id: String) -> Endpoint {
            Endpoint(method: .delete, path: "api/v1/collections/\(id)")
        }
        public static func addItem(_ id: String, statusID: String) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/collections/\(id)/items",
                body: .form([URLQueryItem(name: "status_id", value: statusID)]))
        }
        /// The status goes in the **path**, not in a form body: the server's
        /// route is `/items/{status_id}`, so a `DELETE` to `/items` carrying
        /// `status_id` in the body matches nothing and 404s.
        public static func removeItem(_ id: String, statusID: String) -> Endpoint {
            Endpoint(method: .delete, path: "api/v1/collections/\(id)/items/\(statusID)")
        }

        private static func items(_ draft: CollectionDraft) -> [URLQueryItem] {
            [
                URLQueryItem(name: "title", value: draft.title),
                URLQueryItem(name: "description", value: draft.description),
                URLQueryItem(name: "visibility", value: draft.visibility),
            ]
        }
    }
}
