// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

// The account-side routes: editing the profile, featured hashtags, authorized
// apps, the portfolio, migration, statistics and channels. Everything past
// `update_credentials` and `featured_tags` is Nextcloud Social's own.

/// What `PATCH /api/v1/accounts/update_credentials` may change. Only the
/// fields that are set are sent, so a save touches nothing it did not mean to.
public struct CredentialsUpdate: Sendable, Hashable {
    public struct Picture: Sendable, Hashable {
        public var data: Data
        public var filename: String
        public var mimeType: String

        public init(data: Data, filename: String, mimeType: String) {
            self.data = data
            self.filename = filename
            self.mimeType = mimeType
        }
    }

    public var displayName: String?
    public var note: String?
    public var avatar: Picture?
    public var header: Picture?
    public var fields: [Account.Field]?
    public var locked: Bool?
    public var discoverable: Bool?
    public var indexable: Bool?
    public var bot: Bool?
    public var privacy: Visibility?
    public var sensitive: Bool?
    public var language: String?

    public init(
        displayName: String? = nil, note: String? = nil, avatar: Picture? = nil,
        header: Picture? = nil, fields: [Account.Field]? = nil, locked: Bool? = nil,
        discoverable: Bool? = nil, indexable: Bool? = nil, bot: Bool? = nil,
        privacy: Visibility? = nil, sensitive: Bool? = nil, language: String? = nil
    ) {
        self.displayName = displayName
        self.note = note
        self.avatar = avatar
        self.header = header
        self.fields = fields
        self.locked = locked
        self.discoverable = discoverable
        self.indexable = indexable
        self.bot = bot
        self.privacy = privacy
        self.sensitive = sensitive
        self.language = language
    }

    public var isEmpty: Bool { parts.isEmpty }

    var parts: [Multipart.Part] {
        var parts: [Multipart.Part] = []
        if let displayName { parts.append(.field("display_name", displayName)) }
        if let note { parts.append(.field("note", note)) }
        if let avatar {
            parts.append(
                .init(
                    name: "avatar", filename: avatar.filename, mimeType: avatar.mimeType,
                    data: avatar.data))
        }
        if let header {
            parts.append(
                .init(
                    name: "header", filename: header.filename, mimeType: header.mimeType,
                    data: header.data))
        }
        if let fields {
            for (index, field) in fields.enumerated() {
                parts.append(.field("fields_attributes[\(index)][name]", field.name))
                parts.append(.field("fields_attributes[\(index)][value]", field.value))
            }
        }
        if let locked { parts.append(.field("locked", locked ? "true" : "false")) }
        if let discoverable {
            parts.append(.field("discoverable", discoverable ? "true" : "false"))
        }
        if let indexable { parts.append(.field("indexable", indexable ? "true" : "false")) }
        if let bot { parts.append(.field("bot", bot ? "true" : "false")) }
        if let privacy { parts.append(.field("source[privacy]", privacy.rawValue)) }
        if let sensitive { parts.append(.field("source[sensitive]", sensitive ? "true" : "false")) }
        if let language { parts.append(.field("source[language]", language)) }
        return parts
    }
}

extension Endpoint {
    public enum credentials {
        /// Multipart even without a picture: one encoding for every save.
        public static func update(_ changes: CredentialsUpdate) -> Endpoint {
            Endpoint(
                method: .patch, path: "api/v1/accounts/update_credentials",
                body: .multipart(Multipart(parts: changes.parts)))
        }

        /// Removes the picture; the server falls back to the initials it draws.
        public static var deleteAvatar: Endpoint {
            Endpoint(method: .delete, path: "api/v1/profile/avatar")
        }

        public static var deleteHeader: Endpoint {
            Endpoint(method: .delete, path: "api/v1/profile/header")
        }
    }

