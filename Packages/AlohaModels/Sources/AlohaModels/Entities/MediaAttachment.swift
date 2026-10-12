// SPDX-License-Identifier: MIT

import Foundation

public struct MediaAttachment: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var type: AttachmentKind
    @LenientURL public var url: URL?
    /// For a video this is its poster frame, served as `image/jpeg` — a browser
    /// with `nosniff` on refuses to draw an image served as `video/mp4`.
    @LenientURL public var previewURL: URL?
    @LenientURL public var remoteURL: URL?
    /// The alt text. Travels as the ActivityPub `name`, both directions.
    public var description: String?
    public var blurhash: String?
    public var meta: Meta?

    /// **Nextcloud Social extension, not Mastodon's.** The master playlist of a
    /// local video's transcoding ladder, where the administrator turned
    /// `video_ladder` on and the background job has been over the video. `nil`
    /// everywhere else — and a client that ignores it plays `url` and gets the
    /// same video at one size. Never a *replacement* for `url`: the whole file
    /// is always there beside it (docs/02 §2).
    @LenientURL public var hlsURL: URL?

    public struct Meta: Codable, Sendable, Hashable {
        public var original: Dimensions?
        public var small: Dimensions?
        public var focus: Focus?

        public struct Dimensions: Codable, Sendable, Hashable {
            public var width: Int?
            public var height: Int?
            public var size: String?
            public var aspect: Double?
            public var duration: Double?
            public var frameRate: String?
            public var bitrate: Int?

            enum CodingKeys: String, CodingKey {
                case width, height, size, aspect, duration, bitrate
                case frameRate = "frame_rate"
            }

            public init(
                width: Int? = nil, height: Int? = nil, size: String? = nil, aspect: Double? = nil,
                duration: Double? = nil, frameRate: String? = nil, bitrate: Int? = nil
            ) {
                self.width = width
                self.height = height
                self.size = size
                self.aspect = aspect
                self.duration = duration
                self.frameRate = frameRate
                self.bitrate = bitrate
            }

            /// Width over height. Prefers the server's own `aspect` and falls
            /// back to the dimensions; `nil` when the server filled in neither,
            /// which is the case that defers Shorts classification (docs/06 §4).
            public var resolvedAspect: Double? {
                if let aspect, aspect > 0 { return aspect }
                guard let width, let height, height > 0 else { return nil }
                return Double(width) / Double(height)
            }
        }

        public struct Focus: Codable, Sendable, Hashable {
            public var x: Double
            public var y: Double
            public init(x: Double, y: Double) {
                self.x = x
                self.y = y
            }
        }

        public init(original: Dimensions? = nil, small: Dimensions? = nil, focus: Focus? = nil) {
            self.original = original
            self.small = small
            self.focus = focus
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, type, url, description, blurhash, meta
        case previewURL = "preview_url"
        case remoteURL = "remote_url"
        case hlsURL = "hls_url"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        type = try c.decodeIfPresent(AttachmentKind.self, forKey: .type) ?? .unknown
        _url = try c.decode(LenientURL.self, forKey: .url)
        _previewURL = try c.decode(LenientURL.self, forKey: .previewURL)
        _remoteURL = try c.decode(LenientURL.self, forKey: .remoteURL)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        blurhash = try c.decodeIfPresent(String.self, forKey: .blurhash)
        // Nextcloud Social always sends an object here, never a list — but a
        // fork that sends `[]` for "nothing" must not fail the attachment.
        meta = try? c.decodeIfPresent(Meta.self, forKey: .meta)
        _hlsURL = try c.decode(LenientURL.self, forKey: .hlsURL)
    }

    public init(
        id: String, type: AttachmentKind, url: URL? = nil, previewURL: URL? = nil,
        remoteURL: URL? = nil, description: String? = nil, blurhash: String? = nil,
        meta: Meta? = nil, hlsURL: URL? = nil
    ) {
        _id = .init(wrappedValue: id)
        self.type = type
        _url = .init(wrappedValue: url)
        _previewURL = .init(wrappedValue: previewURL)
        _remoteURL = .init(wrappedValue: remoteURL)
        self.description = description
        self.blurhash = blurhash
        self.meta = meta
        _hlsURL = .init(wrappedValue: hlsURL)
    }
}

extension MediaAttachment {
    public var hasAltText: Bool {
        guard let description else { return false }
        return !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var aspectRatio: Double? { meta?.original?.resolvedAspect }

    public var duration: Double? { meta?.original?.duration }

    /// True only for visual video attachments. Audio is playable, but must
    /// never enter the video or Shorts feeds.
    public var isVideo: Bool { type == .video || type == .gifv }

    /// The URL suitable for an image view. A playable attachment's `url` is
    /// media bytes, never a fallback thumbnail.
    public var displayImageURL: URL? {
        type.isPlayable ? previewURL : (previewURL ?? url)
    }

    /// A sensible box to lay out in before the bytes arrive, so nothing shifts.
    public var displayAspectRatio: Double { aspectRatio ?? 4.0 / 3.0 }
}
