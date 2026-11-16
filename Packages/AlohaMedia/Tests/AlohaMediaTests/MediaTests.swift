// SPDX-License-Identifier: MIT

import AlohaModels
import CoreGraphics
import Foundation
import Testing

@testable import AlohaMedia

@Suite("Video source ladder")
struct VideoSourceTests {

    private let base = URL(string: "https://cloud.example/index.php/apps/social/")!

    @Test("An HLS ladder is preferred, with the plain file behind it")
    func ladderPreferred() {
        let attachment = MediaAttachment(
            id: "m", type: .video,
            url: URL(string: "https://cloud.example/media/abc.mp4"),
            hlsURL: URL(string: "https://cloud.example/media/hls/abc/master.m3u8"))

        let sources = VideoSourceResolver.sources(
            for: attachment, statusID: "9", apiBase: base, isRemote: false)

        #expect(sources.map(\.kind) == [.hlsLadder, .progressive])
    }

    @Test("Without a ladder there is just the plain file")
    func noLadder() {
        let attachment = MediaAttachment(
            id: "m", type: .video, url: URL(string: "https://cloud.example/media/abc.mp4"))

        let sources = VideoSourceResolver.sources(
            for: attachment, statusID: "9", apiBase: base, isRemote: false)

        #expect(sources.map(\.kind) == [.progressive])
    }

    /// A direct URL on the chosen instance remains private and works on Social
    /// servers that do not implement the optional playlist proxy route.
    @Test("A federated video prefers its local instance file")
    func remoteVideoPrefersLocalFile() {
        let attachment = MediaAttachment(
            id: "m", type: .video,
            url: URL(string: "https://cloud.example/media/stream/9"),
            remoteURL: URL(string: "https://peertube.elsewhere/videos/xyz.mp4"))

        let sources = VideoSourceResolver.sources(
            for: attachment, statusID: "9", apiBase: base, isRemote: true)

        #expect(sources.map(\.kind) == [.progressive])
        #expect(sources.first?.url.absoluteString == "https://cloud.example/media/stream/9")
        // Nothing in the ladder points at the origin.
        #expect(sources.allSatisfy { $0.url.host() == "cloud.example" })
        // The invariant, stated positively: no source is the origin itself.
        #expect(sources.contains { $0.url.host() == "peertube.elsewhere" } == false)
    }

    /// The privacy invariant from docs/06 §3, restored: a federated attachment
    /// whose `url` still carries the **origin's** address must never reach the
    /// player, however the payload arrived. The proxy route is the only rung.
    @Test("A federated video at the origin is proxied, never played directly")
    func remoteVideoAtOriginUsesProxy() {
        let attachment = MediaAttachment(
            id: "m", type: .video,
            url: URL(string: "https://peertube.elsewhere/videos/xyz.mp4"),
            remoteURL: URL(string: "https://peertube.elsewhere/videos/xyz.mp4"))

        let sources = VideoSourceResolver.sources(
            for: attachment, statusID: "9", apiBase: base, isRemote: true)

        #expect(sources.map(\.kind) == [.proxiedPlaylist])
        #expect(
            sources.first?.url.absoluteString
                == "https://cloud.example/index.php/apps/social/media/playlist/9")
    }

    /// Host comparison must ignore letter case and an explicit default port:
    /// `https://Cloud.Example:443/media/9.mp4` is the instance, not an origin.
    @Test("A local-copy URL matches the instance regardless of case or port")
    func localCopyURLMatchesInstanceHost() {
        let attachment = MediaAttachment(
            id: "m", type: .video,
            url: URL(string: "https://Cloud.Example:443/media/stream/9"),
            remoteURL: URL(string: "https://peertube.elsewhere/videos/xyz.mp4"))

        let sources = VideoSourceResolver.sources(
            for: attachment, statusID: "9", apiBase: base, isRemote: true)

        #expect(sources.map(\.kind) == [.progressive])
        #expect(sources.first?.url.absoluteString == "https://Cloud.Example:443/media/stream/9")
    }

    @Test("A federated video without a local file falls back to the proxy")
    func remoteVideoWithoutLocalFileUsesProxy() {
        let attachment = MediaAttachment(
            id: "m", type: .video,
            remoteURL: URL(string: "https://peertube.elsewhere/videos/xyz.mp4"))

        let sources = VideoSourceResolver.sources(
            for: attachment, statusID: "9", apiBase: base, isRemote: true)

        #expect(sources.map(\.kind) == [.proxiedPlaylist])
        #expect(
            sources.first?.url.absoluteString
                == "https://cloud.example/index.php/apps/social/media/playlist/9")
    }

    @Test("A JPEG poster is never passed to the video player")
    func imageURLIsNotVideoSource() {
        let attachment = MediaAttachment(
            id: "m", type: .video,
            url: URL(string: "https://cloud.example/media/poster.jpeg"))

        let sources = VideoSourceResolver.sources(
            for: attachment, statusID: "9", apiBase: base, isRemote: false)

        #expect(sources.isEmpty)
    }

    @Test("remote_url is what marks an attachment as federated")
    func remoteDetection() {
        let local = MediaAttachment(id: "m", type: .video)
        let remote = MediaAttachment(
            id: "m", type: .video, remoteURL: URL(string: "https://elsewhere.test/v.mp4"))
        #expect(VideoSourceResolver.isRemote(local) == false)
        #expect(VideoSourceResolver.isRemote(remote))
    }
}

