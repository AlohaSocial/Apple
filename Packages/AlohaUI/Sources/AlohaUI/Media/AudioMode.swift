// SPDX-License-Identifier: MIT

import AVFoundation
import AlohaDesign
import AlohaMedia
import AlohaModels
import MediaPlayer
import Observation
import SwiftUI

/// Background playback with Now Playing metadata and lock-screen controls.
@MainActor
@Observable
public final class AudioPlayerCoordinator {
    public static let shared = AudioPlayerCoordinator()

    public private(set) var nowPlaying: Status?
    /// Whether sound is coming out, read back from the player rather than
    /// kept by hand. A track that ends, a phone call or unplugged headphones
    /// stop the player without asking, and a flag only the buttons flipped
    /// went on saying "playing" — so the next press did the opposite of what
    /// it showed.
    public private(set) var isPlaying = false
    public fileprivate(set) var position: Double = 0
    public fileprivate(set) var duration: Double = 0

    private var player: AVPlayer?
    private var timeObserver: Any?
    @ObservationIgnored private var playbackState: NSKeyValueObservation?
    @ObservationIgnored private var trackEnd: NotificationSubscription?
    @ObservationIgnored private var sessionEvents: [NotificationSubscription] = []
    private var queue: [Status] = []
    /// The account the queue came from; its server is where every track is
    /// fetched, and its token is sent only there.
    private var account: AccountSession?
    @ObservationIgnored private var loading: Task<Void, Never>?
    /// What the person last asked for. An interruption pauses the player but
    /// not this, which is how the end of a phone call knows whether to carry
    /// on.
    private var wantsPlayback = false
    private var resumesAfterInterruption = false
    /// The hold on the speaker, from the first track until playback stops
    /// or a video with its sound on takes over.
    private var sessionClaim: AudibleClaim?
    private let remoteCommands = RemoteCommandRegistration(
        centre: SystemRemoteCommandCentre(),
        handlers: AudioPlayerCoordinator.remoteCommandHandlers())

    private init() {
        #if os(iOS) || os(tvOS) || os(visionOS)
            // The system posts these on a queue of its own; the blocks only
            // read the notification and hop to the main actor with plain
            // values.
            sessionEvents = [
                // iOS 27 splits the old interruption notification in two: the
                // session going inactive, and later a word on whether to carry
                // on. Only a deactivation by the system is an interruption;
                // the app's own (the speaker handed back) is not.
                NotificationSubscription(name: AVAudioSession.didBecomeInactiveNotification) {
                    notification in
                    let context =
                        notification.userInfo?[AVAudioSession.deactivationContextKey]
                        as? AVAudioSession.DeactivationContext
                    guard context?.source == .system else { return }
                    Task { @MainActor in AudioPlayerCoordinator.shared.interruptionBegan() }
                },
                NotificationSubscription(
                    name: AVAudioSession.resumptionRecommendationNotification
                ) { notification in
                    let context =
                        notification.userInfo?[AVAudioSession.resumptionContextKey]
                        as? AVAudioSession.ResumptionContext
                    let shouldResume = context?.recommendation == .shouldResume
                    Task { @MainActor in
                        AudioPlayerCoordinator.shared.interruptionEnded(shouldResume: shouldResume)
                    }
                },
                NotificationSubscription(name: AVAudioSession.routeChangeNotification) {
                    notification in
                    let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                    guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                    else { return }
                    Task { @MainActor in AudioPlayerCoordinator.shared.outputWentAway() }
                },
            ]
        #endif
    }

    public func play(_ status: Status, queue: [Status] = [], session: AccountSession) {
        let target = status.displayed
        guard let attachment = target.mediaAttachments.first(where: { $0.type == .audio })
        else { return }
        let sources = Self.sources(
            for: attachment, statusID: target.id, apiBase: session.capabilities.apiBase)
        guard !sources.isEmpty else { return }

        claimSession()
        loading?.cancel()
        teardownPlayer()

        nowPlaying = target
        self.queue = queue
        account = session
        position = 0
        duration = 0
        wantsPlayback = true
        isPlaying = true
        remoteCommands.register()
        updateNowPlaying()

        loading = Task { await self.open(sources, session: session) }
    }

