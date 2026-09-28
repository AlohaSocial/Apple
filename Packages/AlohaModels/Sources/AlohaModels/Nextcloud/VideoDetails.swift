// SPDX-License-Identifier: MIT

import Foundation

/// What Nextcloud Social knows about a video beyond the attachment: the
/// PeerTube-shaped facts it carries on a status as `video`, plus the dislike
/// state PeerTube readers expect. Local and federated videos alike.
public struct VideoDetails: Codable, Sendable, Hashable {
    @LenientInt public var views: Int
    @LenientInt public var likes: Int
    @LenientInt public var dislikes: Int
    public var category: String?
    public var language: String?
    public var licence: String?
    @LenientBool public var live: Bool
    /// The author's "support me" text, when they wrote one.
    public var support: String?
    /// Whether the author allows downloading. `nil` when the server did not say.
    public var download: Bool?
    public var chapters: [VideoChapter]

    enum CodingKeys: String, CodingKey {
        case views, likes, dislikes, category, language, licence, live, support, download, chapters
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _views = (try? c.decode(LenientInt.self, forKey: .views)) ?? LenientInt(wrappedValue: 0)
        _likes = (try? c.decode(LenientInt.self, forKey: .likes)) ?? LenientInt(wrappedValue: 0)
        _dislikes =
            (try? c.decode(LenientInt.self, forKey: .dislikes)) ?? LenientInt(wrappedValue: 0)
        category = Self.text(c, .category)
        language = Self.text(c, .language)
        licence = Self.text(c, .licence)
        _live = (try? c.decode(LenientBool.self, forKey: .live)) ?? LenientBool(wrappedValue: false)
        support = Self.text(c, .support)
        download = (try? c.decode(LenientBool.self, forKey: .download))?.wrappedValue
        chapters = (try? c.decode(LossyArray<VideoChapter>.self, forKey: .chapters))?.elements ?? []
    }

    /// PeerTube sends `{id, label}` for category, language and licence; the
    /// server may pass either shape on. Both read as the label.
    private static func text(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String?
    {
        if let string = try? c.decode(String.self, forKey: key) {
            return string.isEmpty ? nil : string
        }
        if let labelled = try? c.decode(Labelled.self, forKey: key) { return labelled.label }
        return nil
    }

    private struct Labelled: Decodable {
        var label: String?
    }

    public init(
        views: Int = 0, likes: Int = 0, dislikes: Int = 0, category: String? = nil,
        language: String? = nil, licence: String? = nil, live: Bool = false,
        support: String? = nil, download: Bool? = nil, chapters: [VideoChapter] = []
    ) {
        _views = LenientInt(wrappedValue: views)
        _likes = LenientInt(wrappedValue: likes)
        _dislikes = LenientInt(wrappedValue: dislikes)
        self.category = category
        self.language = language
        self.licence = licence
        _live = LenientBool(wrappedValue: live)
        self.support = support
        self.download = download
        self.chapters = chapters
    }
}

/// One entry of a video's chapter list: where it starts, and what it is.
public struct VideoChapter: Codable, Sendable, Hashable, Identifiable {
    /// Seconds from the start.
    public var start: Double
    public var title: String

    public var id: Double { start }

    enum CodingKeys: String, CodingKey {
        case start, title
    }

    public init(start: Double, title: String) {
        self.start = start
        self.title = title
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let double = try? c.decode(Double.self, forKey: .start) {
            start = double
        } else if let string = try? c.decode(String.self, forKey: .start),
            let parsed = VideoChapters.seconds(from: string)
        {
            start = parsed
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .start, in: c,
                debugDescription: "chapter start was neither seconds nor a clock")
        }
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
    }
}

/// The keys a status carries beyond Mastodon's when it is a video. Decoded
/// from the same bytes as the `Status`, so nothing is fetched twice.
public struct VideoStatusExtras: Decodable, Sendable, Hashable {
    public var video: VideoDetails?
    public var dislikesCount: Int?
    public var disliked: Bool?

    enum CodingKeys: String, CodingKey {
        case video
        case dislikesCount = "dislikes_count"
        case disliked
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        video = try? c.decodeIfPresent(VideoDetails.self, forKey: .video)
        dislikesCount =
            (try? c.decodeIfPresent(LenientInt.self, forKey: .dislikesCount))?.wrappedValue
        disliked = (try? c.decodeIfPresent(LenientBool.self, forKey: .disliked))?.wrappedValue
    }

    public init(video: VideoDetails? = nil, dislikesCount: Int? = nil, disliked: Bool? = nil) {
        self.video = video
        self.dislikesCount = dislikesCount
        self.disliked = disliked
    }
}

/// Chapters written into a description, the way people write them: a clock
/// at the start of a line, then the title.
///
/// ```
/// 0:00 Intro
/// 1:02 The first thing
/// 01:02:03 - Much later
/// ```
public enum VideoChapters {
    /// The chapters in a plain-text description, in order of appearance,
    /// or an empty list when there are fewer than two — one timestamp is a
    /// reference, not a table of contents.
    public static func parse(from plainText: String) -> [VideoChapter] {
        var found: [VideoChapter] = []
        for rawLine in plainText.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
        {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let space = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            let stamp = String(line[..<space])
            guard let start = seconds(from: stamp) else { continue }
            var title = line[space...].trimmingCharacters(in: .whitespaces)
            // "1:02 - Title", "1:02 – Title", "1:02: Title" all mean the same.
            while let first = title.first, ["-", "–", "—", ":", "•"].contains(first) {
                title = String(title.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            guard !title.isEmpty else { continue }
            found.append(VideoChapter(start: start, title: title))
        }
        // Chapters run forward; a stray timestamp out of order is a mention.
        var ordered: [VideoChapter] = []
        for chapter in found where chapter.start >= (ordered.last?.start ?? -1) {
            if chapter.start == ordered.last?.start { continue }
            ordered.append(chapter)
        }
        return ordered.count >= 2 ? ordered : []
    }

    /// `m:ss`, `mm:ss` or `h:mm:ss` to seconds. Anything else is `nil`.
    public static func seconds(from clock: String) -> Double? {
        let parts = clock.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return nil }
        var values: [Int] = []
        for (index, part) in parts.enumerated() {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let value = Int(part) else {
                return nil
            }
            // Only the leading unit may exceed 59.
            if index > 0, value > 59 { return nil }
            values.append(value)
        }
        if values.count == 2 { return Double(values[0] * 60 + values[1]) }
        return Double(values[0] * 3600 + values[1] * 60 + values[2])
    }

    /// Seconds as a clock, the way a chapter list writes it: `1:02`,
    /// `1:02:03`.
    public static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }
}
