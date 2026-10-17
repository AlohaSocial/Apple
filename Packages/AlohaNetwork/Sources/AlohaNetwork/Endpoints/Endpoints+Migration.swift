// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

// Moving an account, and the queue imports run on (`MigrationController`).
//
// Two credentials, route by route. The move-in, import and export routes are
// `#[PublicPage]` and read the caller themselves, so the Social token reaches
// them (docs/API.md, "account pages a client app shows"). Moving *away* —
// status, move and undo — is `#[NoAdminRequired]` without `#[PublicPage]`: a
// Nextcloud session only, so those go out with the app password. The move
// and its undo also carry `#[PasswordConfirmationRequired]`; whether an app
// password satisfies that depends on the Nextcloud, and a refusal comes back
// as the server's own message.

/// A list one account can carry to another as a CSV, the way Mastodon,
/// Pixelfed, GoToSocial and Akkoma export them.
public enum MigrationListKind: String, Sendable, Hashable, CaseIterable, Identifiable {
    case following, followers, blocks, mutes, lists, bookmarks
    case domainBlocks = "domain_blocks"

    public var id: String { rawValue }

    /// The name under `/api/v1/migration/export/{kind}`.
    public var exportName: String { rawValue }

    /// The route an import of this kind is queued at, or `nil`. Followers
    /// cannot be imported: they are other people's decision, and arrive with
    /// the old server's `Move` instead.
    public var importPath: String? {
        switch self {
        case .following: "follows"
        case .followers: nil
        default: rawValue
        }
    }
}

extension Endpoint.migration {
    public static func export(_ kind: MigrationListKind) -> Endpoint {
        Endpoint(path: "api/v1/migration/export/\(kind.exportName)")
    }

    /// Queues the import: answers `202 {"import": …}`. `nil` for a kind that
    /// cannot be imported.
    public static func queueImport(
        _ kind: MigrationListKind, csv: Data, filename: String
    ) -> Endpoint? {
        guard let path = kind.importPath else { return nil }
        return Endpoint(
            method: .post, path: "api/v1/migration/\(path)",
            body: .multipart(
                Multipart(parts: [
                    .init(name: "file", filename: filename, mimeType: "text/csv", data: csv)
                ])))
    }

    // MARK: - The queue

    /// Every import this account asked for, newest first, with how far each
    /// got: `{"imports": […]}`.
    public static var imports: Endpoint { Endpoint(path: "api/v1/migration/imports") }

    /// Takes a finished import off the list. Answers the list as it now is.
    public static func dismissImport(_ id: String) -> Endpoint {
        Endpoint(method: .delete, path: "api/v1/migration/imports/\(id)")
    }

    // MARK: - Moving here

    /// Reads the old account off its own server before anything happens:
    /// `{"account": …}`.
    public static func inspectMoveIn(handle: String) -> Endpoint {
        Endpoint(
            method: .post, path: "api/v1/migration/move-in/inspect",
            body: .form([URLQueryItem(name: "handle", value: handle)]))
    }

    /// Sets the old account as an alias now, and queues following who it
    /// follows and bringing its public posts over.
    public static func moveIn(
        handle: String, follows: Bool, posts: Bool, fetchMedia: Bool
    ) -> Endpoint {
        Endpoint(
            method: .post, path: "api/v1/migration/move-in",
            body: .form([
                URLQueryItem(name: "handle", value: handle),
                URLQueryItem(name: "follows", value: follows ? "1" : "0"),
                URLQueryItem(name: "posts", value: posts ? "1" : "0"),
                URLQueryItem(name: "fetch_media", value: fetchMedia ? "1" : "0"),
            ]))
    }

    /// When the old server is Aloha Social too, starts the last step from
    /// here: answers the address where the person consents on the old server.
    public static func finishMoveIn(handle: String, bluesky: BlueskyAfterMove) -> Endpoint {
        Endpoint(
            method: .post, path: "api/v1/migration/move-in/finish",
            body: .form([
                URLQueryItem(name: "handle", value: handle),
                URLQueryItem(name: "bluesky", value: bluesky.rawValue),
            ]))
    }

    public static var moveInFinishStatus: Endpoint {
        Endpoint(path: "api/v1/migration/move-in/finish")
    }

    // MARK: - Moving away

    public static var moveStatus: Endpoint {
        Endpoint(path: "api/v1/migration/move", authentication: .nextcloudSession)
    }

    /// Moves this account to `target`, which must already name this one as
    /// an alias. `confirm` is this account's own handle, typed back.
    public static func moveAway(
        to target: String, confirm: String, bluesky: BlueskyAfterMove
    ) -> Endpoint {
        Endpoint(
            method: .post, path: "api/v1/migration/move",
            body: .form([
                URLQueryItem(name: "target", value: target),
                URLQueryItem(name: "confirm", value: confirm),
                URLQueryItem(name: "bluesky", value: bluesky.rawValue),
            ]),
            authentication: .nextcloudSession)
    }

    /// Takes the redirect off again. The followers do not come back by
    /// themselves; what returns is the right to post and follow from here.
    public static var undoMove: Endpoint {
        Endpoint(
            method: .delete, path: "api/v1/migration/move", authentication: .nextcloudSession)
    }
}
