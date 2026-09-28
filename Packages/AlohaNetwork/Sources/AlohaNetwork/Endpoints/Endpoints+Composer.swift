// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

// MARK: - Composer extras (Nextcloud Social)

extension Endpoint {
    /// The shared library of animated pictures. Served by the instance itself,
    /// so nothing about a search leaves it (no third-party GIF service).
    public enum gifs {
        public static func library(query: String?, limit: Int = 40, offset: Int = 0) -> Endpoint {
            Endpoint(
                path: "api/v1/gifs",
                query: .optional("q", query.flatMap { $0.isEmpty ? nil : $0 }) + [
                    URLQueryItem(name: "limit", value: String(min(max(1, limit), 200))),
                    URLQueryItem(name: "offset", value: String(max(0, offset))),
                ])
        }

        /// Attaches a library picture as a media attachment, the way an upload
        /// would have.
        public static func attach(slug: String, description: String?) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/media/from-gif",
                body: .form(
                    [URLQueryItem(name: "slug", value: slug)]
                        + .optional("description", description)))
        }
    }

    /// Places a post can be tagged with. Names only; no map service is
    /// involved on either side.
    public enum places {
        public static func search(_ query: String, limit: Int = 10) -> Endpoint {
            Endpoint(
                path: "api/v1/places/search",
                query: [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "limit", value: String(min(max(1, limit), 40))),
                ])
        }

        public static func place(_ id: String) -> Endpoint {
            Endpoint(path: "api/v1/places/\(id)", requiresAuthentication: false)
        }
    }

    /// Team accounts the viewer may post as.
    public enum teams {
        public static var all: Endpoint { Endpoint(path: "api/v1.1/teams") }
    }

    public enum mediaExtra {
        /// The focal point, as Mastodon defines it: `x,y` in −1…1 with the
        /// origin in the centre. What a cropped preview keeps in frame.
        public static func updateFocus(
            _ id: String, x: Double, y: Double, description: String? = nil
        ) -> Endpoint {
            let clamp = { (value: Double) in min(max(value, -1), 1) }
            let focus = String(format: "%.2f,%.2f", clamp(x), clamp(y))
            return Endpoint(
                method: .put, path: "api/v1/media/\(id)",
                body: .form(
                    [URLQueryItem(name: "focus", value: focus)]
                        + .optional("description", description)))
        }
    }
}
