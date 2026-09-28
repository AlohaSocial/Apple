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

    /// The player must never contact the origin host: the CSP forbids it, and
    /// it would announce every viewer to a server they never chose.
    @Test("A federated video is proxied, never played from its origin")
    func remoteVideoIsProxied() {
        let attachment = MediaAttachment(
            id: "m", type: .video,
            url: URL(string: "https://cloud.example/media/stream/9"),
            remoteURL: URL(string: "https://peertube.elsewhere/videos/xyz.mp4"))

        let sources = VideoSourceResolver.sources(
            for: attachment, statusID: "9", apiBase: base, isRemote: true)

        #expect(sources.first?.kind == .proxiedPlaylist)
        #expect(
            sources.first?.url.absoluteString
                == "https://cloud.example/index.php/apps/social/media/playlist/9")
        // Nothing in the ladder points at the origin.
        #expect(sources.allSatisfy { $0.url.host() == "cloud.example" })
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

    @Test("HEIC is transcoded rather than refused")
    func heicTranscodes() {
        guard
            case .needsTranscode(_, let target) = UploadPreflight.check(
                fileSize: 2 * 1024 * 1024, mimeType: "image/heic", limits: nextcloud)
        else {
            Issue.record("expected a transcode")
            return
        }
        #expect(target == "image/jpeg")
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

@Suite("Upload progress")
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