    public enum featuredTags {
        public static var all: Endpoint { Endpoint(path: "api/v1/featured_tags") }
        /// Hashtags the viewer posts with and has not featured.
        public static var suggestions: Endpoint {
            Endpoint(path: "api/v1/featured_tags/suggestions")
        }
        public static func create(name: String) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/featured_tags",
                body: .form([URLQueryItem(name: "name", value: name)]))
        }
        public static func delete(_ id: String) -> Endpoint {
            Endpoint(method: .delete, path: "api/v1/featured_tags/\(id)")
        }
    }

    /// The account itself, as Nextcloud rather than Mastodon holds it.
    ///
    /// These are `LocalController` routes: `#[NoAdminRequired]`, which means a
    /// Nextcloud session and not a bearer token, so they go out with the app
    /// password as HTTP Basic. Without one they are refused on the device and
    /// the screen says to connect Nextcloud first (docs/03 §5).
    public enum socialAccount {
        /// Deletes the reader's Social account and keeps their Nextcloud one:
        /// the posts, the follows, and a `Delete` to every server that knew
        /// them. **It cannot be undone.**
        ///
        /// `confirm` has to be the handle being deleted — deliberately not a
        /// password, because an account signed in through SSO has none to give.
        public static func delete(confirm handle: String) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/account/delete",
                body: .form([URLQueryItem(name: "confirm", value: handle)]),
                authentication: .nextcloudSession)
        }
    }

    public enum authorizedApps {
        public static var all: Endpoint { Endpoint(path: "api/v1/authorized_apps") }
        public static func revoke(_ id: String) -> Endpoint {
            Endpoint(method: .delete, path: "api/v1/authorized_apps/\(id)")
        }
    }

    /// Pixelfed's portfolio page, served by Nextcloud Social.
    public enum portfolio {
        public static var own: Endpoint { Endpoint(path: "api/v1.1/portfolio") }

        public static func save(_ settings: PortfolioSettings) -> Endpoint {
            var items: [URLQueryItem] = [
                URLQueryItem(name: "active", value: settings.active ? "1" : "0"),
                URLQueryItem(name: "title", value: settings.title),
                URLQueryItem(name: "intro", value: settings.intro),
                URLQueryItem(name: "layout", value: settings.layout.rawValue),
                URLQueryItem(name: "source", value: settings.source.rawValue),
                URLQueryItem(name: "show_captions", value: settings.showCaptions ? "1" : "0"),
                URLQueryItem(name: "show_places", value: settings.showPlaces ? "1" : "0"),
                URLQueryItem(name: "show_dates", value: settings.showDates ? "1" : "0"),
                URLQueryItem(name: "show_avatar", value: settings.showAvatar ? "1" : "0"),
            ]
            items += .optional("collection_id", settings.collectionID)
            return Endpoint(method: .post, path: "api/v1.1/portfolio", body: .form(items))
        }

        /// The published page. Anybody may read it, so no token is needed.
        public static func page(handle: String) -> Endpoint {
            Endpoint(path: "api/v1.1/portfolio/\(handle)", requiresAuthentication: false)
        }

        /// The viewer's own albums, for the picture-source picker.
        public static var ownCollections: Endpoint { Endpoint(path: "api/v1.1/collections/self") }
    }

    /// Taking the account somewhere else, or bringing one here.
    public enum migration {
        public enum ListKind: String, Sendable, Hashable, CaseIterable {
            case following, followers, blocks, mutes, lists

            /// The route an import of this kind lives at. Following goes in
            /// as `follows`; the rest keep their name.
            var importPath: String { self == .following ? "follows" : rawValue }
        }

        /// The whole account as a zip: profile, posts, media, relationships.
        public static var exportArchive: Endpoint { Endpoint(path: "api/v1/migration/export") }

        public static func exportList(_ kind: ListKind) -> Endpoint {
            Endpoint(path: "api/v1/migration/export/\(kind.rawValue)")
        }

        public static func importArchive(_ data: Data, filename: String) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/migration/import",
                body: .multipart(
                    Multipart(parts: [
                        .init(
                            name: "file", filename: filename, mimeType: "application/zip",
                            data: data)
                    ])))
        }

        public static func importList(_ kind: ListKind, csv: Data, filename: String) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/migration/\(kind.importPath)",
                body: .multipart(
                    Multipart(parts: [
                        .init(name: "file", filename: filename, mimeType: "text/csv", data: csv)
                    ])))
        }

        public static func importPosts(_ data: Data, filename: String, fetchMedia: Bool) -> Endpoint
        {
            Endpoint(
                method: .post, path: "api/v1/migration/posts",
                query: [URLQueryItem(name: "fetch_media", value: fetchMedia ? "1" : "0")],
                body: .multipart(
                    Multipart(parts: [
                        .init(
                            name: "file", filename: filename, mimeType: "application/zip",
                            data: data)
                    ])))
        }

        /// One video by its address on another server.
        public static func importVideo(url: String, fetchMedia: Bool) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/migration/video",
                body: .form([
                    URLQueryItem(name: "url", value: url),
                    URLQueryItem(name: "fetch_media", value: fetchMedia ? "1" : "0"),
                ]))
        }

        /// Candidate handles out of an Instagram archive.
        public static func instagramPeople(_ data: Data, filename: String) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/migration/people",
                body: .multipart(
                    Multipart(parts: [
                        .init(
                            name: "file", filename: filename, mimeType: "application/zip",
                            data: data)
                    ])))
        }

        public static func findPeople(_ handles: [String]) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/migration/people/find",
                body: .form(.repeated("handles", handles)))
        }

        public static var announcement: Endpoint { Endpoint(path: "api/v1/migration/announcement") }

        public static var aliases: Endpoint { Endpoint(path: "api/v1/migration/aliases") }

        public static func addAlias(_ alias: String) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/migration/aliases",
                body: .form([URLQueryItem(name: "alias", value: alias)]))
        }

        /// The alias rides in the query: a DELETE with a body is dropped by
        /// some of the proxies a Nextcloud sits behind.
        public static func removeAlias(_ alias: String) -> Endpoint {
            Endpoint(
                method: .delete, path: "api/v1/migration/aliases",
                query: [URLQueryItem(name: "alias", value: alias)])
        }
    }

    public enum statistics {
        /// `days` 0 means everything. `fresh` bypasses the server's cache.
        public static func overview(days: Int, fresh: Bool = false) -> Endpoint {
            Endpoint(
                path: "api/v1/statistics",
                query: [URLQueryItem(name: "days", value: String(days))] + .flag("fresh", fresh))
        }

        public static func export(days: Int, format: String = "csv") -> Endpoint {
            Endpoint(
                path: "api/v1/statistics/export",
                query: [
                    URLQueryItem(name: "days", value: String(days)),
                    URLQueryItem(name: "format", value: format),
                ])
        }
    }

    public enum channels {
        public static var all: Endpoint { Endpoint(path: "api/v1/channels") }

        public static func create(handle: String, name: String, description: String) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/channels",
                body: .form([
                    URLQueryItem(name: "handle", value: handle),
                    URLQueryItem(name: "name", value: name),
                    URLQueryItem(name: "description", value: description),
                ]))
        }

        public static func update(_ id: String, name: String, description: String) -> Endpoint {
            Endpoint(
                method: .put, path: "api/v1/channels/\(id)",
                body: .form([
                    URLQueryItem(name: "name", value: name),
                    URLQueryItem(name: "description", value: description),
                ]))
        }
    }
}
