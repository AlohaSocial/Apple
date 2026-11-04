// SPDX-License-Identifier: MIT

import AVFoundation
import AVKit
import OSLog
import SwiftUI

/// The one place a video is drawn.
///
/// On macOS 27, SwiftUI's `VideoPlayer` aborts inside `_AVKit_SwiftUI` while
/// instantiating its representable's class metadata — the process died the
/// moment Shorts appeared. `AVPlayerView` itself is fine, so the Mac gets that
/// directly. iOS gets `AVPlayerViewController` directly too, because
/// `VideoPlayer` offers no way to allow Picture in Picture; the other
/// platforms keep `VideoPlayer`.
///
/// A surface with controls offers Picture in Picture; one without (a Shorts
/// page, a photo-grid preview) does not, because those videos are the page
/// itself rather than something to keep watching elsewhere.
struct PlayerSurface: View {
    let player: AVPlayer
    var showsControls = true

    var body: some View {
        Group {
            #if os(macOS)
                MacPlayerView(player: player, showsControls: showsControls)
            #elseif os(iOS)
                PhonePlayerView(player: player, showsControls: showsControls)
            #else
                VideoPlayer(player: player)
                    .disabled(!showsControls)
            #endif
        }
        // AVPlayer's mute control is independent from the system audio
        // session. A player with its sound on and playing holds a claim on
        // the speaker until it is muted or this surface goes; silent previews
        // never claim, so they do not interrupt somebody else's music.
        .task(id: ObjectIdentifier(player)) {
            let sessions = AudioSessionCoordinator.shared
            sessions.prepareForSilentPlayback()
            var claim: AudibleClaim?
            for await _ in Self.soundChanges(of: player) {
                if player.isMuted {
                    if let held = claim { sessions.release(held) }
                    claim = nil
                } else if player.timeControlStatus != .paused,
                    claim.map(sessions.holds) != true
                {
                    // Taken again after being preempted only when the person
                    // presses play on this video once more. Holding the
                    // player here is no leak: the claim ends with the
                    // surface, or with its Picture in Picture window.
                    claim = sessions.claim(owner: ObjectIdentifier(player), kind: .video) {
                        player.pause()
                    }
                }
            }
            // The surface is gone. A video floating in Picture in Picture is
            // still playing, so its claim lasts until the window closes.
            if let held = claim {
                PictureInPicture.release(player) { AudioSessionCoordinator.shared.release(held) }
            }
        }
    }

