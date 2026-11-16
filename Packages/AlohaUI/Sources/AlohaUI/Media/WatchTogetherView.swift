// SPDX-License-Identifier: MIT

import AVFoundation
import AlohaDesign
import GroupActivities
import SwiftUI
import Synchronization

/// The shared player: whatever the call is watching, in step for everybody.
///
/// Play, pause and seeking are the playback coordinator's — anybody's
/// press is everybody's. For shorts, moving to the next or the previous one
/// moves the whole call (`WatchTogether.move(to:)`).
struct WatchTogetherView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let together: WatchTogether

    @State private var player = AVPlayer()
    @State private var coordinatorDelegate = PlaybackIdentity()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerSurface(player: player)
                .ignoresSafeArea()

            VStack {
                header
                Spacer()
                if together.kind == .shorts, together.videos.count > 1 { shortsControls }
            }
            .padding(AlohaMetrics.space3)
            .foregroundStyle(.white)
        }
        .task(id: together.session.map(ObjectIdentifier.init)) {
            guard let session = together.session else { return }
            // Items are told apart by their file's address, the same on
            // every device whatever each one's server called the post.
            player.playbackCoordinator.delegate = coordinatorDelegate
            player.playbackCoordinator.coordinateWithSession(session)
        }
        .task(id: together.current?.mediaURL) {
            guard let video = together.current else { return }
            let item = AVPlayerItem(url: video.mediaURL)
            coordinatorDelegate.name(item, video.mediaURL.absoluteString)
            player.replaceCurrentItem(with: item)
            player.play()
        }
        .gesture(swipe, including: together.kind == .shorts ? .all : .subviews)
        .onDisappear {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AlohaMetrics.space3) {
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text("SharePlay", comment: "Watch together header")
                } icon: {
                    Image(systemName: "shareplay")
                }
                .font(.caption.weight(.semibold))
                if let video = together.current {
                    Text(video.author)
                        .font(.headline)
                    if !video.text.isEmpty {
                        Text(video.text)
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
            }
            .shadow(color: .black.opacity(0.5), radius: 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button {
                together.leave()
            } label: {
                Text("Leave", comment: "Leave a SharePlay session")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, AlohaMetrics.space3)
                    .padding(.vertical, AlohaMetrics.space2)
                    .alohaGlassEffect(MediaViewer.controlGlass, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                Text(
                    "The others keep watching.",
                    comment: "Accessibility hint for leaving a SharePlay session"))
        }
    }

    /// Buttons as well as the swipe, so moving on never depends on a gesture.
    private var shortsControls: some View {
        HStack(spacing: AlohaMetrics.space4) {
            Button {
                together.move(to: together.index - 1)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.title3.weight(.semibold))
                    .padding(12)
                    .alohaGlassEffect(MediaViewer.controlGlass, in: Circle())
            }
            .disabled(together.index == 0)
            .accessibilityLabel(Text("Previous short", comment: "SharePlay shorts control"))

            Text(
                "\(together.index + 1) of \(together.videos.count)",
                comment: "Position in a run of shorts watched together"
            )
            .font(.caption.monospacedDigit())

            Button {
                together.move(to: together.index + 1)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .padding(12)
                    .alohaGlassEffect(MediaViewer.controlGlass, in: Circle())
            }
            .disabled(together.index >= together.videos.count - 1)
            .accessibilityLabel(Text("Next short", comment: "SharePlay shorts control"))
        }
        .buttonStyle(.plain)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let height = value.translation.height
                guard abs(height) > 80, abs(height) > abs(value.translation.width) else { return }
                together.move(to: together.index + (height < 0 ? 1 : -1))
            }
    }
}

/// Names an item by its file's address, so the coordinator knows two
/// devices are on the same video even though each made its own item.
///
/// The coordinator asks from its own queue, where the item's asset may not
/// be read; the name is written down on the main actor when the item is
/// made, and read back here under a lock.
nonisolated final class PlaybackIdentity: NSObject, AVPlayerPlaybackCoordinatorDelegate,
    Sendable
{
    private let names = Mutex<[ObjectIdentifier: String]>([:])

    /// Only the item on now is ever asked about, so only it is kept.
    func name(_ item: AVPlayerItem, _ identifier: String) {
        names.withLock { $0 = [ObjectIdentifier(item): identifier] }
    }

    func playbackCoordinator(
        _ coordinator: AVPlayerPlaybackCoordinator, identifierFor playerItem: AVPlayerItem
    ) -> String {
        names.withLock { $0[ObjectIdentifier(playerItem)] } ?? ""
    }
}

/// "Watch together": straight into SharePlay while a FaceTime call is on,
/// and the share sheet's SharePlay row to start one with somebody when
/// there is no call. Not drawn at all in a build without the SharePlay
/// entitlement.
struct WatchTogetherButton<Label: View>: View {
    let activity: WatchTogetherActivity
    @ViewBuilder let label: () -> Label

    @StateObject private var callState = GroupStateObserver()

    var body: some View {
        if WatchTogether.isEnabled {
            if callState.isEligibleForGroupSession {
                Button {
                    Task { await WatchTogether.shared.start(activity) }
                } label: {
                    label()
                }
                .accessibilityLabel(Text("Watch together", comment: "SharePlay action"))
            } else {
                ShareLink(
                    item: activity,
                    preview: SharePreview(
                        Text("Watch together", comment: "SharePlay share sheet preview title"))
                ) {
                    label()
                }
                .accessibilityLabel(Text("Watch together", comment: "SharePlay action"))
                .accessibilityHint(
                    Text(
                        "Starts SharePlay with the people you choose.",
                        comment: "Accessibility hint for Watch together with no call"))
            }
        }
    }
}

extension View {
    /// Where the shared player appears, and where the app starts listening
    /// for sessions: the shell, once per window.
    func watchTogetherPresentation() -> some View {
        modifier(WatchTogetherPresentation())
    }
}

private struct WatchTogetherPresentation: ViewModifier {
    @State private var together = WatchTogether.shared

    func body(content: Content) -> some View {
        content
            .task { await together.listen() }
            #if os(iOS)
                .fullScreenCover(isPresented: $together.isPresenting) {
                    WatchTogetherView(together: together)
                }
            #else
                .sheet(isPresented: $together.isPresenting) {
                    WatchTogetherView(together: together)
                        #if os(macOS)
                            .frame(minWidth: 640, minHeight: 420)
                        #endif
                }
            #endif
    }
}
