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
        .sheet(isPresented: $isShowingAltText) { altTextSheet }
        #if os(macOS)
            .frame(minWidth: 640, minHeight: 480)
        #endif
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
            .scaleEffect(zoom)
            .offset(offset)
            .gesture(zoomGesture)
            .onTapGesture(count: 2) {
                withAnimation(.spring(duration: 0.25)) {
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
                        .background(.black.opacity(0.4), in: Circle())
                }
                .accessibilityLabel(Text("Close", comment: "Media viewer action"))

                Spacer()

                if attachments.indices.contains(index), attachments[index].hasAltText {
                    Button {
                        isShowingAltText = true
                    } label: {
                        Text("ALT", comment: "Alt text button")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.4), in: Capsule())
                    }
                    .accessibilityLabel(Text("Show description", comment: "Media viewer action"))
                }

                if let url = attachments[safe: index]?.url {
                    ShareLink(item: url) {
                        Image(systemName: AlohaSymbol.share)
                            .font(.body.weight(.semibold))
                            .padding(10)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                }
            }
            .foregroundStyle(.white)
            .padding()

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
        max(0.5, 1 - abs(dragOffset.height) / 400)
    }

    private var dismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoom <= 1 else { return }
                dragOffset = CGSize(width: 0, height: value.translation.height)
            }
            .onEnded { value in
                if abs(value.translation.height) > 140 {
                    dismiss()
                } else {
                    withAnimation(.spring(duration: 0.3)) { dragOffset = .zero }
                }
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(5, max(1, committedZoom * value.magnification))
            }
            .onEnded { _ in
                committedZoom = zoom
                if zoom <= 1 {
                    withAnimation(.spring(duration: 0.2)) { offset = .zero }
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

    public var body: some View {
        Group {
            if let player {
                PlayerSurface(player: player)
            } else {
                RemoteImage(
                    url: attachment.previewURL, blurhash: attachment.blurhash, contentMode: .fit)
            }
        }
        .task(id: sourceIndex) { await prepare() }
        .onChange(of: seekRequest) { _, position in
            guard let position else { return }
            seek(to: position)
        }
        .onDisappear { player?.pause() }
    }

    /// Jumps to a chapter and plays from there; a paused player that seeks
    /// and stays paused looks like nothing happened.
    private func seek(to position: Double) {
        guard let player else { return }
        // The `async` seek rather than the completion-handler one: that
        // handler is a nonisolated `@Sendable` closure, and clearing
        // `seekRequest` from inside it is a main-actor mutation off the main
        // actor — a warning today and a data race whenever the callback lands
        // on another thread.
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

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
