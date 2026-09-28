// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

// MARK: - Discovery (Nextcloud Social and Pixelfed routes)

extension Endpoint {
    /// Starter packs, other servers' directories, the follow graph and
    /// Pixelfed's discover surface. All Nextcloud Social; gate on
    /// `capabilities.isNextcloudSocial` (docs/02 §2).
    public enum discovery {
        // Starter packs

        public static var starterPacks: Endpoint {
            Endpoint(path: "api/v1/starter_packs", requiresAuthentication: false)
        }
        public static func starterPack(_ slug: String) -> Endpoint {
            Endpoint(path: "api/v1/starter_packs/\(slug)", requiresAuthentication: false)
        }
        public static func followStarterPack(_ slug: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/starter_packs/\(slug)/follow")
        }

        // Other servers' directories

        public static var directories: Endpoint {
            Endpoint(path: "api/v1/directories")
        }
        public static func directorySearch(
            _ query: String, source: String? = nil, limit: Int = 20
        ) -> Endpoint {
            Endpoint(
                path: "api/v1/directories/search",
                query: [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "limit", value: String(min(max(1, limit), 40))),
                ] + .optional("source", source))
        }
        public static func directoryHashtags(
            _ query: String? = nil, source: String? = nil, limit: Int = 20
        ) -> Endpoint {
            Endpoint(
                path: "api/v1/directories/hashtags",
                query: [URLQueryItem(name: "limit", value: String(min(max(1, limit), 40)))]
                    + .optional("q", query.flatMap { $0.isEmpty ? nil : $0 })
                    + .optional("source", source))
        }

        // Follow graph

        public static var followGraph: Endpoint {
            Endpoint(path: "api/v1/follow_graph")
        }
        public static var followGraphStatus: Endpoint {
            Endpoint(path: "api/v1/follow_graph/status")
        }

        // Pixelfed discover

        /// Trending posts, narrowed to pictures or video.
        public static func discoverPosts(media: String, limit: Int = 30) -> Endpoint {
            Endpoint(
                path: "api/v2/discover/posts",
                query: [
                    URLQueryItem(name: "media", value: media),
                    URLQueryItem(name: "limit", value: String(min(max(1, limit), 60))),
                ])
        }
        public static var categories: Endpoint {
            Endpoint(path: "api/v1.1/discover/categories", requiresAuthentication: false)
        }
        public static func popularAccounts(limit: Int = 20) -> Endpoint {
            Endpoint(
                path: "api/v1.1/discover/accounts/popular",
                query: [URLQueryItem(name: "limit", value: String(limit))])
        }

        // Mastodon fallback for the picture and video grids

        public static func trendingStatuses(limit: Int = 20) -> Endpoint {
            Endpoint(
                path: "api/v1/trends/statuses",
                query: [URLQueryItem(name: "limit", value: String(min(max(1, limit), 40)))],
                requiresAuthentication: false)
        }
    }

    /// The hashtag extras beyond Mastodon's own tag routes.
    public enum tagsExtra {
        /// Tags that travel with this one on public posts.
        public static func related(_ name: String, limit: Int = 20) -> Endpoint {
            Endpoint(
                path: "api/v1/tags/\(Tag.normalise(name) ?? name)/related",
                query: [URLQueryItem(name: "limit", value: String(min(max(1, limit), 40)))],
                requiresAuthentication: false)
        }
    }
}
