// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

// MARK: - Profile extras

extension Endpoint {
    /// What a profile shows beyond the account entity: Nextcloud Social's
    /// highlights, featured tags, pinned posts, mutual followers, private
    /// notes, endorsements, and Pixelfed's tagged photos.
    public enum profile {
        /// Twelve weeks of posting, for a local account (docs/05 §5).
        public static func highlights(_ id: String) -> Endpoint {
            Endpoint(path: "api/v1/accounts/\(id)/highlights")
        }

        /// Up to ten hashtags an account features at the top of its profile.
        public static func featuredTags(_ id: String) -> Endpoint {
            Endpoint(path: "api/v1/accounts/\(id)/featured_tags", requiresAuthentication: false)
        }

        /// Up to five pinned posts.
        public static func pinnedStatuses(_ id: String) -> Endpoint {
            Endpoint(
                path: "api/v1/accounts/\(id)/statuses",
                query: [
                    URLQueryItem(name: "pinned", value: "true"),
                    URLQueryItem(name: "limit", value: "5"),
                ])
        }

        /// The people you follow who also follow each of the accounts asked.
        public static func familiarFollowers(_ ids: [String]) -> Endpoint {
            Endpoint(path: "api/v1/accounts/familiar_followers", query: .repeated("id", ids))
        }

        /// A private note about an account, seen by nobody else.
        public static func setNote(_ id: String, comment: String) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/accounts/\(id)/note",
                body: .form([
                    URLQueryItem(name: "comment", value: comment)
                ]))
        }

        public static func removeFromFollowers(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/accounts/\(id)/remove_from_followers")
        }

        /// Feature an account on your own profile.
        public static func endorse(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/accounts/\(id)/pin")
        }

        public static func unendorse(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/accounts/\(id)/unpin")
        }

        /// The viewer's lists that contain an account.
        public static func listsContaining(_ id: String) -> Endpoint {
            Endpoint(path: "api/v1/accounts/\(id)/lists")
        }

        /// Photos an account is tagged in (Pixelfed).
        public static func tagged(
            _ id: String, limit: Int = defaultLimit, anchor: PageAnchor = .cold
        ) -> Endpoint {
            Endpoint(
                path: "api/v1.1/accounts/\(id)/tagged",
                query: pageItems(limit: min(limit, 40), anchor: anchor))
        }

        /// Tag people in your own photo. Handles go without the `@`.
        public static func tagPeople(statusID: String, handles: [String]) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1.1/compose/tag",
                body: .form(
                    [URLQueryItem(name: "status_id", value: statusID)]
                        + .repeated("accounts", handles)))
        }

        /// Take your own tag off somebody's photo.
        public static func untagMe(statusID: String) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1.1/compose/tag/untagme",
                body: .form([
                    URLQueryItem(name: "status_id", value: statusID)
                ]))
        }
    }

    /// The rest of the lists API: editing a list and its membership.
    public enum listsExtra {
        public static func update(
            _ id: String, title: String, repliesPolicy: String?, exclusive: Bool
        ) -> Endpoint {
            Endpoint(
                method: .put, path: "api/v1/lists/\(id)",
                body: .form(
                    [
                        URLQueryItem(name: "title", value: title),
                        URLQueryItem(name: "exclusive", value: exclusive ? "true" : "false"),
                    ] + .optional("replies_policy", repliesPolicy)))
        }

        public static func members(
            _ id: String, limit: Int = 40, anchor: PageAnchor = .cold
        ) -> Endpoint {
            Endpoint(
                path: "api/v1/lists/\(id)/accounts", query: pageItems(limit: limit, anchor: anchor))
        }

        public static func addAccounts(_ id: String, accountIDs: [String]) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/lists/\(id)/accounts",
                body: .form(.repeated("account_ids", accountIDs)))
        }

        public static func removeAccounts(_ id: String, accountIDs: [String]) -> Endpoint {
            Endpoint(
                method: .delete, path: "api/v1/lists/\(id)/accounts",
                body: .form(.repeated("account_ids", accountIDs)))
        }
    }
}