    /// Where a track is fetched from: the same ladder the video player uses
    /// (docs/06 §3). The attachment's `url` is used only when it is on the
    /// signed-in instance; a federated track that still carries the origin's
    /// address goes through the instance's proxy route instead. Fetching it
    /// from the origin told a server the listener never chose to talk to
    /// their address, and Nextcloud's CSP forbids it anyway.
    static func sources(
        for attachment: MediaAttachment, statusID: String, apiBase: URL
    ) -> [VideoSource] {
        VideoSourceResolver.sources(
            for: attachment, statusID: statusID, apiBase: apiBase,
            isRemote: VideoSourceResolver.isRemote(attachment))
    }

    /// Opens the first rung that plays, falling to the next when one fails
    /// while loading, as the video viewer does. The token goes only to a URL
    /// on the account's own server (`mediaRequestHeaders`).
    private func open(_ sources: [VideoSource], session: AccountSession) async {
        for (rung, source) in sources.enumerated() {
            let headers = await session.client.mediaRequestHeaders(for: source.url)
            guard !Task.isCancelled else { return }
            let attempt = await PlaybackReadiness.open(
                url: source.url, headers: headers, deadline: .zero)
            switch attempt {
            case .rejected(let reason):
                PlaybackLog.logger.error("audio rung \(rung) rejected: \(reason, privacy: .public)")
            case .playable(let player, let item, _):
                guard !Task.isCancelled else {
                    player.replaceCurrentItem(with: nil)
                    return
                }
                self.player = player
                observe(player, item: item)
                if wantsPlayback { player.play() }

                for await status in PlaybackReadiness.statuses(item) {
                    if status == .readyToPlay { return }
                    if status == .failed { break }
                }
                guard !Task.isCancelled else { return }
                let reason = item.error?.localizedDescription ?? "unknown"
                PlaybackLog.logger.error("audio rung \(rung) failed: \(reason, privacy: .public)")
                teardownPlayer()
            }
        }
        guard !Task.isCancelled else { return }
        stop()
    }

    public func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    /// The lock screen sends play and pause as separate commands; mapping
    /// both to a toggle made a Play press on a playing track pause it.
    public func pause() {
        guard nowPlaying != nil else { return }
        wantsPlayback = false
        player?.pause()
        isPlaying = false
        updateNowPlaying()
    }

    public func resume() {
        guard nowPlaying != nil else { return }
        claimSession()
        wantsPlayback = true
        player?.play()
        isPlaying = true
        updateNowPlaying()
    }

    /// Ends playback and takes the app off the lock screen: the remote
    /// command targets go with the player, so a later track does not find
    /// the old handlers still attached.
    public func stop() {
        loading?.cancel()
        loading = nil
        teardownPlayer()
        nowPlaying = nil
        queue = []
        account = nil
        isPlaying = false
        wantsPlayback = false
        resumesAfterInterruption = false
        position = 0
        duration = 0
        remoteCommands.unregister()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        // Last, once nothing is playing: the session is handed back and the
        // music this interrupted carries on.
        if let sessionClaim { AudioSessionCoordinator.shared.release(sessionClaim) }
        sessionClaim = nil
    }

    public func seek(to seconds: Double) {
        guard let player else { return }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        // Now Playing extrapolates from the last elapsed time it was given,
        // so a seek it is not told about leaves the lock screen elsewhere.
        position = seconds
        updateNowPlaying()
    }

    public func next() {
        guard let account, let upcoming = Self.track(after: nowPlaying, in: queue) else { return }
        play(upcoming, queue: queue, session: account)
    }

    /// The next post in the queue with something to play.
    ///
    /// The queue holds the list's rows, boosts included, while `nowPlaying`
    /// is the post a boost carries; the match is on what each row displays,
    /// or a boosted track was the end of the queue.
    static func track(after current: Status?, in queue: [Status]) -> Status? {
        guard let current,
            let index = queue.firstIndex(where: { $0.displayed.id == current.id })
        else { return nil }
        return queue[(index + 1)...].first { candidate in
            candidate.displayed.mediaAttachments.contains { $0.type == .audio }
        }
    }

