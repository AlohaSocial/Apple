// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

extension Endpoint {
    /// What a story can do beyond being watched: reactions and replies from
    /// the audience, and the audience itself for the poster. Pixelfed's
    /// routes, because these are Pixelfed's feature (docs/02 §2).
    ///
    /// Pixelfed names the story in a `sid` parameter rather than in the path,
    /// and these are its v1.1 and v1.2 routes verbatim — `PixelfedController`
    /// serves no `/api/v1/stories/{id}/…` shape at all, so a path-style call
    /// here 404s however reasonable it looks.
    public enum storyExtras {
        /// Pixelfed's v1.2 rail: `{self, nodes}` rather than a flat array.
        public static var carouselV2: Endpoint { Endpoint(path: "api/v1.2/stories/carousel") }

        /// Who watched one of the viewer's own stories. Account entities.
        public static func viewers(_ id: String) -> Endpoint {
            Endpoint(
                path: "api/v1.2/stories/viewers",
                query: [URLQueryItem(name: "sid", value: id)])
        }

        /// An emoji, at most 20 characters, sent to the poster and nobody else.
        public static func react(_ id: String, reaction: String) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1.2/stories/react",
                body: .form([
                    URLQueryItem(name: "sid", value: id),
                    URLQueryItem(name: "reaction", value: String(reaction.prefix(20))),
                ]))
        }

        /// A reply, delivered to the poster as a direct message rather than
        /// federated as a post.
        public static func comment(_ id: String, caption: String) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1.2/stories/comment",
                body: .form([
                    URLQueryItem(name: "sid", value: id),
                    URLQueryItem(name: "caption", value: String(caption.prefix(500))),
                ]))
        }

        /// Reactions and replies to one of the viewer's own stories.
        public static func reactions(_ id: String) -> Endpoint {
            Endpoint(
                path: "api/v1.2/stories/reactions",
                query: [URLQueryItem(name: "sid", value: id)])
        }

        /// Ends one of the viewer's own stories before its day is up.
        ///
        /// Pixelfed's name for it. `DELETE /api/v1/stories/{id}` does the same
        /// thing; this is the route its own app calls, and the one the web
        /// client's viewer offers behind "Remove".
        public static func selfExpire(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1.1/stories/self-expire/\(id)")
        }

        /// People the writer may name in a story's caption.
        public static func mentionAutocomplete(_ query: String) -> Endpoint {
            Endpoint(
                path: "api/v1.2/stories/mention-autocomplete",
                query: [URLQueryItem(name: "q", value: query)])
        }
    }
}
