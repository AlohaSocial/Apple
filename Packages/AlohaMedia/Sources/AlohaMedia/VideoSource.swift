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

        // A direct URL on the chosen instance is already a proxy/cached copy
        // for a federated post. Prefer it: not every Social version exposes
        // the optional `media/playlist` route (it returns 404 on older
        // servers), while this URL is what the status payload explicitly
        // advertises as playable.
        //
        // Only a URL **on this instance** qualifies. A federated attachment
        // that still carries the origin's URL in `url` must never reach the
        // player: Nextcloud's CSP forbids it and it would disclose the viewer
        // to a server they never chose to talk to (docs/06 §3).
        if let url = attachment.url, isVideoResource(url),
            !isRemote || isLocal(url, apiBase: apiBase) {
            sources.append(VideoSource(url: url, kind: .progressive))
        } else if isRemote, attachment.hlsURL == nil {
            // A federated PeerTube video with no local file needs the server
            // proxy. Never point the player at `remote_url`: that would evade
            // the instance CSP and disclose the viewer to the origin host.
            let proxied = apiBase.appending(path: "media/playlist/\(statusID)")
            sources.append(VideoSource(url: proxied, kind: .proxiedPlaylist))
        }

        return sources
    }

    /// Whether this attachment came from another instance. `remote_url` being
    /// present is the server saying so.
    public static func isRemote(_ attachment: MediaAttachment) -> Bool {
        attachment.remoteURL != nil
    }

    /// Social occasionally labels an attachment as `video` while returning a
    /// JPEG poster in `url`. AVFoundation then only reports the vague
    /// "Cannot Open" error. Reject known image resources before the player is
    /// created; `preview_url` remains exclusively for the poster image.
    private static func isVideoResource(_ url: URL) -> Bool {
        let imageExtensions: Set<String> = ["apng", "avif", "gif", "heic", "heif", "jpeg", "jpg", "png", "webp"]
        return !imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// Whether a URL is served by the instance the person signed in to.
    ///
    /// Hosts are compared case-insensitively per RFC 3986, and the port is
    /// ignored: a server that advertises `https://cloud.example/media/…`
    /// while the account is signed in as `https://cloud.example:443/…` (or
    /// the other way round) is still the same instance.
    private static func isLocal(_ url: URL, apiBase: URL) -> Bool {
        guard let urlHost = url.host()?.lowercased(), let baseHost = apiBase.host()?.lowercased()
        else { return false }
        return urlHost == baseHost
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