    /// `.playback`, exclusive and active, is what keeps audio going when the
    /// screen locks; the coordinator sets it and pauses any video playing
    /// with its sound on. Held across pauses, so the lock screen keeps its
    /// controls, and taken again after a video took the speaker away.
    private func claimSession() {
        let sessions = AudioSessionCoordinator.shared
        if let sessionClaim, sessions.holds(sessionClaim) { return }
        sessionClaim = sessions.claim(owner: ObjectIdentifier(self), kind: .audio) {
            AudioPlayerCoordinator.shared.preempted()
        }
    }

    /// A video's sound was turned on: the track pauses where it is, and the
    /// mini-player stays so it can be picked up again.
    private func preempted() {
        sessionClaim = nil
        guard let player else { return }
        wantsPlayback = false
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    /// Follows the player rather than the buttons: its time for the progress
    /// bar, its `timeControlStatus` for whether it is playing, and the end of
    /// its item for what comes next.
    private func observe(_ player: AVPlayer, item: AVPlayerItem) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { time in
            let seconds = time.seconds
            let total = item.duration.seconds
            Task { @MainActor in
                let coordinator = AudioPlayerCoordinator.shared
                coordinator.position = seconds
                let known = total.isFinite ? total : 0
                // Now Playing runs its own clock from the elapsed time and
                // rate; it only needs telling when the duration arrives.
                if known != coordinator.duration {
                    coordinator.duration = known
                    coordinator.updateNowPlaying()
                }
            }
        }

        playbackState = player.observe(\.timeControlStatus, options: [.new]) {
            @Sendable _, _ in
            Task { @MainActor in AudioPlayerCoordinator.shared.playerStateChanged() }
        }

        let finished = ObjectIdentifier(item)
        trackEnd = NotificationSubscription(name: AVPlayerItem.didPlayToEndTimeNotification) {
            notification in
            guard let object = notification.object,
                ObjectIdentifier(object as AnyObject) == finished
            else { return }
            Task { @MainActor in AudioPlayerCoordinator.shared.trackEnded(finished) }
        }
    }

    private func playerStateChanged() {
        guard let player else { return }
        let seconds = player.currentTime().seconds
        if seconds.isFinite { position = seconds }
        isPlaying = player.timeControlStatus != .paused
        updateNowPlaying()
    }

    /// The queue is the visible list (docs/06 §7), so the end of one track is
    /// the start of the next; after the last there is nothing left to show.
    private func trackEnded(_ item: ObjectIdentifier) {
        guard let current = player?.currentItem, ObjectIdentifier(current) == item else { return }
        if let account, let upcoming = Self.track(after: nowPlaying, in: queue) {
            play(upcoming, queue: queue, session: account)
        } else {
            stop()
        }
    }

