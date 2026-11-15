// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// How many of the pictures an account posted carry a description.
///
/// Counted per *picture*, not per post, the way the server counts it
/// (`StatisticsService::forAccount`): a post with four pictures and one
/// description is not three-quarters done. Read from the statistics when the
/// server sends the figure; worked out on this device from the account's own
/// recent posts when it does not, and the screen says which.
nonisolated struct AltTextCoverage: Hashable, Sendable {
    enum Source: Hashable, Sendable {
        /// The server counted every post in the statistics window.
        case server
        /// Counted here, from this many of the account's latest posts with
        /// media.
        case recentPosts(Int)
    }

    var pictures: Int
    var described: Int
    var source: Source

    /// 0…1, or `nil` with no pictures to speak of.
    var share: Double? {
        pictures > 0 ? Double(min(described, pictures)) / Double(pictures) : nil
    }

    init(pictures: Int, described: Int, source: Source) {
        self.pictures = pictures
        self.described = described
        self.source = source
    }

    /// The server's figure, or `nil` from a server that does not count it.
    /// `pictures` is the key an earlier server used for the same number.
    init?(statistics: AccountStatistics) {
        let media = statistics.media
        guard let pictures = media["images"] ?? media["pictures"],
            let described = media["described"], pictures.isFinite, described.isFinite
        else { return nil }
        self.init(
            pictures: max(0, Int(pictures)), described: max(0, Int(described)), source: .server)
    }

    /// Counted from the account's own posts. Boosts are somebody else's
    /// pictures and are left out; so is anything that is not a picture,
    /// since a video's description is a different job.
    init(posts: [Status]) {
        let own = posts.filter { $0.reblog == nil }
        var pictures = 0
        var described = 0
        for post in own {
            for attachment in post.mediaAttachments
            where attachment.type == .image || attachment.type == .gifv {
                pictures += 1
                if attachment.hasAltText { described += 1 }
            }
        }
        self.init(pictures: pictures, described: described, source: .recentPosts(own.count))
    }
}
