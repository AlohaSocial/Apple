// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// Which URL to hand the player, in the order docs/06 §3 prescribes.
///
/// The fallback is mandatory: a 404 on a master playlist means no ladder
/// exists, and the correct response is to play the plain file — not to report a
/// broken video.
public struct VideoSource: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// A local video's transcoding ladder. Adaptive bitrate, so always
        /// preferred where the administrator enabled `video_ladder`.
        case hlsLadder
        /// A federated PeerTube video's playlist, rewritten so every segment is
        /// proxied back through the instance.
        case proxiedPlaylist
        /// The plain file. `/media/{uuid}` honours `Range`, so seeking works.
        case progressive
    }

    public var url: URL
    public var kind: Kind

    public init(url: URL, kind: Kind) {
        self.url = url
        self.kind = kind
    }
}

public enum VideoSourceResolver {

    /// The ordered ladder for one attachment. The caller plays the first and
    /// falls to the next on failure, at the current position.
    public static func sources(
        for attachment: MediaAttachment,
        statusID: String,
        apiBase: URL,
        isRemote: Bool
    ) -> [VideoSource] {
        var sources: [VideoSource] = []

        if let hls = attachment.hlsURL {
            sources.append(VideoSource(url: hls, kind: .hlsLadder))
        }

        // A federated PeerTube video is referenced rather than mirrored, so
        // there is no local copy. **Never point the player at the origin**:
        // Nextcloud's CSP forbids it, and it would announce every viewer to a
        // server they never chose to talk to.
        if isRemote, attachment.hlsURL == nil {
            let proxied = apiBase.appending(path: "media/playlist/\(statusID)")
            sources.append(VideoSource(url: proxied, kind: .proxiedPlaylist))
        }

        if let url = attachment.url {
            sources.append(VideoSource(url: url, kind: .progressive))
        }

        return sources
    }

    /// Whether this attachment came from another instance. `remote_url` being
    /// present is the server saying so.
    public static func isRemote(_ attachment: MediaAttachment) -> Bool {
        attachment.remoteURL != nil
    }
}

/// Playback policy. Autoplay is always on, on every network — what adapts is
/// the bitrate and the preload depth, never the decision (docs/06 §4).
public struct PlaybackPolicy: Sendable, Hashable {
    public var autoplayEnabled: Bool
    public var isLowPowerMode: Bool
    public var isConstrainedNetwork: Bool
    public var isExpensiveNetwork: Bool

    public init(
        autoplayEnabled: Bool = true, isLowPowerMode: Bool = false,
        isConstrainedNetwork: Bool = false, isExpensiveNetwork: Bool = false
    ) {
        self.autoplayEnabled = autoplayEnabled
        self.isLowPowerMode = isLowPowerMode
        self.isConstrainedNetwork = isConstrainedNetwork
        self.isExpensiveNetwork = isExpensiveNetwork
    }

    /// The only thing that stops autoplay is the person's own switch, and a
    /// consent decision about sensitive media — never the network.
    public func shouldAutoplay(isSensitiveAndCovered: Bool) -> Bool {
        autoplayEnabled && !isSensitiveAndCovered
    }

    /// Bounded so "always on" does not become "always downloading".
    public func shortsPreloadCount() -> Int {
        if isLowPowerMode { return 1 }
        if isConstrainedNetwork { return 1 }
        return 3
    }

    /// Set on the player item so a cellular connection plays a smaller rung
    /// rather than nothing at all.
    public var preferredPeakBitRateForExpensiveNetworks: Double {
        isExpensiveNetwork ? 2_000_000 : 0
    }

    public static let maximumLivePlayers = 3
}