@Suite("Playback policy")
struct PlaybackPolicyTests {

    @Test("No network condition stops autoplay")
    func networkNeverStopsAutoplay() {
        let cellular = PlaybackPolicy(isConstrainedNetwork: true, isExpensiveNetwork: true)
        #expect(cellular.shouldAutoplay(isSensitiveAndCovered: false))

        let lowPower = PlaybackPolicy(isLowPowerMode: true)
        #expect(lowPower.shouldAutoplay(isSensitiveAndCovered: false))
    }

    @Test("The person's own switch stops it")
    func switchStopsAutoplay() {
        #expect(
            PlaybackPolicy(autoplayEnabled: false).shouldAutoplay(isSensitiveAndCovered: false)
                == false)
    }

    @Test("Covered sensitive media is still not autoplayed")
    func sensitiveMediaStaysCovered() {
        // A consent decision, not a network one, and it stands.
        #expect(PlaybackPolicy().shouldAutoplay(isSensitiveAndCovered: true) == false)
    }

    @Test("Low Power and Low Data trim the preload, not the playback")
    func preloadAdapts() {
        #expect(PlaybackPolicy().shortsPreloadCount() == 3)
        #expect(PlaybackPolicy(isLowPowerMode: true).shortsPreloadCount() == 1)
        #expect(PlaybackPolicy(isConstrainedNetwork: true).shortsPreloadCount() == 1)
    }

    @Test("An expensive network caps the peak bitrate instead of refusing")
    func bitrateAdapts() {
        #expect(
            PlaybackPolicy(isExpensiveNetwork: true).preferredPeakBitRateForExpensiveNetworks > 0)
        #expect(
            PlaybackPolicy(isExpensiveNetwork: false).preferredPeakBitRateForExpensiveNetworks == 0)
    }
}

@Suite("BlurHash")
struct BlurHashTests {

    @Test("A valid hash decodes to an image of the requested size")
    func decodesValidHash() throws {
        let image = try #require(
            BlurHash.decode("LEHV6nWB2yk8pyo0adR*.7kCMdnj", size: CGSize(width: 32, height: 32)))
        #expect(image.width == 32)
        #expect(image.height == 32)
    }

    @Test("Malformed hashes return nil rather than crashing")
    func rejectsMalformedHashes() {
        let size = CGSize(width: 16, height: 16)
        #expect(BlurHash.decode("", size: size) == nil)
        #expect(BlurHash.decode("abc", size: size) == nil)
        #expect(BlurHash.decode("!!!!!!!!!!!!", size: size) == nil)
        #expect(BlurHash.decode("LEHV6nWB2yk8pyo0adR*.7kCMdnj", size: .zero) == nil)
    }
}

@Suite("Upload pre-flight")
struct UploadPreflightTests {

    private let nextcloud = ServerLimits(
        maxStatusCharacters: 5000, maxMediaAttachments: 4, charactersReservedPerURL: 23,
        imageSizeLimit: 10 * 1024 * 1024, videoSizeLimit: 2048 * 1024 * 1024,
        supportedMIMETypes: ["image/jpeg", "image/png", "video/mp4"],
        maxPollOptions: 4, maxPollOptionCharacters: 50,
        minPollExpiration: 300, maxPollExpiration: 2_629_746, maxFeaturedTags: 10)

