// SPDX-License-Identifier: MIT

import AVFoundation
import AVKit
import Combine
import SwiftUI
import OSLog

/// The one place a video is drawn.
///
/// On macOS 27, SwiftUI's `VideoPlayer` aborts inside `_AVKit_SwiftUI` while
/// instantiating its representable's class metadata — the process died the
/// moment Shorts appeared. `AVPlayerView` itself is fine, so the Mac gets that
/// directly; everything else keeps `VideoPlayer`.
struct PlayerSurface: View {
    let player: AVPlayer
    var showsControls = true

    var body: some View {
        Group {
        #if os(macOS)
            MacPlayerView(player: player, showsControls: showsControls)
        #else
            VideoPlayer(player: player)
                .disabled(!showsControls)
        #endif
        }
        // AVPlayer's mute control is independent from the system audio
        // session. Activate audible playback only when sound is requested;
        // silent previews must not interrupt somebody else's music.
        .onReceive(player.publisher(for: \.isMuted).removeDuplicates().receive(on: DispatchQueue.main)) { muted in
            if !muted { PlaybackAudioSession.activate() }
        }
    }
}

@MainActor
enum PlaybackAudioSession {
    static func activate() {
        #if os(iOS) || os(tvOS) || os(visionOS)
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .moviePlayback)
                try session.setActive(true)
            } catch {
                PlaybackLog.logger.error("Audio session activation failed: \(error.localizedDescription, privacy: .public)")
            }
        #endif
    }
}

/// What AVFoundation decided about one attempt at a source.
enum PlaybackOutcome: Sendable {
    case ready
    case failed
    /// Still saying nothing when the deadline passed. Not a failure.
    case pending
}

/// One place that says what a video did, so a poster that never gives way to
/// picture can be read about in Console rather than guessed at.
enum PlaybackLog {
    static let logger = Logger(subsystem: "com.nextcloud.alohasocial", category: "playback")
}

/// One attempt at one source, judged.
enum PlaybackAttempt {
    /// The player is up. `isReady` says whether there is a picture to show
    /// yet; until there is, the caller's poster stays over the surface.
    case playable(AVPlayer, item: AVPlayerItem, isReady: Bool)
    /// This rung is not one. `reason` says why, in a form a person can read
    /// off a poster that never gave way to picture.
    case rejected(String)
}

/// Opens a source, and reports honestly on how far it got.
///
/// The player is built before anything is awaited: `AVPlayerItem.status` does
/// not advance until something holds the item, so waiting on it first waits
/// for a change that can never arrive — which is how a poster that never gave
/// way to picture was arrived at. The caller gets the player as soon as it
/// exists and keeps its poster over the top until there is a frame behind it,
/// so a file that is still arriving looks like loading rather than like black.
enum PlaybackReadiness {
    /// How long a rung gets to answer before the app admits it is still
    /// loading rather than instant. A 404 replies in milliseconds; a large
    /// file whose index sits at its far end may need much longer than any
    /// deadline, so this is not a failure point — only the moment at which
    /// the poster stops pretending.
    static let verdictDeadline = Duration.seconds(5)

    /// The poll interval. Far below anything a person can see, and cheap
    /// enough that a rung sitting on the deadline costs nothing.
    static let pollInterval = Duration.milliseconds(40)

    static func open(
        url: URL, headers: [String: String],
        deadline: Duration = PlaybackReadiness.verdictDeadline
    ) async -> PlaybackAttempt {
        let asset = AVURLAsset(
            url: url,
            options: headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)

        switch await verdict(of: item, deadline: deadline) {
        case .ready:
            return .playable(player, item: item, isReady: true)
        case .failed:
            player.replaceCurrentItem(with: nil)
            return .rejected(describe(url: url, error: item.error))
        case .pending:
            // Not wrong, not settled — a file still on its way. Hand the
            // player over anyway and let the poster cover it; refusing here
            // would fail every video large enough to be worth watching.
            return .playable(player, item: item, isReady: false)
        }
    }

    /// Every status the item takes from now on, starting with the one it has
    /// right now.
    ///
    /// Deliberately polled rather than observed. A KVO subscription reports
    /// only changes that happen *after* it exists, and the gap between reading
    /// a status and installing the subscription is measured in milliseconds —
    /// which is exactly how long a small file on a fast server takes to go
    /// from `unknown` to `readyToPlay`. Every video was losing the answer in
    /// that gap and then waiting out a full deadline to be handed over
    /// anyway. A read has no gap to fall through.
    static func statuses(
        _ item: AVPlayerItem, every interval: Duration = PlaybackReadiness.pollInterval
    ) -> AsyncStream<AVPlayerItem.Status> {
        AsyncStream { continuation in
            let task = Task {
                var last = item.status
                continuation.yield(last)
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    if Task.isCancelled { break }
                    let current = item.status
                    if current != last {
                        last = current
                        continuation.yield(current)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// What the item decided inside the deadline; `.pending` when it is still
    /// saying nothing, which is a verdict about time rather than about the
    /// file.
    static func verdict(
        of item: AVPlayerItem, deadline: Duration = PlaybackReadiness.verdictDeadline
    ) async -> PlaybackOutcome {
        await withTaskGroup(of: PlaybackOutcome.self) { group in
            group.addTask {
                for await status in PlaybackReadiness.statuses(item) {
                    switch status {
                    case .readyToPlay: return .ready
                    case .failed: return .failed
                    default: break
                    }
                }
                return .failed
            }
            group.addTask {
                try? await Task.sleep(for: deadline)
                return .pending
            }
            let outcome = await group.next() ?? .pending
            group.cancelAll()
            return outcome
        }
    }

    /// Shown when no rung opens: the host first, because "this video could
    /// not be played" alone never told anybody whether the file, the network
    /// or the account was at fault.
    static func describe(url: URL, error: (any Error)?) -> String {
        let host = url.host() ?? url.absoluteString
        guard let error else { return "\(host) — not playable" }
        return "\(host) — \(error.localizedDescription)"
    }
}


#if os(macOS)
    private struct MacPlayerView: NSViewRepresentable {
        let player: AVPlayer
        let showsControls: Bool

        func makeNSView(context: Context) -> AVPlayerView {
            let view = AVPlayerView()
            view.player = player
            view.controlsStyle = showsControls ? .inline : .none
            view.videoGravity = showsControls ? .resizeAspect : .resizeAspectFill
            view.showsFullScreenToggleButton = showsControls
            return view
        }

        func updateNSView(_ view: AVPlayerView, context: Context) {
            if view.player !== player { view.player = player }
            view.controlsStyle = showsControls ? .inline : .none
        }
    }
#endif
