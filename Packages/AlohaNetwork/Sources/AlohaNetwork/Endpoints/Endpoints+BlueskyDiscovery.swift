// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

// Discovering through Bluesky: trending topics, suggested accounts, starter
// packs, taking over the follows of a Bluesky account, and a handle on a
// domain of one's own (`AtprotoFeedsController`, `BlueskyFollowFromController`,
// `AtprotoAccountController`). Like the rest of the Bluesky routes these are
// `#[NoAdminRequired]` without `#[PublicPage]`: the app password, not the
// Social token.

extension Endpoint.bluesky {
    /// `{"trends": [{topic, label, feed, search}]}`.
    public static var trends: Endpoint {
        Endpoint(path: "api/v1/social/bluesky/trends", authentication: .nextcloudSession)
    }

    /// `{"accounts": […]}`: who Bluesky suggests to the reader.
    public static var suggestions: Endpoint {
        Endpoint(path: "api/v1/social/bluesky/suggestions", authentication: .nextcloudSession)
    }

    /// A starter pack by its bsky.app address or `at://` URI: `{"pack": …}`.
    public static func starterPack(_ pack: String) -> Endpoint {
        Endpoint(
            path: "api/v1/social/bluesky/starter-pack",
            query: [URLQueryItem(name: "pack", value: pack)],
            authentication: .nextcloudSession)
    }

    /// Follows the named members of a pack, a batch at a time, and keeps its
    /// feeds when asked to. Answers `{followed: [did], failed: [did]}`.
    public static func followStarterPack(
        _ pack: String, dids: [String], keepFeeds: Bool
    ) -> Endpoint {
        Endpoint(
            method: .post, path: "api/v1/social/bluesky/starter-pack/follow",
            body: .form(
                [URLQueryItem(name: "pack", value: pack)] + .repeated("dids", dids)
                    + [URLQueryItem(name: "feeds", value: keepFeeds ? "1" : "0")]),
            authentication: .nextcloudSession)
    }

    /// The largest batch the server follows in one request
    /// (`StarterPacks::FOLLOW_BATCH`).
    public static let starterPackFollowBatch = 25

    /// Follows from here everybody a Bluesky account follows, in the
    /// background: `202 {"import": …, "account": {did, handle}}`, and the
    /// migration imports list is where it gets to.
    public static func followFrom(_ account: String) -> Endpoint {
        Endpoint(
            method: .post, path: "api/v1/social/bluesky/follow-from",
            body: .form([URLQueryItem(name: "account", value: account)]),
            authentication: .nextcloudSession)
    }

    /// A handle on a domain the reader owns, once the domain names their DID.
    /// Needs Nextcloud's password confirmation. Answers the identity.
    public static func setHandle(_ handle: String) -> Endpoint {
        Endpoint(
            method: .post, path: "api/v1/social/bluesky/handle",
            body: .form([URLQueryItem(name: "handle", value: handle)]),
            authentication: .nextcloudSession)
    }

    /// Back to the handle this server assigned. Answers the identity.
    public static var clearHandle: Endpoint {
        Endpoint(
            method: .delete, path: "api/v1/social/bluesky/handle",
            authentication: .nextcloudSession)
    }
}