    @Test("Images and video get different ceilings")
    func twoCeilings() {
        // The server reads an image whole into memory and copies a video a
        // chunk at a time, which is why the two differ so widely.
        let bigImage = UploadPreflight.check(
            fileSize: 20 * 1024 * 1024, mimeType: "image/jpeg", limits: nextcloud)
        let sameSizedVideo = UploadPreflight.check(
            fileSize: 20 * 1024 * 1024, mimeType: "video/mp4", limits: nextcloud)

        guard case .tooLarge(_, let limit, let isVideo) = bigImage else {
            Issue.record("expected the image to be refused")
            return
        }
        #expect(limit == 10 * 1024 * 1024)
        #expect(isVideo == false)

        guard case .ready = sameSizedVideo else {
            Issue.record("expected the video to be accepted")
            return
        }
    }

    @Test("HEIC on a server without HEIC is transcoded rather than refused")
    func heicTranscodes() {
        guard
            case .needsTranscode(_, let target) = UploadPreflight.check(
                fileSize: 2 * 1024 * 1024, mimeType: "image/heic", limits: nextcloud)
        else {
            Issue.record("expected a transcode")
            return
        }
        // The explicit last resort: this server takes neither HEIC nor HEIF.
        #expect(target == "image/jpeg")
    }

    @Test("HEIC on a server that lists it goes up as it is")
    func heicIsReady() {
        var limits = nextcloud
        limits.supportedMIMETypes.append(contentsOf: ["image/heic", "image/heif"])
        #expect(
            UploadPreflight.check(fileSize: 1024, mimeType: "image/heic", limits: limits)
                == .ready(mimeType: "image/heic"))
    }

    @Test("A type the server takes and no transcode can reach is refused")
    func unsupportedType() {
        guard
            case .unsupported = UploadPreflight.check(
                fileSize: 1024, mimeType: "application/zip", limits: nextcloud)
        else {
            Issue.record("expected unsupported")
            return
        }
    }

    @Test("The explanation names the ceiling, because a bare refusal is not actionable")
    func explanationNamesTheCeiling() throws {
        let verdict = UploadPreflight.check(
            fileSize: 20 * 1024 * 1024, mimeType: "image/jpeg", limits: nextcloud)
        let message = try #require(UploadPreflight.explanation(for: verdict))
        #expect(message.contains("MB"))
        #expect(UploadPreflight.explanation(for: .ready(mimeType: "image/jpeg")) == nil)
    }
}

/// The rule since servers keep HEIC: send the original, convert to HEIC
/// where the server will not take the original, and fall back to JPEG only
/// where it takes neither (docs/07 §4).
@Suite("Picture upload formats")
struct ImageUploadFormatTests {

    private func limits(_ types: [String], imageLimit: Int = 10 * 1024 * 1024) -> ServerLimits {
        ServerLimits(
            maxStatusCharacters: 500, maxMediaAttachments: 4, charactersReservedPerURL: 23,
            imageSizeLimit: imageLimit, videoSizeLimit: 40 * 1024 * 1024,
            supportedMIMETypes: types, maxPollOptions: 4, maxPollOptionCharacters: 50,
            minPollExpiration: 300, maxPollExpiration: 2_629_746, maxFeaturedTags: 10)
    }

    private let modern = ["image/jpeg", "image/png", "image/heic", "image/heif"]
    private let jpegOnly = ["image/jpeg", "image/png"]
    private let everyEncoder: (ImageFormat) -> Bool = { _ in true }

    private func plan(
        _ mimeType: String, size: Int = 1024, spatial: Bool = false, on types: [String],
        imageLimit: Int = 10 * 1024 * 1024, writable: ((ImageFormat) -> Bool)? = nil
    ) -> UploadPreflight.ImagePlan {
        UploadPreflight.imagePlan(
            fileSize: size, mimeType: mimeType, isSpatial: spatial,
            limits: limits(types, imageLimit: imageLimit), writable: writable ?? everyEncoder)
    }

