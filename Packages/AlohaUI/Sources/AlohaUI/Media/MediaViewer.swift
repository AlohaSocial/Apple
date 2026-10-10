// SPDX-License-Identifier: MIT

import AVKit
import AlohaDesign
import AlohaMedia
import AlohaModels
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

    @State private var index: Int
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var isShowingAltText = false
    @State private var isDragging = false

    public init(
        attachments: [MediaAttachment], startIndex: Int, statusID: String,
        apiBase: URL, autoplay: Bool
    ) {
        self.attachments = attachments
        self.statusID = statusID
        self.apiBase = apiBase
        self.autoplay = autoplay
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
                attachment: attachment, statusID: statusID, apiBase: apiBase, autoplay: autoplay)
        } else {
            RemoteImage(
                url: attachment.url ?? attachment.previewURL,
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
            .padding(metrics.space3)

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
                if abs(value.translation.height) > 140 || (value.predictedEndTranslation.height > 200) {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { dragOffset = .zero }
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
    /// Set to a position in seconds to jump there; cleared once done. How a
    /// chapter list reaches the player without owning it.
    @Binding private var seekRequest: Double?

    @State private var player: AVPlayer?
    @State private var sourceIndex = 0
    @State private var showControls = true
    @State private var controlsHideTask: Task<Void, Never>?

    /// Autoplay never starts unmuted (docs/06 §4); a watch page the person
    /// chose to open is the one place sound is on from the start.
    public init(
        attachment: MediaAttachment, statusID: String, apiBase: URL, autoplay: Bool,
        startsMuted: Bool = true, seekRequest: Binding<Double?> = .constant(nil)
    ) {
        self.attachment = attachment
        self.statusID = statusID
        self.apiBase = apiBase
        self.autoplay = autoplay
        self.startsMuted = startsMuted
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
            Group {
                if let player {
                    PlayerSurface(player: player)
                        .gesture(
                            TapGesture(count: 1)
                                .onEnded { _ in
                                    withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
                                    scheduleControlsHide()
                                }
                        )
                } else {
                    RemoteImage(
                        url: attachment.previewURL, blurhash: attachment.blurhash, contentMode: .fit)
                }
            }

            // Controls overlay
            if showControls {
                VStack {
                    HStack {
                        Button {
                            // Exit fullscreen / close handled by parent
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .padding(10)
                                .background(.black.opacity(0.3), in: Circle())
                                .unifiedGlass(.subtle, in: Circle())
                        }
                        .accessibilityLabel(Text("Close", comment: "Video action"))

                        Spacer()

                        ShareLink(item: attachment.url ?? attachment.previewURL) {
                            Image(systemName: AlohaSymbol.share)
                                .font(.body.weight(.semibold))
                                .padding(10)
                                .background(.black.opacity(0.3), in: Circle())
                                .unifiedGlass(.subtle, in: Circle())
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(metrics.space3)

                    Spacer()

                    HStack {
                        Spacer()
                        // Play/pause, time, etc.
                        VideoControlsOverlay(player: player)
                    }
                    .padding(metrics.space3)
                }
        }
        .task(id: sourceIndex) { await prepare() }
        .onChange(of: seekRequest) { _, position in
            guard let position else { return }
            seek(to: position)
        }
        .onDisappear { player?.pause() }
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
            player.play()
            seekRequest = nil
        }
    }

    private func prepare() async {
        guard sources.indices.contains(sourceIndex) else { return }
        let source = sources[sourceIndex]
        let item = AVPlayerItem(url: source.url)

        // A 404 on a master playlist means no ladder exists, and the right
        // answer is to play the plain file — never to report a broken video.
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = startsMuted
        player = newPlayer

        if autoplay { newPlayer.play() }
        if let pending = seekRequest { seek(to: pending) }
        scheduleControlsHide()

        // Watch for a failed item and fall to the next rung at the same point.
        for await status in item.publisher(for: \.status).values {
            if status == .failed, sourceIndex + 1 < sources.count {
                sourceIndex += 1
                return
            }
            if status == .readyToPlay { return }
        }
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
