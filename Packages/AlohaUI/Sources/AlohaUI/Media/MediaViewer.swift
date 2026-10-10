// SPDX-License-Identifier: MIT

import AVKit
import AlohaDesign
import AlohaMedia
import AlohaModels
import AlohaNetwork
import Combine
import OSLog
import SwiftUI

/// One component, used from every mode and from the thread view. It knows
/// nothing about which mode opened it (docs/06 §8).
public struct MediaViewer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alohaPalette) private var palette
    @Environment(\.alohaMetrics) private var metrics
    @Environment(\.mediaTransition) private var mediaTransition

    private let attachments: [MediaAttachment]
    private let statusID: String
    private let apiBase: URL
    private let autoplay: Bool
    private let session: AccountSession?

    @State private var index: Int
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var isShowingAltText = false
    @State private var isDragging = false

    public init(
        attachments: [MediaAttachment], startIndex: Int, statusID: String,
        apiBase: URL, autoplay: Bool, session: AccountSession? = nil
    ) {
        self.attachments = attachments
        self.statusID = statusID
        self.apiBase = apiBase
        self.autoplay = autoplay
        self.session = session
        _index = State(initialValue: startIndex)
    }

    public var body: some View {
        ZStack {
            Color.black
                .opacity(backdropOpacity)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.2), value: backdropOpacity)

            TabView(selection: $index) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { offset, attachment in
                    page(attachment)
                        .tag(offset)
                }
            }
            #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: attachments.count > 1 ? .automatic : .never))
            #endif

            controls
        }
        .offset(dragOffset)
        .gesture(dismissGesture)
        .gesture(zoomGesture)
        .sheet(isPresented: $isShowingAltText) { altTextSheet }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            index = max(0, index - 1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            index = min(attachments.count - 1, index + 1)
            return .handled
        }
        .onChange(of: index) { _, _ in
            // Reset zoom/offset when swiping to next media
            withAnimation(.spring(duration: 0.25)) {
                zoom = 1
                committedZoom = 1
                offset = .zero
            }
        }
        #if os(macOS)
            .frame(minWidth: 640, minHeight: 480)
        #endif
    }

    @ViewBuilder
    private func page(_ attachment: MediaAttachment) -> some View {
        if attachment.type.isPlayable {
            VideoAttachmentPlayer(
                attachment: attachment, statusID: statusID, apiBase: apiBase, autoplay: autoplay,
                startsMuted: false, session: session)
        } else {
            RemoteImage(
                url: attachment.displayImageURL,
                blurhash: attachment.blurhash,
                contentMode: .fit,
                accessibilityText: attachment.description
            )
            .scaleEffect(zoom, anchor: .center)
            .offset(offset)
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    zoom = zoom > 1 ? 1 : 2.5
                    committedZoom = zoom
                    if zoom == 1 { offset = .zero }
                }
            }
        }
    }

    private var controls: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .padding(10)
                        .background(.black.opacity(0.3), in: Circle())
                        .unifiedGlass(.subtle, in: Circle())
                }
                .accessibilityLabel(Text("Close", comment: "Media viewer action"))

                Spacer()

                if attachments.indices.contains(index), attachments[index].hasAltText {
                    Button {
                        isShowingAltText = true
                    } label: {
                        Text("ALT", comment: "Alt text button")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .unifiedGlass(.regular, in: Capsule())
                    }
                    .accessibilityLabel(Text("Show description", comment: "Media viewer action"))
                }

                if let url = attachments[safe: index]?.url {
                    ShareLink(item: url) {
                        Image(systemName: AlohaSymbol.share)
                            .font(.body.weight(.semibold))
                            .padding(10)
                            .background(.black.opacity(0.3), in: Circle())
                            .unifiedGlass(.subtle, in: Circle())
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(AlohaMetrics.space3)

            Spacer()
        }
    }

    private var altTextSheet: some View {
        NavigationStack {
            ScrollView {
                Text(attachments[safe: index]?.description ?? "")
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(Text("Description", comment: "Alt text sheet title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isShowingAltText = false
                    } label: {
                        Text("Done", comment: "Sheet action")
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Gestures

    private var backdropOpacity: Double {
        max(0.5, 1 - min(abs(dragOffset.height) / 400, 0.5))
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard zoom <= 1 else { return }
                isDragging = true
                dragOffset = CGSize(width: 0, height: value.translation.height)
            }
            .onEnded { value in
                isDragging = false
                if abs(value.translation.height) > 140
                    || (value.predictedEndTranslation.height > 200)
                {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newZoom = min(5, max(1, committedZoom * value.magnification))
                zoom = newZoom
            }
            .onEnded { _ in
                committedZoom = zoom
                if zoom <= 1 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = .zero }
                }
            }
    }
}

/// Plays through the source ladder, falling to the next rung on failure.
public struct VideoAttachmentPlayer: View {
    private let attachment: MediaAttachment
    private let statusID: String
    private let apiBase: URL
    private let autoplay: Bool
    private let startsMuted: Bool
    private let session: AccountSession?
    /// Set to a position in seconds to jump there; cleared once done. How a
    /// chapter list reaches the player without owning it.
    @Binding private var seekRequest: Double?

    @State private var player: AVPlayer?
    @State private var sourceIndex = 0
    @State private var playbackError: String?
    @State private var retryCount = 0
    @State private var ticker: Any?
    @State private var watcher: Task<Void, Never>?
    /// Whether there is a frame behind the poster yet. The player can be
    /// alive and loading long before it has anything to draw, and a picture
    /// of a rectangle in that window is what "black video" looks like.
    @State private var isRevealed = false
    /// Modern glass controls, auto-hidden so nothing covers the video.
    @State private var showControls = true
    @State private var controlsHideTask: Task<Void, Never>?

    /// Autoplay never starts unmuted (docs/06 §4); a watch page the person
    /// chose to open is the one place sound is on from the start.
    public init(
        attachment: MediaAttachment, statusID: String, apiBase: URL, autoplay: Bool,
        startsMuted: Bool = true, seekRequest: Binding<Double?> = .constant(nil),
        session: AccountSession? = nil
    ) {
        self.attachment = attachment
        self.statusID = statusID
        self.apiBase = apiBase
        self.autoplay = autoplay
        self.startsMuted = startsMuted
        self.session = session
        _seekRequest = seekRequest
    }

    private var sources: [VideoSource] {
        VideoSourceResolver.sources(
            for: attachment, statusID: statusID, apiBase: apiBase,
            isRemote: VideoSourceResolver.isRemote(attachment))
    }

    @Environment(\.alohaPalette) private var palette
    @Environment(\.alohaMetrics) private var metrics

    public var body: some View {
        ZStack {
            if let player {
                PlayerSurface(player: player)
                    .gesture(
                        TapGesture(count: 1)
                            .onEnded { _ in
                                withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
                                scheduleControlsHide()
                            }
                    )
            }
            if !isRevealed {
                RemoteImage(
                    url: attachment.previewURL, blurhash: attachment.blurhash, contentMode: .fit)
                if playbackError == nil { ProgressView() }
            }
            if let playbackError {
                VStack(spacing: 12) {
                    Text(playbackError)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                    Button {
                        sourceIndex = 0
                        retryCount += 1
                    } label: {
                        Text("Try again")
                    }
                    .buttonStyle(.glass)
                }
                .foregroundStyle(.primary)
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding()
            }

            // Modern glass controls, over the video and out of its way.
            if showControls, playbackError == nil {
                VStack {
                    HStack {
                        Spacer()
                        ShareLink(item: attachment.url ?? attachment.previewURL) {
                            Image(systemName: AlohaSymbol.share)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(.black.opacity(0.3), in: Circle())
                                .unifiedGlass(.subtle, in: Circle())
                        }
                        .accessibilityLabel(Text("Share video", comment: "Video action"))
                    }
                    .foregroundStyle(.white)
                    .padding(AlohaMetrics.space3)

                    Spacer()

                    HStack {
                        Spacer()
                        VideoControlsOverlay(player: player)
                    }
                    .padding(AlohaMetrics.space3)
                }
            }
        }
        .task(id: "\(sourceIndex):\(retryCount)") { await prepare() }
        .onChange(of: seekRequest) { _, position in
            guard let position else { return }
            seek(to: position)
        }
        .onDisappear {
            stopWatching()
            releasePlayer()
        }
    }

    private func scheduleControlsHide() {
        controlsHideTask?.cancel()
        controlsHideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) { showControls = false }
                }
            }
        }
    }

    /// Jumps to a chapter and plays from there; a paused player that seeks
    /// and stays paused looks like nothing happened.
    private func seek(to position: Double) {
        guard let player else { return }
        Task { @MainActor in
            _ = await player.seek(
                to: CMTime(seconds: position, preferredTimescale: 600),
                toleranceBefore: .zero, toleranceAfter: .zero)
            guard !Task.isCancelled, self.player === player else { return }
            player.play()
            seekRequest = nil
        }
    }

    private func prepare() async {
        stopWatching()
        releasePlayer()
        isRevealed = false
        playbackError = nil

        for index in sourceIndex..<sources.count {
            guard !Task.isCancelled else { return }
            let source = sources[index]
            let headers = await session?.client.mediaRequestHeaders(for: source.url) ?? [:]
            PlaybackLog.logger.info(
                "opening video rung \(index) \(source.url.absoluteString, privacy: .public)")

            switch await PlaybackReadiness.open(url: source.url, headers: headers, deadline: .zero)
            {
            case .playable(let newPlayer, let item, let isReady):
                guard !Task.isCancelled else {
                    newPlayer.replaceCurrentItem(with: nil)
                    return
                }
                newPlayer.isMuted = startsMuted
                player = newPlayer
                isRevealed = isReady
                if autoplay { newPlayer.play() }
                if let pending = seekRequest { seek(to: pending) }
                scheduleControlsHide()
                startTicking(newPlayer, item: item)
                watch(item, at: index)
                PlaybackLog.logger.notice(
                    "video handed over ready=\(isReady) \(source.url.absoluteString, privacy: .public)"
                )
            case .rejected(let reason):
                PlaybackLog.logger.error("video rung rejected: \(reason, privacy: .public)")
            }
        }

        playbackError = String(
            localized:
                "This video could not be played. Please check your connection and try again.",
            comment: "Video playback failure")
    }

    /// A rung that opens can still collapse later — a master playlist that
    /// answers 200 and a variant that then 404s — so the ladder keeps its
    /// place and moves on rather than freezing on a poster. The same stream
    /// is what lifts the poster the moment there is a frame to show.
    private func watch(_ item: AVPlayerItem, at rung: Int) {
        watcher = Task { @MainActor in
            for await status in PlaybackReadiness.statuses(item) {
                guard !Task.isCancelled else { return }
                switch status {
                case .readyToPlay:
                    isRevealed = true
                case .failed:
                    PlaybackLog.logger.error(
                        "video failed after opening: \(item.error?.localizedDescription ?? "unknown", privacy: .public)"
                    )
                    releasePlayer()
                    isRevealed = false
                    if rung + 1 < sources.count {
                        sourceIndex = rung + 1
                    } else {
                        playbackError =
                            String(
                                localized: "This video could not be played.",
                                comment: "Video playback failure")
                    }
                    return
                default:
                    break
                }
            }
        }
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    private func releasePlayer() {
        stopTicking()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    // MARK: - Watch positions

    /// Reports as the video goes, coalesced well inside the server's
    /// 600-a-minute, so the Continue Watching shelf has something to show.
    private func startTicking(_ player: AVPlayer, item: AVPlayerItem) {
        guard let session, session.capabilities.watchPositions else { return }
        ticker = player.addPeriodicTimeObserver(
            forInterval: CMTime(
                seconds: WatchPositionRules.reportInterval, preferredTimescale: 600),
            queue: .main
        ) { time in
            let duration = item.duration.seconds
            guard duration.isFinite, duration > 0, time.seconds.isFinite else { return }
            _ = MainActor.assumeIsolated {
                Task {
                    await Self.report(
                        session, statusID: statusID, position: time.seconds, duration: duration)
                }
            }
        }
    }

    private func stopTicking() {
        if let ticker, let player { player.removeTimeObserver(ticker) }
        ticker = nil
    }

    static func report(
        _ session: AccountSession, statusID: String, position: Double, duration: Double
    ) async {
        guard session.capabilities.watchPositions,
            WatchPositionRules.shouldReport(position: position, duration: duration)
        else { return }
        try? await session.supportStore.recordWatchPosition(
            accountID: session.id, statusID: statusID, position: position, duration: duration)
        _ = try? await session.client.send(
            Endpoint.video.reportWatched(statusID, position: position, duration: duration))
    }
}

/// Minimal video controls overlay
private struct VideoControlsOverlay: View {
    let player: AVPlayer?
    @Environment(\.alohaPalette) private var palette

    var body: some View {
        HStack(spacing: 16) {
            Button {
                guard let player else { return }
                if player.rate > 0 { player.pause() } else { player.play() }
            } label: {
                Image(systemName: player?.rate ?? 0 > 0 ? "pause.fill" : "play.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.3), in: Circle())
                    .unifiedGlass(.subtle, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