    @Test("A type the server takes goes up as it is, HEIC and spatial photos included")
    func originals() {
        #expect(plan("image/heic", on: modern) == .original)
        #expect(plan("image/heif", on: modern) == .original)
        #expect(plan("image/heic", spatial: true, on: modern) == .original)
        #expect(plan("image/jpeg", on: jpegOnly) == .original)
    }

    @Test("A type the server does not take becomes HEIC where the server takes HEIC")
    func convertsToHEIC() {
        #expect(plan("image/tiff", on: modern) == .convert(to: .heic))
        #expect(plan("image/x-adobe-dng", on: modern) == .convert(to: .heic))
        #expect(plan("image/heif", on: ["image/jpeg", "image/heic"]) == .convert(to: .heic))
    }

    @Test("JPEG only for a server that takes neither the type nor HEIC")
    func jpegFallback() {
        #expect(plan("image/heic", on: jpegOnly) == .convert(to: .jpeg))
        #expect(plan("image/tiff", on: jpegOnly) == .convert(to: .jpeg))
        // A device that cannot write HEIC falls back too, rather than failing.
        #expect(
            plan("image/tiff", on: modern, writable: { $0 == .jpeg }) == .convert(to: .jpeg))
    }

    @Test("Nothing to convert to is a refusal, not a guess")
    func nothingToConvertTo() {
        #expect(
            plan("image/heic", on: ["image/png"])
                == .refuse(.unsupported(mimeType: "image/heic")))
        // An animated type is not flattened to its first frame.
        #expect(
            plan("image/gif", on: modern) == .refuse(.unsupported(mimeType: "image/gif")))
    }

    @Test("A picture over the limit is shrunk as HEIC, or JPEG without HEIC")
    func shrinks() {
        let big = 12 * 1024 * 1024
        #expect(plan("image/jpeg", size: big, on: modern) == .shrink(to: .heic))
        #expect(plan("image/heic", size: big, on: modern) == .shrink(to: .heic))
        #expect(plan("image/jpeg", size: big, on: jpegOnly) == .shrink(to: .jpeg))
    }

    @Test("A spatial photo over the limit is refused, never shrunk")
    func spatialTooLarge() {
        let big = 12 * 1024 * 1024
        #expect(
            plan("image/heic", size: big, spatial: true, on: modern)
                == .spatialTooLarge(size: big, limit: 10 * 1024 * 1024))
        let message = UploadPreflight.spatialTooLargeExplanation(limit: 10 * 1024 * 1024)
        #expect(message.contains("MB"))
    }

    @Test("A spatial photo on a server without HEIC goes up as an ordinary picture")
    func spatialWithoutHEIC() {
        #expect(plan("image/heic", spatial: true, on: jpegOnly) == .convert(to: .jpeg))
    }

    @Test("QuickTime still goes to MP4, and only where the server takes MP4")
    func videos() {
        #expect(
            UploadPreflight.check(
                fileSize: 1024, mimeType: "video/quicktime",
                limits: limits(["video/mp4"]))
                == .needsTranscode(
                    from: "video/quicktime", to: "video/mp4"))
        #expect(
            UploadPreflight.check(
                fileSize: 1024, mimeType: "video/quicktime", limits: limits(["video/webm"]))
                == .unsupported(mimeType: "video/quicktime"))
    }

    @Test("The format a MIME type names")
    func formats() {
        #expect(ImageFormat(mimeType: "image/HEIC") == .heic)
        #expect(ImageFormat(mimeType: "image/heif") == .heic)
        #expect(ImageFormat(mimeType: "image/jpeg") == .jpeg)
        #expect(ImageFormat(mimeType: "image/png") == nil)
        #expect(ImageFormat.target(accepting: { _ in true }, writable: { _ in true }) == .heic)
    }
}

@Suite("Upload progress")
@MainActor
struct UploadProgressTests {

    @Test("Overall progress is the mean of the parts")
    func overallProgress() {
        let progress = UploadProgress()
        let first = progress.begin("a.jpg")
        let second = progress.begin("b.mp4")

        progress.update(first, fraction: 1)
        progress.update(second, fraction: 0.5)
        #expect(abs(progress.overallFraction - 0.75) < 0.001)
        #expect(progress.isFinished == false)

        progress.finish(first)
        progress.finish(second)
        #expect(progress.isFinished)
    }
}
