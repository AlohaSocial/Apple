// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

// Aloha Social's Bluesky side: the feeds the reader keeps there, and their
// own identity. Every route here is `#[NoAdminRequired]` without
// `#[PublicPage]` — a Nextcloud session, not the Social token — so they go out
// with the app password and are refused on the device without one (docs/03 §5).
//
// With Bluesky switched off on the server every one of them answers 404
// `{"error": "Bluesky is not enabled on this server"}`, which is how the app
// finds out; there is no capability to read it from.
//
// Moving an account, recovery phrases, the archive, labelers and Bluesky app
// passwords are deliberately not here: they are set up once, in the web
// interface, and several of them need a password confirmation an app password
// cannot give.

extension Endpoint {
    public enum bluesky {
        /// The feeds and lists the reader keeps, pinned ones first.
        public static var feeds: Endpoint {
            Endpoint(path: "api/v1/social/bluesky/feeds", authentication: .nextcloudSession)
        }

        /// The feeds Bluesky suggests to the reader.
        public static var suggestedFeeds: Endpoint {
            Endpoint(
                path: "api/v1/social/bluesky/feeds/suggested", authentication: .nextcloudSession)
        }

        /// Keeps a feed or list, by its `at://` URI or its bsky.app address.
        /// Answers `{"feed": …}`, pinned.
        public static func addFeed(_ feed: String) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/social/bluesky/feeds",
                body: .form([URLQueryItem(name: "feed", value: feed)]),
                authentication: .nextcloudSession)
        }

        /// `uri` in the query: Nextcloud reads a form body only on the
        /// methods that are meant to carry one.
        public static func removeFeed(uri: String) -> Endpoint {
            Endpoint(
                method: .delete, path: "api/v1/social/bluesky/feeds",
                query: [URLQueryItem(name: "uri", value: uri)],
                authentication: .nextcloudSession)
        }

        /// The reader's own identity, made now if their account has none.
        public static var identity: Endpoint {
            Endpoint(path: "api/v1/social/bluesky/identity", authentication: .nextcloudSession)
        }

        /// Switches the reader's presence on Bluesky off or on. Off, the
        /// account is deactivated there; the DID and the handle stay theirs.
        /// Answers the identity.
        public static func setActive(_ active: Bool) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/social/bluesky/state",
                body: .form([URLQueryItem(name: "active", value: active ? "1" : "0")]),
                authentication: .nextcloudSession)
        }

        /// Whether the reader's blocks of Bluesky accounts are published
        /// there, where a block is public. Answers `{"publish_blocks": bool}`.
        public static func setPublishBlocks(_ publish: Bool) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/social/bluesky/publish-blocks",
                body: .form([URLQueryItem(name: "publish", value: publish ? "1" : "0")]),
                authentication: .nextcloudSession)
        }
    }
}

/// What the app can say about Bluesky on this account's server.
public enum BlueskyAvailability: Sendable, Hashable {
    /// The server reads Bluesky for this account.
    case available
    /// The server has Bluesky switched off, or is not Aloha Social.
    case off
    /// The routes need the Nextcloud app password, and there is none.
    case needsNextcloudConnection
    /// Nothing could be learned — a network failure. Treated as absent.
    case unknown

    public var isAvailable: Bool { self == .available }

    /// Asks the one route that answers for everybody whose server reads
    /// Bluesky — the kept feeds — and reads the refusal. `identity` would 404
    /// for a reader who simply has none, which says nothing about the server.
    public static func probe(_ client: APIClient) async -> BlueskyAvailability {
        guard await client.hasNextcloudAuthorization else { return .needsNextcloudConnection }
        do {
            _ = try await client.decode(BlueskyFeedList.self, from: Endpoint.bluesky.feeds)
            return .available
        } catch let error as APIError {
            switch error {
            case .notFound: return .off
            case .unauthorised: return .needsNextcloudConnection
            case .transport, .rateLimited: return .unknown
            // A server that reads Bluesky but could not reach it (502) still
            // has Bluesky; the screen says what went wrong when it is opened.
            case .server: return .available
            default: return .off
            }
        } catch {
            return .unknown
        }
    }
}
