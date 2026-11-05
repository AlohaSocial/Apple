// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import Foundation

/// What `POST /api/v1/statuses` answered.
///
/// A post sent with a `scheduled_at` does not exist yet, so Mastodon answers
/// with the scheduled post instead — an id, the time, the parameters it will
/// be made from, and no `account` — which no `Status` can be read from. The
/// same request can still come back as a plain status: a time already past
/// is posted at once (`PostStatusService#scheduled_in_the_past?`), and a
/// server that does not schedule at all simply posts.
enum PostResponse: Sendable {
    case posted(Status)
    case scheduled(ScheduledStatus)

    /// `scheduledAt` is what the post asked for. Without one the answer is a
    /// status and nothing else; with one, either shape is a success.
    ///
    /// A body that is neither throws `APIError.decoding`, as the client's own
    /// `decode` would, so a caller tells it apart from a refusal the same way.
    init(decoding data: Data, scheduledAt: Date?) throws {
        if scheduledAt != nil,
            let scheduled = try? AlohaJSON.decoder.decode(ScheduledStatus.self, from: data)
        {
            self = .scheduled(scheduled)
            return
        }
        do {
            self = .posted(try AlohaJSON.decoder.decode(Status.self, from: data))
        } catch {
            throw APIError.decoding(underlying: error, context: "api/v1/statuses")
        }
    }
}
