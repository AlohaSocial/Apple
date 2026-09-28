// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaModels

private func makeAccount() -> Account {
    Account(id: "1", username: "alice", acct: "alice@example.test", displayName: "Alice")
}

private func makeAttachment(
    id: String = "m1",
    type: AttachmentKind,
    duration: Double? = nil,
    width: Int? = nil,
    height: Int? = nil
) -> MediaAttachment {
    let hasMeta = duration != nil || width != nil
    return MediaAttachment(
        id: id,
        type: type,
        url: URL(string: "https://example.test/\(id)"),
        meta: hasMeta
            ? .init(original: .init(width: width, height: height, duration: duration))
            : nil
    )
}

private func makeStatus(
    attachments: [MediaAttachment] = [],
    tags: [String] = [],
    card: Card? = nil
) -> Status {
    Status(
        id: "s1",
        account: makeAccount(),
        mediaAttachments: attachments,
        tags: tags.map { Status.StatusTag(name: $0) },
        card: card
    )
}

@Suite("Content classification")
struct ContentClassifierTests {

    @Test("Text with no attachments and no card is text")
    func plainText() {
        #expect(ContentClassifier.classify(makeStatus()) == .text)
    }

    @Test("A status carrying only a link card is news")
    func linkCardIsNews() {
        let card = Card(url: URL(string: "https://example.test/article"), title: "Something")
        #expect(ContentClassifier.classify(makeStatus(card: card)) == .news)
    }

    @Test("Images only is a photo post")
    func imagesArePhotos() {
        let status = makeStatus(attachments: [
            makeAttachment(id: "a", type: .image, width: 1200, height: 800),
            makeAttachment(id: "b", type: .image, width: 1200, height: 800),
        ])
        #expect(ContentClassifier.classify(status) == .photo)
    }

    @Test("Audio only is audio")
    func audioIsAudio() {
        let status = makeStatus(attachments: [makeAttachment(type: .audio, duration: 1800)])
        #expect(ContentClassifier.classify(status) == .audio)
    }

    @Test("A single portrait clip under three minutes is a short")
    func portraitClipIsShort() {
        let status = makeStatus(attachments: [
            makeAttachment(type: .video, duration: 25, width: 1080, height: 1920)
        ])
        #expect(ContentClassifier.classify(status) == .short)
    }

    @Test("Anything at or under sixty seconds is a short regardless of shape")
    func shortDurationWinsOverAspect() {
        let landscape = makeStatus(attachments: [
            makeAttachment(type: .video, duration: 45, width: 1920, height: 1080)
        ])
        #expect(ContentClassifier.classify(landscape) == .short)
    }

    @Test("A landscape clip between one and three minutes is a video, not a short")
    func landscapeMidLengthIsVideo() {
        let status = makeStatus(attachments: [
            makeAttachment(type: .video, duration: 120, width: 1920, height: 1080)
        ])
        #expect(ContentClassifier.classify(status) == .video)
    }

    @Test("A long portrait video is still a video")
    func longPortraitIsVideo() {
        let status = makeStatus(attachments: [
            makeAttachment(type: .video, duration: 2400, width: 1080, height: 1920)
        ])
        #expect(ContentClassifier.classify(status) == .video)
    }

    @Test("A #shorts hashtag promotes a mid-length clip whose shape says otherwise")
    func hashtagPromotesByShape() {
        let status = makeStatus(
            attachments: [makeAttachment(type: .video, width: 1920, height: 1080)],
            tags: ["shorts"]
        )
        #expect(ContentClassifier.classify(status) == .short)
    }

    @Test("A hashtag cannot rescue a clip that is simply too long")
    func hashtagCannotBeatDuration() {
        let status = makeStatus(
            attachments: [makeAttachment(type: .video, duration: 600, width: 1080, height: 1920)],
            tags: ["loops"]
        )
        #expect(ContentClassifier.classify(status) == .video)
    }

