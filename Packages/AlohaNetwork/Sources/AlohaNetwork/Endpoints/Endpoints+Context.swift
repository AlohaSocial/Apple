// SPDX-License-Identifier: MIT

import Foundation

// A conversation, and who liked or boosted a post, as Aloha Social fills
// them in: the server reads the rest of a thread, and the likes and boosts a
// post has where it lives, in the background, and says so in a header
// (docs/API.md, `/statuses/{nid}/context` and `/favourited_by`).

extension Endpoint.statuses {
    /// The thread, with the replies its first post's author hid
    /// (`with_hidden=true`) so the app can show them collapsed rather than
    /// not at all. Mastodon ignores the parameter.
    public static func context(_ id: String, includingHidden: Bool) -> Endpoint {
        Endpoint(
            path: "api/v1/statuses/\(id)/context",
            query: includingHidden ? [URLQueryItem(name: "with_hidden", value: "true")] : [],
            requiresAuthentication: false)
    }
}

/// What Aloha Social's `X-Social-*` headers said about an answer.
public struct SocialFilling: Sendable, Hashable {
    /// `X-Social-Thread-Filling: 1`: the rest of the conversation was just
    /// asked for where it lives, and asking again shortly adds it.
    public var isThreadFilling: Bool
    /// `X-Social-Filling: 1`: the same for counts, likes, boosts, quotes.
    public var isFilling: Bool
    /// `X-Social-Hidden-Replies`: how many replies the thread's author hid.
    public var hiddenReplies: Int?

    public init(isThreadFilling: Bool = false, isFilling: Bool = false, hiddenReplies: Int? = nil) {
        self.isThreadFilling = isThreadFilling
        self.isFilling = isFilling
        self.hiddenReplies = hiddenReplies
    }

    public init(_ response: RawResponse) {
        self.init(headers: response.socialHeaders)
    }

    /// From headers keyed in lower case, as `RawResponse` holds them.
    public init(headers: [String: String]) {
        func flag(_ name: String) -> Bool {
            headers[name]?.trimmingCharacters(in: .whitespaces) == "1"
        }
        isThreadFilling = flag("x-social-thread-filling")
        isFilling = flag("x-social-filling")
        hiddenReplies = headers["x-social-hidden-replies"].flatMap {
            Int($0.trimmingCharacters(in: .whitespaces))
        }
    }

    /// Whether anything is still on its way.
    public var isStillFilling: Bool { isThreadFilling || isFilling }
}

/// When to ask again while the server is still filling an answer in.
///
/// The server's own web app asks once more after a few seconds. Two more
/// asks, three and then six seconds apart, give a slow federated thread a
/// second chance without the app polling a busy server: past that, what has
/// arrived is what the reader gets, and pulling to refresh asks again.
public struct FillingRetryPolicy: Sendable, Hashable {
    public var delays: [Duration]

    public init(delays: [Duration] = [.seconds(3), .seconds(6)]) {
        self.delays = delays
    }

    /// How long to wait before ask number `attempt + 1` (`attempt` counts
    /// the asks already made, from 1), or nil to stop.
    public func delay(after attempt: Int, filling: SocialFilling) -> Duration? {
        guard filling.isStillFilling, attempt >= 1, attempt <= delays.count else { return nil }
        return delays[attempt - 1]
    }
}
