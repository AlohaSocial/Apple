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
        registerRemoteCommands()
        updateNowPlaying()
    }

    public func togglePlayPause() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
        updateNowPlaying()
    }

    public func stop() {
        player?.pause()
        teardownObserver()
        player = nil
        nowPlaying = nil
        isPlaying = false
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
    /// it: `assumeIsolated` from another thread traps the process.
    private func registerRemoteCommands() {
        let centre = MPRemoteCommandCenter.shared()

        centre.playCommand.addTarget { _ in
            Task { @MainActor in AudioPlayerCoordinator.shared.togglePlayPause() }
            return .success
        }
        centre.pauseCommand.addTarget { _ in
            Task { @MainActor in AudioPlayerCoordinator.shared.togglePlayPause() }
            return .success
        }
        centre.nextTrackCommand.addTarget { _ in
            Task { @MainActor in AudioPlayerCoordinator.shared.next() }
            return .success
        }
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

public struct AudioModeView: View {
    @Environment(\.alohaPalette) private var palette

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
            if coordinator.nowPlaying != nil { miniPlayer }
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
        .onTapGesture { onAction(.open(status)) }
    }

    private var miniPlayer: some View {
        HStack(spacing: AlohaMetrics.space3) {
            Button {
                coordinator.togglePlayPause()
            } label: {
                Image(systemName: coordinator.isPlaying ? AlohaSymbol.pause : AlohaSymbol.play)
                    .font(.body)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(coordinator.nowPlaying.map(title) ?? "")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if coordinator.duration > 0 {
                    ProgressView(value: coordinator.position, total: coordinator.duration)
                        .progressViewStyle(.linear)
                }
            }

            Button {
                coordinator.stop()
            } label: {
                Image(systemName: "xmark").font(.caption)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Stop", comment: "Audio action"))
        }
        .padding(AlohaMetrics.space3)
        .background(.regularMaterial)
    }

    private func title(for status: Status) -> String {
        let plain = status.displayed.content
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return plain.isEmpty
            ? String(localized: "Untitled audio", comment: "Audio with no text") : plain
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