    @Test("Missing meta defers the decision rather than guessing")
    func missingMetaDefers() {
        // Nextcloud Social fills meta only for what it probed, so this is a real
        // case and not a hypothetical (docs/06 §4).
        let status = makeStatus(attachments: [makeAttachment(type: .video)])
        #expect(ContentClassifier.classify(status) == .undetermined)
    }

    @Test("Reclassification settles a deferred decision once a player reports")
    func reclassificationSettles() {
        let status = makeStatus(attachments: [makeAttachment(id: "v", type: .video)])
        #expect(ContentClassifier.classify(status) == .undetermined)

        let settled = ContentClassifier.reclassify(
            status, attachmentID: "v", duration: 18, width: 1080, height: 1920)
        #expect(settled == .short)

        let asVideo = ContentClassifier.reclassify(
            status, attachmentID: "v", duration: 900, width: 1920, height: 1080)
        #expect(asVideo == .video)
    }

    @Test("A boost is classified by what it boosts, not by the wrapper")
    func boostsClassifyByTheirPayload() {
        let inner = makeStatus(attachments: [
            makeAttachment(type: .video, duration: 20, width: 1080, height: 1920)
        ])
        let boost = Status(id: "boost", account: makeAccount(), reblog: Box(inner))
        #expect(ContentClassifier.classify(boost) == .short)
    }

    @Test("Mixed video and images is a video post")
    func mixedIsVideo() {
        let status = makeStatus(attachments: [
            makeAttachment(id: "a", type: .image, width: 100, height: 100),
            makeAttachment(id: "b", type: .video, duration: 30, width: 1080, height: 1920),
        ])
        #expect(ContentClassifier.classify(status) == .video)
    }

    @Test("Kinds route into the right modes")
    func modeRouting() {
        #expect(ContentKind.short.belongs(in: .shorts))
        // A short is also a video: Video mode shows both, Shorts shows only shorts.
        #expect(ContentKind.short.belongs(in: .video))
        #expect(ContentKind.video.belongs(in: .shorts) == false)
        #expect(ContentKind.photo.belongs(in: .photos))
        #expect(ContentKind.text.belongs(in: .home))
        #expect(ContentKind.text.belongs(in: .photos) == false)
    }
}

@Suite("Timeline filters and over-fetching")
struct TimelineFilterTests {

    private func capabilities(nextcloud: Bool) -> ServerCapabilities {
        ServerCapabilities(
            apiBase: URL(string: "https://example.test/")!,
            onlyMediaFilter: nextcloud,
            onlyVideoFilter: nextcloud,
            onlyNewsFilter: nextcloud
        )
    }

    @Test("Video mode asks for only_video where the server has it")
    func videoUsesServerNarrowing() {
        let filters = TimelineFilters.forMode(.video, capabilities: capabilities(nextcloud: true))
        #expect(filters.onlyVideo)
        #expect(OverFetch.multiplier(for: .video, serverFilters: filters) == 1)
    }

    @Test("Without server narrowing, Shorts over-fetches hardest")
    func shortsOverFetchWithoutSupport() {
        let filters = TimelineFilters.forMode(.shorts, capabilities: capabilities(nextcloud: false))
        #expect(filters.isEmpty)
        #expect(OverFetch.multiplier(for: .shorts, serverFilters: filters) == 8)
    }

    @Test("News is hidden entirely on a server without only_news")
    func newsHiddenWithoutSupport() {
        #expect(capabilities(nextcloud: false).supports(.news) == false)
        #expect(capabilities(nextcloud: true).supports(.news))
    }

    @Test("Timeline keys keep modes from sharing rows")
    func timelineKeysAreDistinct() {
        let home = TimelineKey(mode: .home, source: .home)
        let photosOfHome = TimelineKey(mode: .photos, source: .home)
        #expect(home.storageKey != photosOfHome.storageKey)
        #expect(photosOfHome.storageKey == "photos:home")
    }
}

