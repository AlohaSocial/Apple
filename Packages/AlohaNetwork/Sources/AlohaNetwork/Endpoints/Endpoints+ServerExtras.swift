// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

// Smaller routes the server answers that the app had not asked yet: a poll
// read again, a post's reactions counted again, the accounts the reader
// features, one post covered by a filter, and Aloha Social's switch that
// turns replies to a shared file into comments on it.

extension Endpoint.statuses {
    /// The poll as it stands now: Mastodon's `GET /api/v1/polls/{id}`.
    public static func poll(_ id: String) -> Endpoint {
        Endpoint(path: "api/v1/polls/\(id)", requiresAuthentication: false)
    }

    /// The emoji reactions on a post, counted now: `[{name, count, me}]`. A
    /// post the reader may not see is a 404, and so are its reactions.
    public static func reactions(_ id: String) -> Endpoint {
        Endpoint(path: "api/v1/statuses/\(id)/reactions", requiresAuthentication: false)
    }
}

extension Endpoint.profile {
    /// The accounts the reader features on their own profile, as Account
    /// entities: Mastodon's endorsements.
    public static func endorsements(limit: Int = 40) -> Endpoint {
        Endpoint(
            path: "api/v1/endorsements",
            query: [URLQueryItem(name: "limit", value: String(limit))])
    }
}

extension Endpoint.filters {
    /// The posts a filter covers by name: `[{id, status_id}]`.
    public static func statuses(_ filterID: String) -> Endpoint {
        Endpoint(path: "api/v2/filters/\(filterID)/statuses")
    }

    /// Adds one post to a filter. Answers the entry, `{id, status_id}`.
    public static func addStatus(_ statusID: String, to filterID: String) -> Endpoint {
        Endpoint(
            method: .post, path: "api/v2/filters/\(filterID)/statuses",
            body: .form([URLQueryItem(name: "status_id", value: statusID)]))
    }

    /// Takes one post back off its filter, by the entry's own id.
    public static func removeStatus(entryID: String) -> Endpoint {
        Endpoint(method: .delete, path: "api/v2/filters/statuses/\(entryID)")
    }
}

extension Endpoint.readerSettings {
    /// Whether a reply to a post carrying a file from the reader's Nextcloud
    /// is also added to that file as a comment: `{"enabled": bool}`.
    public static var filesComments: Endpoint { Endpoint(path: "api/v1/social/files_comments") }

    /// `enabled` is required; a request unclear about it is a 422.
    public static func setFilesComments(enabled: Bool) -> Endpoint {
        Endpoint(
            method: .patch, path: "api/v1/social/files_comments",
            body: .json(Data((enabled ? #"{"enabled":true}"# : #"{"enabled":false}"#).utf8)))
    }
}
