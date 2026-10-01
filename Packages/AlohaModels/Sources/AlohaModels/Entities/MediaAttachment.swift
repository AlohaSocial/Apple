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
        /// Seconds, at the top level. Where Nextcloud puts a locally uploaded
        /// video's length (`AttachmentMeta::$duration`), rather than under
        /// `original` as Mastodon does.
        public var duration: Double?

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

            /// Every field on its own: one value in a shape this did not expect
            /// must cost that field, not the whole `meta` — `meta` is decoded
            /// with `try?`, so a throw here used to drop the aspect ratio and
            /// the duration along with it. Nextcloud sends `frame_rate` as a
            /// number (`AttachmentMetaDim::getFloat`); Mastodon sends `"30/1"`.
            public init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                width = Self.number(c, .width).map { Int($0) }
                height = Self.number(c, .height).map { Int($0) }
                size = try? c.decodeIfPresent(String.self, forKey: .size)
                aspect = Self.number(c, .aspect)
                duration = Self.number(c, .duration)
                bitrate = Self.number(c, .bitrate).map { Int($0) }
                if let text = try? c.decodeIfPresent(String.self, forKey: .frameRate) {
                    frameRate = text
                } else if let value = try? c.decodeIfPresent(Double.self, forKey: .frameRate) {
                    frameRate = value.rounded() == value ? String(Int(value)) : String(value)
                } else {
                    frameRate = nil
                }
            }

            /// A number, or a string holding one: both turn up in the wild.
            static func number(
                _ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
            )
                -> Double?
            {
                if let value = try? c.decodeIfPresent(Double.self, forKey: key) { return value }
                if let text = try? c.decodeIfPresent(String.self, forKey: key) {
                    return Double(text)
                }
                return nil
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

        enum CodingKeys: String, CodingKey {
            case original, small, focus, duration
        }

        public init(
            original: Dimensions? = nil, small: Dimensions? = nil, focus: Focus? = nil,
            duration: Double? = nil
        ) {
            self.original = original
            self.small = small
            self.focus = focus
            self.duration = duration
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            original = try? c.decodeIfPresent(Dimensions.self, forKey: .original)
            small = try? c.decodeIfPresent(Dimensions.self, forKey: .small)
            focus = try? c.decodeIfPresent(Focus.self, forKey: .focus)
            duration =
                (try? c.decodeIfPresent(Double.self, forKey: .duration))
                ?? (try? c.decodeIfPresent(String.self, forKey: .duration)).flatMap { $0 }
                .flatMap(Double.init)
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

    /// Mastodon's place first, then Nextcloud's for a local upload.
    public var duration: Double? { meta?.original?.duration ?? meta?.duration }

    /// A sensible box to lay out in before the bytes arrive, so nothing shifts.
    public var displayAspectRatio: Double { aspectRatio ?? 4.0 / 3.0 }
}