@Suite("Sync tier selection")
struct SyncTierTests {

    @Test("An empty vapid key and empty urls mean polling")
    func nextcloudSocialPolls() {
        // Both are deliberate signals: instance.urls is {} and vapid_key is "".
        let capabilities = ServerCapabilities(
            apiBase: URL(string: "https://cloud.example/")!,
            streamingURL: nil,
            webPushVAPIDKey: ""
        )
        #expect(capabilities.syncTier == .polling)
    }

    @Test("A streaming URL upgrades to streaming")
    func streamingUpgrade() {
        let capabilities = ServerCapabilities(
            apiBase: URL(string: "https://mastodon.example/")!,
            streamingURL: URL(string: "wss://mastodon.example/api/v1/streaming")
        )
        #expect(capabilities.syncTier == .streaming)
    }

    @Test("A real vapid key wins over streaming")
    func webPushWins() {
        let capabilities = ServerCapabilities(
            apiBase: URL(string: "https://mastodon.example/")!,
            streamingURL: URL(string: "wss://mastodon.example/api/v1/streaming"),
            webPushVAPIDKey: "BNcT..."
        )
        #expect(capabilities.syncTier == .webPush)
    }
}

@Suite("Character counting")
struct CharacterCountTests {

    private let limits = ServerLimits(
        maxStatusCharacters: 500, maxMediaAttachments: 4, charactersReservedPerURL: 23,
        imageSizeLimit: 0, videoSizeLimit: 0, supportedMIMETypes: [],
        maxPollOptions: 4, maxPollOptionCharacters: 50,
        minPollExpiration: 300, maxPollExpiration: 0, maxFeaturedTags: 10)

    @Test("Plain text counts as itself")
    func plainText() {
        #expect(CharacterCount.count(text: "Hello", spoilerText: "", limits: limits) == 5)
    }

    @Test("A URL costs the flat rate however long it is")
    func urlsAreFlatRate() {
        let short = "See https://a.test"
        let long = "See https://example.test/a/very/long/path?with=query&more=parameters#fragment"

        #expect(
            CharacterCount.count(text: short, spoilerText: "", limits: limits)
                == CharacterCount.count(text: long, spoilerText: "", limits: limits))
        // "See " is 4 characters, plus the 23 a URL costs.
        #expect(CharacterCount.count(text: short, spoilerText: "", limits: limits) == 27)
    }

    /// The bug this replaced: `NSRange.length` is in UTF-16 units while
    /// `String.count` is in grapheme clusters, so any emoji made the counter
    /// wrong — and the counter gates the Post button.
    @Test("Emoji and non-BMP characters count as one each")
    func emojiCountAsOne() {
        #expect(CharacterCount.count(text: "👋", spoilerText: "", limits: limits) == 1)
        #expect(CharacterCount.count(text: "👨‍👩‍👧‍👦", spoilerText: "", limits: limits) == 1)
        // One emoji, a space, and a URL at its flat rate.
        #expect(
            CharacterCount.count(text: "👋 https://example.test/x", spoilerText: "", limits: limits)
                == 25)
    }

    @Test("The content warning shares the body's budget")
    func spoilerSharesBudget() {
        #expect(CharacterCount.count(text: "Hello", spoilerText: "CW", limits: limits) == 7)
        #expect(
            CharacterCount.remaining(text: "Hello", spoilerText: "CW", limits: limits) == 493)
    }

    @Test("Several URLs each cost the flat rate")
    func severalURLs() {
        let text = "https://a.test https://b.test"
        // Two URLs at 23, plus the space between them.
        #expect(CharacterCount.count(text: text, spoilerText: "", limits: limits) == 47)
    }

    @Test("Over-length is reported as a negative remainder")
    func overLength() {
        let text = String(repeating: "a", count: 600)
        #expect(CharacterCount.remaining(text: text, spoilerText: "", limits: limits) == -100)
    }
}
