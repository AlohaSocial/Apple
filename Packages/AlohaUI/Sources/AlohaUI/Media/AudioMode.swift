// SPDX-License-Identifier: MIT

import AVFoundation
import AlohaDesign
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
    public private(set) var isPlaying = false
    public fileprivate(set) var position: Double = 0
    public fileprivate(set) var duration: Double = 0

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var queue: [Status] = []
    private let remoteCommands = RemoteCommandRegistration(
        centre: SystemRemoteCommandCentre(),
        handlers: AudioPlayerCoordinator.remoteCommandHandlers())

    private init() {}

    public func play(_ status: Status, queue: [Status] = []) {
        let target = status.displayed
        guard let attachment = target.mediaAttachments.first(where: { $0.type == .audio }),
            let url = attachment.url
        else { return }

        configureSession()
        teardownObserver()

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        self.nowPlaying = target
        self.queue = queue

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { time in
            let seconds = time.seconds
            let total = item.duration.seconds
            Task { @MainActor in
                let coordinator = AudioPlayerCoordinator.shared
                coordinator.position = seconds
                coordinator.duration = total.isFinite ? total : 0
                coordinator.updateNowPlaying()
            }
        }

        player.play()
        isPlaying = true
        remoteCommands.register()
        updateNowPlaying()
    }

    public func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    /// The lock screen sends play and pause as separate commands; mapping
    /// both to a toggle made a Play press on a playing track pause it.
    public func pause() {
        guard let player, isPlaying else { return }
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    public func resume() {
        guard let player, !isPlaying else { return }
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    /// Ends playback and takes the app off the lock screen: the remote
    /// command targets go with the player, so a later track does not find
    /// the old handlers still attached.
    public func stop() {
        player?.pause()
        teardownObserver()
        player = nil
        nowPlaying = nil
        isPlaying = false
        remoteCommands.unregister()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    public func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    public func next() {
        guard let current = nowPlaying,
            let index = queue.firstIndex(where: { $0.id == current.id }),
            queue.indices.contains(index + 1)
        else { return }
        play(queue[index + 1], queue: queue)
    }

    private func configureSession() {
        #if os(iOS) || os(tvOS) || os(visionOS)
            // `.playback` is what keeps audio going when the screen locks.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    private func teardownObserver() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
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
                    coordinator.play(status, queue: statuses)
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
