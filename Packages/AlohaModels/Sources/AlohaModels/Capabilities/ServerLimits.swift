// SPDX-License-Identifier: MIT

import Foundation

/// The server's own statement of what it will accept.
///
/// Rule from docs/02 §3: never hardcode any of these. The composer's counter,
/// the media picker's limits and the upload pre-flight all read from here.
/// Mastodon's documented defaults are the last resort, used only when both
/// `/api/v2/instance` and `/api/v1/instance` fail.
public struct ServerLimits: Codable, Sendable, Hashable {
    public var maxStatusCharacters: Int
    public var maxMediaAttachments: Int
    public var charactersReservedPerURL: Int
    /// Applies to everything. 10 MB by default on Nextcloud Social, because an
    /// image is read whole into memory to be stripped and resized.
    public var imageSizeLimit: Int
    /// Video only. 2048 MB by default — a video is copied to storage a chunk at
    /// a time and never held, so it gets a far larger ceiling.
    public var videoSizeLimit: Int
    public var supportedMIMETypes: [String]
    public var maxPollOptions: Int
    public var maxPollOptionCharacters: Int
    public var minPollExpiration: TimeInterval
    public var maxPollExpiration: TimeInterval
    public var maxFeaturedTags: Int

    public static let mastodonDefaults = ServerLimits(
        maxStatusCharacters: 500,
        maxMediaAttachments: 4,
        charactersReservedPerURL: 23,
        imageSizeLimit: 10 * 1024 * 1024,
        videoSizeLimit: 40 * 1024 * 1024,
        supportedMIMETypes: [
            "image/jpeg", "image/png", "image/gif", "image/webp", "image/heic", "image/heif",
            "video/mp4", "video/quicktime", "video/webm", "audio/mpeg", "audio/mp4", "audio/ogg",
        ],
        maxPollOptions: 4,
        maxPollOptionCharacters: 50,
        minPollExpiration: 300,
        maxPollExpiration: 2_629_746,
        maxFeaturedTags: 10
    )

    public init(
        maxStatusCharacters: Int, maxMediaAttachments: Int, charactersReservedPerURL: Int,
        imageSizeLimit: Int, videoSizeLimit: Int, supportedMIMETypes: [String],
        maxPollOptions: Int, maxPollOptionCharacters: Int, minPollExpiration: TimeInterval,
        maxPollExpiration: TimeInterval, maxFeaturedTags: Int
    ) {
        self.maxStatusCharacters = maxStatusCharacters
        self.maxMediaAttachments = maxMediaAttachments
        self.charactersReservedPerURL = charactersReservedPerURL
        self.imageSizeLimit = imageSizeLimit
        self.videoSizeLimit = videoSizeLimit
        self.supportedMIMETypes = supportedMIMETypes
        self.maxPollOptions = maxPollOptions
        self.maxPollOptionCharacters = maxPollOptionCharacters
        self.minPollExpiration = minPollExpiration
        self.maxPollExpiration = maxPollExpiration
        self.maxFeaturedTags = maxFeaturedTags
    }

    /// The ceiling that applies to one file, which of the two depends on
    /// whether the server will treat it as video.
    public func sizeLimit(forMIMEType mimeType: String) -> Int {
        mimeType.hasPrefix("video/") ? videoSizeLimit : imageSizeLimit
    }

    public func accepts(mimeType: String) -> Bool {
        supportedMIMETypes.isEmpty || supportedMIMETypes.contains(mimeType)
    }
}
