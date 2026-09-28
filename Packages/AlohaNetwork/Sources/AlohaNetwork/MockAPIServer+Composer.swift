// SPDX-License-Identifier: MIT

import Foundation

extension MockAPIServer {
    /// Mock answers for the composer's Nextcloud extras: places, the GIF
    /// library, team accounts and the media focal point. `nil` means "not mine".
    func composerMock(
        route: String, url: URL, method: String, query: [URLQueryItem], body: Data?
    ) -> (Data, HTTPURLResponse)? {
        switch route {
        case "api/v1/places/search":
            let q = (query.first { $0.name == "q" }?.value ?? "").lowercased()
            let places: [[String: Any]] = [
                ["id": "p1", "name": "Berlin", "country": "Germany", "lat": 52.52, "lon": 13.405],
                ["id": "p2", "name": "Stuttgart", "country": "Germany"],
                ["id": "p3", "name": "Honolulu", "country": "United States"],
            ]
            let hits = places.filter {
                q.isEmpty || (($0["name"] as? String) ?? "").lowercased().hasPrefix(q)
            }
            return respond(url: url, status: 200, json: hits)

        case let path where path.hasPrefix("api/v1/places/"):
            let id = String(path.dropFirst("api/v1/places/".count))
            guard id == "p1" else {
                return respond(url: url, status: 404, body: #"{"error":"Record not found"}"#)
            }
            return respond(
                url: url, status: 200,
                json: [
                    "id": "p1", "name": "Berlin", "country": "Germany",
                ])

        case "api/v1/gifs":
            let q = (query.first { $0.name == "q" }?.value ?? "").lowercased()
            let all = ["wave", "party", "thumbs-up", "confetti"].map { slug -> [String: Any] in
                [
                    "slug": slug, "title": slug.capitalized,
                    "url": "https://\(host)/gif/\(slug).png",
                    "preview_url": "https://\(host)/gif/\(slug)_small.png",
                    "width": 240, "height": 240,
                ]
            }
            let hits = all.filter { q.isEmpty || (($0["slug"] as? String) ?? "").contains(q) }
            return respond(
                url: url, status: 200,
                json: [
                    "gifs": hits, "total": hits.count,
                    "attribution": "Pictures from the instance's shared library.",
                ])

        case "api/v1/media/from-gif" where method == "POST":
            let fields = formFields(body)
            let slug = fields["slug"] ?? "wave"
            return respond(
                url: url, status: 200,
                json: [
                    "id": "gif-\(slug)",
                    "type": "image",
                    "url": "https://\(host)/gif/\(slug).png",
                    "preview_url": "https://\(host)/gif/\(slug)_small.png",
                    "remote_url": NSNull(),
                    "description": fields["description"] ?? slug,
                    "blurhash": "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
                    "meta": ["original": ["width": 240, "height": 240]],
                ])

        case "api/v1.1/teams":
            return respond(
                url: url, status: 200,
                json: [
                    "teams": [
                        [
                            "handle": "photographers", "name": "Photographers",
                            "avatar": "https://\(host)/avatars/photographers.png",
                        ]
                    ]
                ])

        case let path where path.hasPrefix("api/v1/media/") && method == "PUT":
            // The focal point (or a description) on an attachment: echo it back
            // on a fixture attachment so the composer's copy updates.
            let id = String(path.dropFirst("api/v1/media/".count))
            let fields = formFields(body)
            var meta: [String: Any] = ["original": ["width": 1600, "height": 1200]]
            if let focus = fields["focus"] {
                let parts = focus.split(separator: ",").compactMap { Double($0) }
                if parts.count == 2 { meta["focus"] = ["x": parts[0], "y": parts[1]] }
            }
            return respond(
                url: url, status: 200,
                json: [
                    "id": id,
                    "type": "image",
                    "url": "https://\(host)/media/\(id).jpg",
                    "preview_url": "https://\(host)/media/\(id)_small.jpg",
                    "remote_url": NSNull(),
                    "description": fields["description"] ?? "A test photograph.",
                    "blurhash": "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
                    "meta": meta,
                ])

        default:
            return nil
        }
    }
}