    /// Every change to the player's `isMuted` or `timeControlStatus`, by
    /// key-value observation — what Combine's KVO publisher did, without
    /// Combine (docs/12 §1). The handlers only signal; the surface reads the
    /// player itself on the main actor. The observations end with the stream.
    private static func soundChanges(of player: AVPlayer) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let muted = player.observe(\.isMuted, options: [.initial, .new]) { @Sendable _, _ in
                continuation.yield()
            }
            let status = player.observe(\.timeControlStatus, options: [.new]) {
                @Sendable _, _ in
                continuation.yield()
            }
            continuation.onTermination = { _ in
                muted.invalidate()
                status.invalidate()
            }
        }
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
    static let logger = Logger(subsystem: "social.aloha.app", category: "playback")
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
        // Before anything can play: with nobody audible the session is made
        // mixable, so a muted autoplay never stops the person's music.
        AudioSessionCoordinator.shared.prepareForSilentPlayback()
        let asset = AVURLAsset(
            url: url,
            options: headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        #if os(iOS)
            player.allowsExternalPlayback = true
            // With the screen mirrored to a TV, send the video itself rather
            // than a picture of the phone showing it.
            player.usesExternalPlaybackWhileExternalScreenIsActive = true
        #elseif os(macOS) || os(tvOS)
            player.allowsExternalPlayback = true
        #endif

        // Active playback must not wait for a readiness deadline before it
        // gets a surface and a play request. The caller observes the item
        // and advances to the next source if it fails while loading.
        if deadline <= .zero {
            if item.status == .failed {
                player.replaceCurrentItem(with: nil)
                return .rejected(describe(url: url, error: item.error))
            }
            return .playable(player, item: item, isReady: item.status == .readyToPlay)
        }

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
                // The stream is made on the main actor, where the item's
                // status is read; only its values cross into this task.
                for await status in await PlaybackReadiness.statuses(item) {
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

/// The players currently floating in Picture in Picture.
///
/// The view that started one is usually gone by the time anybody looks at it
/// again — leaving the screen is the point of Picture in Picture — and that
/// view's `onDisappear` is what releases its player. The registry holds the
/// controller and defers the release until the floating window closes, so
/// dismissing the viewer does not end the video it just handed off.
@MainActor
enum PictureInPicture {
    private static var floating: [ObjectIdentifier: AnyObject] = [:]
    /// Several parts may be waiting on the same window: the viewer releasing
    /// its player and the surface giving back its claim on the speaker.
    private static var pendingRelease: [ObjectIdentifier: [() -> Void]] = [:]

    static func isFloating(_ player: AVPlayer) -> Bool {
        floating[ObjectIdentifier(player)] != nil
    }

    static func began(_ player: AVPlayer?, controller: AnyObject) {
        guard let player else { return }
        floating[ObjectIdentifier(player)] = controller
    }

    static func ended(_ player: AVPlayer?) {
        guard let player else { return }
        let key = ObjectIdentifier(player)
        floating[key] = nil
        for release in pendingRelease.removeValue(forKey: key) ?? [] { release() }
    }

    /// Runs `release` now, or when the floating window closes if the player
    /// is in one.
    static func release(_ player: AVPlayer, _ release: @escaping () -> Void) {
        if isFloating(player) {
            pendingRelease[ObjectIdentifier(player), default: []].append(release)
        } else {
            release()
        }
    }
}

/// The system's AirPlay route button, for surfaces whose own controls cover
/// the player's: the viewer's overlay draws over the controls that would
/// otherwise carry it.
struct AirPlayButton: View {
    var body: some View {
        RoutePicker()
            .frame(width: 44, height: 44)
            .accessibilityLabel(Text("AirPlay", comment: "Video action: choose a playback device"))
    }
}

#if os(iOS)
    private struct PhonePlayerView: UIViewControllerRepresentable {
        let player: AVPlayer
        let showsControls: Bool

        func makeCoordinator() -> PictureInPictureDelegate { PictureInPictureDelegate() }

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.player = player
            controller.delegate = context.coordinator
            controller.view.backgroundColor = .clear
            apply(to: controller)
            return controller
        }

        func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
            if controller.player !== player { controller.player = player }
            apply(to: controller)
        }

        private func apply(to controller: AVPlayerViewController) {
            controller.showsPlaybackControls = showsControls
            controller.allowsPictureInPicturePlayback = showsControls
            // Swiping home from a playing video carries on in a floating
            // window, the way the system's own players behave.
            controller.canStartPictureInPictureAutomaticallyFromInline = showsControls
            controller.view.isUserInteractionEnabled = showsControls
        }
    }

    // AVKit calls its delegates on the main thread; the protocol just does not
    // say so.
    @MainActor
    final class PictureInPictureDelegate: NSObject, @preconcurrency AVPlayerViewControllerDelegate {
        func playerViewControllerWillStartPictureInPicture(
            _ controller: AVPlayerViewController
        ) {
            PictureInPicture.began(controller.player, controller: controller)
        }

        func playerViewControllerDidStopPictureInPicture(_ controller: AVPlayerViewController) {
            PictureInPicture.ended(controller.player)
        }

        // The inline player stays where it is while the video floats, so
        // there is nothing to dismiss.
        func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(
            _ controller: AVPlayerViewController
        ) -> Bool {
            false
        }

        /// Back into the screen it came from when that screen is still up;
        /// when it has been closed there is no inline player to return to,
        /// and the floating window simply ends.
        func playerViewController(
            _ controller: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completion:
                @escaping (Bool) -> Void
        ) {
            completion(controller.viewIfLoaded?.window != nil)
        }
    }

    private struct RoutePicker: UIViewRepresentable {
        func makeUIView(context: Context) -> AVRoutePickerView {
            let picker = AVRoutePickerView()
            picker.tintColor = .white
            picker.activeTintColor = .white
            picker.prioritizesVideoDevices = true
            return picker
        }

        func updateUIView(_ picker: AVRoutePickerView, context: Context) {}
    }
#elseif os(macOS)
    private struct RoutePicker: NSViewRepresentable {
        func makeNSView(context: Context) -> AVRoutePickerView {
            let picker = AVRoutePickerView()
            picker.isRoutePickerButtonBordered = false
            return picker
        }

        func updateNSView(_ picker: AVRoutePickerView, context: Context) {}
    }
#else
    private struct RoutePicker: View {
        var body: some View { EmptyView() }
    }
#endif

#if os(macOS)
    private struct MacPlayerView: NSViewRepresentable {
        let player: AVPlayer
        let showsControls: Bool

        func makeCoordinator() -> MacPictureInPictureDelegate { MacPictureInPictureDelegate() }

        func makeNSView(context: Context) -> AVPlayerView {
            let view = AVPlayerView()
            view.player = player
            view.controlsStyle = showsControls ? .inline : .none
            view.videoGravity = showsControls ? .resizeAspect : .resizeAspectFill
            view.showsFullScreenToggleButton = showsControls
            view.allowsPictureInPicturePlayback = showsControls
            view.pictureInPictureDelegate = context.coordinator
            return view
        }

        func updateNSView(_ view: AVPlayerView, context: Context) {
            if view.player !== player { view.player = player }
            view.controlsStyle = showsControls ? .inline : .none
            view.allowsPictureInPicturePlayback = showsControls
        }
    }

    @MainActor
    final class MacPictureInPictureDelegate: NSObject,
        @preconcurrency AVPlayerViewPictureInPictureDelegate
    {
        func playerViewWillStartPicture(inPicture playerView: AVPlayerView) {
            PictureInPicture.began(playerView.player, controller: playerView)
        }

        func playerViewDidStopPicture(inPicture playerView: AVPlayerView) {
            PictureInPicture.ended(playerView.player)
        }

        func playerView(
            _ playerView: AVPlayerView,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:
                @escaping (Bool) -> Void
        ) {
            completionHandler(playerView.window != nil)
        }
    }
#endif