    /// A phone call or a timer: paused while it lasts, and carried on after
    /// only if the system says so and the person had not paused first.
    private func interruptionBegan() {
        guard let player else { return }
        resumesAfterInterruption = wantsPlayback
        wantsPlayback = false
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    private func interruptionEnded(shouldResume: Bool) {
        let resumes = resumesAfterInterruption && shouldResume
        resumesAfterInterruption = false
        if resumes { resume() }
    }

    /// Headphones pulled out: the player has already paused itself, and it
    /// stays paused after the next interruption too.
    private func outputWentAway() {
        wantsPlayback = false
        resumesAfterInterruption = false
    }

    private func teardownPlayer() {
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        playbackState?.invalidate()
        playbackState = nil
        trackEnd = nil
        player = nil
    }

    /// Remote command handlers are invoked on a background thread, so they
    /// must **hop** to the main actor rather than assume they are already on
    /// it: `assumeIsolated` from another thread traps the process. They are
    /// made in a `nonisolated` function and typed `@Sendable`, so none of
    /// them can be inferred main-actor-isolated (docs/14 §6).
    nonisolated static func remoteCommandHandlers() -> [RemoteCommand: RemoteCommandHandler] {
        [
            .play: {
                Task { @MainActor in AudioPlayerCoordinator.shared.resume() }
                return .success
            },
            .pause: {
                Task { @MainActor in AudioPlayerCoordinator.shared.pause() }
                return .success
            },
            .togglePlayPause: {
                Task { @MainActor in AudioPlayerCoordinator.shared.togglePlayPause() }
                return .success
            },
            .nextTrack: {
                Task { @MainActor in AudioPlayerCoordinator.shared.next() }
                return .success
            },
        ]
    }

    /// Title from the post's first line, artist from the author — the only
    /// honest mapping when the wire carries no track metadata.
    fileprivate func updateNowPlaying() {
        guard let nowPlaying else { return }
        let plain = nowPlaying.content
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: plain.split(separator: "\n").first.map(String.init) ?? plain,
            MPMediaItemPropertyArtist: nowPlaying.account.bestDisplayName,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

/// A lock-screen button the Audio mode answers.
nonisolated enum RemoteCommand: CaseIterable, Sendable {
    case play, pause, togglePlayPause, nextTrack
}

/// What runs when a lock-screen button is pressed. The system calls it on a
/// queue of its own, never the main actor, which is why it is `@Sendable`.
/// None of the Audio mode's buttons needs the event itself.
typealias RemoteCommandHandler = @Sendable () -> MPRemoteCommandHandlerStatus

/// Where handlers are attached: the system's command centre in the app, a
/// recorder in the tests.
protocol RemoteCommandCentre: AnyObject {
    func addTarget(for command: RemoteCommand, handler: @escaping RemoteCommandHandler) -> Any
    func removeTarget(_ target: Any, for command: RemoteCommand)
}

/// `nonisolated`, so the closure handed to `addTarget` is formed outside the
/// main actor and cannot be inferred isolated to it.
nonisolated final class SystemRemoteCommandCentre: RemoteCommandCentre {
    func addTarget(for command: RemoteCommand, handler: @escaping RemoteCommandHandler) -> Any {
        let target: @Sendable (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus = { _ in
            handler()
        }
        return self.command(command).addTarget(handler: target)
    }

    func removeTarget(_ target: Any, for command: RemoteCommand) {
        self.command(command).removeTarget(target)
    }

    private func command(_ command: RemoteCommand) -> MPRemoteCommand {
        let centre = MPRemoteCommandCenter.shared()
        switch command {
        case .play: return centre.playCommand
        case .pause: return centre.pauseCommand
        case .togglePlayPause: return centre.togglePlayPauseCommand
        case .nextTrack: return centre.nextTrackCommand
        }
    }
}

/// The lock-screen handlers, attached once.
///
/// `addTarget` adds; it never replaces. Registering on every `play()` left
/// one more handler behind with each track, so after two tracks a single
/// Pause press toggled twice and nothing appeared to happen. The targets are
/// kept here and taken off again when playback stops.
final class RemoteCommandRegistration {
    private let centre: any RemoteCommandCentre
    private let handlers: [RemoteCommand: RemoteCommandHandler]
    private var targets: [(command: RemoteCommand, target: Any)] = []

    init(centre: any RemoteCommandCentre, handlers: [RemoteCommand: RemoteCommandHandler]) {
        self.centre = centre
        self.handlers = handlers
    }

    var isRegistered: Bool { !targets.isEmpty }

    func register() {
        guard targets.isEmpty else { return }
        for command in RemoteCommand.allCases {
            guard let handler = handlers[command] else { continue }
            targets.append((command, centre.addTarget(for: command, handler: handler)))
        }
    }

    func unregister() {
        for (command, target) in targets {
            centre.removeTarget(target, for: command)
        }
        targets = []
    }
}

public struct AudioModeView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.shellUsesTabBar) private var shellUsesTabBar

    private let session: AccountSession
    private let source: TimelineSource
    private let onAction: (StatusRowAction) -> Void

    @State private var model: TimelineModel
    private var coordinator = AudioPlayerCoordinator.shared

    public init(
        session: AccountSession, source: TimelineSource,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.session = session
        self.source = source
        self.onAction = onAction
        _model = State(
            initialValue: TimelineModel(
                key: TimelineKey(mode: .audio, source: source), session: session))
    }

    private var statuses: [Status] { model.rows.compactMap(\.status) }

    public var body: some View {
        List {
            ForEach(statuses) { status in
                row(status)
                    .onAppear {
                        if status.id == statuses.last?.id {
                            Task { await model.loadOlder() }
                        }
                    }
            }

            if statuses.isEmpty && !model.isRefreshing {
                ContentUnavailableView {
                    Text("No audio yet", comment: "Empty Audio mode")
                } description: {
                    Text(
                        "Posts with audio attachments will show up here.",
                        comment: "Empty Audio detail")
                }
            }
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .bottom) {
            if coordinator.nowPlaying != nil, !usesTabAccessory {
                AudioMiniPlayer()
                    .padding(AlohaMetrics.space3)
                    .background(.regularMaterial)
            }
        }
        .task { await model.appear() }
        .refreshable { await model.refresh() }
    }

    private func row(_ status: Status) -> some View {
        let isCurrent = coordinator.nowPlaying?.id == status.displayed.id

        return HStack(spacing: AlohaMetrics.space3) {
            Button {
                if isCurrent {
                    coordinator.togglePlayPause()
                } else {
                    coordinator.play(status, queue: statuses, session: session)
                }
            } label: {
                Image(
                    systemName: isCurrent && coordinator.isPlaying
                        ? AlohaSymbol.pause : AlohaSymbol.play
                )
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(palette.surfaceRaised, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isCurrent && coordinator.isPlaying
                    ? Text("Pause", comment: "Audio action")
                    : Text("Play", comment: "Audio action"))

            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: status)).font(.subheadline).lineLimit(2)
                Text(status.displayed.account.bestDisplayName)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .alohaRowHighlight()
        .onTapGesture { onAction(.open(status)) }
    }

    /// Under the phone's tab bar the player lives in the bar's accessory,
    /// where it stays across tabs; drawing it here as well would show it
    /// twice. Not on the sidebar shell — an unfolded iPhone Duo included.
    private var usesTabAccessory: Bool {
        #if os(iOS)
            shellUsesTabBar
        #else
            false
        #endif
    }

    private func title(for status: Status) -> String {
        audioTitle(status)
    }
}

private func audioTitle(_ status: Status) -> String {
    let plain = status.displayed.content
        .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return plain.isEmpty
        ? String(localized: "Untitled audio", comment: "Audio with no text") : plain
}

/// What is playing, with play/pause and stop.
///
/// It used to live inside the Audio feed and vanished the moment you
/// changed tab, although the audio kept playing — the only control left was
/// the lock screen. On a phone it now sits in the tab bar's accessory, so it
/// follows you; when the bar is minimised it shrinks to the essentials.
struct AudioMiniPlayer: View {
    @Environment(\.alohaPalette) private var palette
    #if os(iOS)
        @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    #endif

    private var coordinator: AudioPlayerCoordinator { .shared }

    private var isInline: Bool {
        #if os(iOS)
            placement == .inline
        #else
            false
        #endif
    }

    var body: some View {
        HStack(spacing: AlohaMetrics.space3) {
            Button {
                coordinator.togglePlayPause()
            } label: {
                Image(systemName: coordinator.isPlaying ? AlohaSymbol.pause : AlohaSymbol.play)
                    .font(.body)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(minWidth: 32, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                coordinator.isPlaying
                    ? Text("Pause", comment: "Audio action")
                    : Text("Play", comment: "Audio action"))

            VStack(alignment: .leading, spacing: 2) {
                Text(coordinator.nowPlaying.map(audioTitle) ?? "")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.label)
                    .lineLimit(1)
                if !isInline, coordinator.duration > 0 {
                    ProgressView(value: coordinator.position, total: coordinator.duration)
                        .progressViewStyle(.linear)
                        .tint(palette.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isInline {
                Button {
                    coordinator.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .frame(minWidth: 32, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Stop", comment: "Audio action"))
            }
        }
        .padding(.horizontal, AlohaMetrics.space3)
    }
}

public struct NewsModeView: View {
    private let session: AccountSession
    private let source: TimelineSource
    private let onAction: (StatusRowAction) -> Void

    public init(
        session: AccountSession, source: TimelineSource,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.session = session
        self.source = source
        self.onAction = onAction
    }

    public var body: some View {
        // Only ever reached where `only_news` exists — there is no client-side
        // equivalent worth faking, so the mode is hidden otherwise (docs/06 §2).
        TimelineView(
            key: TimelineKey(mode: .news, source: source), session: session, onAction: onAction
        )
        // Long articles want reader typography, whatever the person chose
        // for the conversational modes.
        .environment(\.alohaMetrics, readerMetrics)
    }

    private var readerMetrics: AlohaMetrics {
        AlohaMetrics(
            density: .spacious, lineSpacing: 5, useSerifBody: true,
            avatarShape: .roundedSquare)
    }
}
