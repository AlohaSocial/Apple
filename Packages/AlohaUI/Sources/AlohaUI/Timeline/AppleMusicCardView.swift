// SPDX-License-Identifier: MIT

import AVFoundation
import AlohaDesign
import AlohaModels
import MusicKit
import Observation
import SwiftUI

/// A song, as the card draws it: what MusicKit's catalog says about it.
nonisolated struct AppleMusicSong: Sendable, Hashable {
    let id: String
    let title: String
    let artist: String
    let artworkURL: URL?
    /// Apple's 30-second preview, which plays without a subscription.
    let previewURL: URL?
    let url: URL?
}

/// Looks songs up in the Apple Music catalog, once each.
///
/// MusicKit needs the MusicKit service enabled on the App ID — something
/// only a person with access to the developer account can do. Without it
/// (or without a network, or with Apple Music access turned off in
/// Settings) every lookup fails, and the card is the ordinary link card it
/// would have been anyway. A failure is remembered for the session, so a
/// timeline full of songs does not ask again on every scroll.
actor AppleMusicCatalog {
    static let shared = AppleMusicCatalog()

    private var songs: [String: AppleMusicSong?] = [:]

    func song(id: String) async -> AppleMusicSong? {
        if let known = songs[id] { return known }
        switch MusicAuthorization.currentStatus {
        case .denied, .restricted:
            // The person said no to Apple Music in Settings; the card says
            // nothing more than the link does.
            return nil
        default:
            break
        }
        let found = await Self.lookUp(id)
        songs[id] = found
        return found
    }

    private static func lookUp(_ id: String) async -> AppleMusicSong? {
        let request = MusicCatalogResourceRequest<Song>(
            matching: \.id, equalTo: MusicItemID(id))
        guard let song = try? await request.response().items.first else { return nil }
        return AppleMusicSong(
            id: id, title: song.title, artist: song.artistName,
            artworkURL: song.artwork?.url(width: 300, height: 300),
            previewURL: song.previewAssets?.first?.url, url: song.url)
    }
}

/// The one preview playing, wherever it was started.
///
/// It takes the app's audio session like a track in Audio mode
/// (`AudioSessionCoordinator`): starting a preview pauses a video playing
/// with its sound on, or the Audio mode's track, and either of those
/// starting stops the preview. Leaving the screen does not stop it — it is
/// thirty seconds at most.
@MainActor
@Observable
final class MusicPreviewPlayer {
    static let shared = MusicPreviewPlayer()

    /// The song whose preview is playing.
    private(set) var playingID: String?

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var claim: AudibleClaim?
    @ObservationIgnored private var endObserver: NotificationSubscription?

    private init() {}

    func toggle(_ song: AppleMusicSong) {
        if playingID == song.id {
            stop()
        } else if let url = song.previewURL {
            play(url, id: song.id)
        }
    }

    private func play(_ url: URL, id: String) {
        stop()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        playingID = id
        claim = AudioSessionCoordinator.shared.claim(owner: ObjectIdentifier(self), kind: .audio) {
            [weak self] in
            self?.claim = nil
            self?.stop()
        }
        player.play()
        let finished = ObjectIdentifier(item)
        endObserver = NotificationSubscription(name: AVPlayerItem.didPlayToEndTimeNotification) {
            notification in
            guard let object = notification.object,
                ObjectIdentifier(object as AnyObject) == finished
            else { return }
            Task { @MainActor in MusicPreviewPlayer.shared.stop() }
        }
    }

    func stop() {
        endObserver = nil
        player?.pause()
        player = nil
        playingID = nil
        if let claim { AudioSessionCoordinator.shared.release(claim) }
        claim = nil
    }
}

/// A post's Apple Music song, as a card with its artwork and a button that
/// plays the 30-second preview. Until MusicKit has answered — and for good
/// when it cannot — it is the ordinary link card.
struct AppleMusicCardView: View {
    @Environment(\.alohaPalette) private var palette

    let card: Card
    let songID: String
    let onOpen: () -> Void

    @State private var song: AppleMusicSong?
    @State private var preview = MusicPreviewPlayer.shared

    var body: some View {
        Group {
            if let song {
                songCard(song)
            } else {
                LinkCardView(card: card, onOpen: onOpen)
            }
        }
        .task(id: songID) {
            song = await AppleMusicCatalog.shared.song(id: songID)
        }
    }

    private func songCard(_ song: AppleMusicSong) -> some View {
        let isPlaying = preview.playingID == song.id
        return HStack(spacing: AlohaMetrics.space3) {
            Button(action: onOpen) {
                HStack(spacing: AlohaMetrics.space3) {
                    RemoteImage(url: song.artworkURL ?? card.image, blurhash: card.blurhash)
                        .frame(width: 64, height: 64)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: AlohaMetrics.cornerSmall, style: .continuous)
                        )
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Label {
                            Text("Apple Music", comment: "Provider line on a song card")
                        } icon: {
                            Image(systemName: "music.note")
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(palette.secondaryLabel)
                        Text(song.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.label)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(song.artist)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryLabel)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(
                Text("Opens the song in Apple Music.", comment: "Song card accessibility hint"))

            if song.previewURL != nil {
                Button {
                    preview.toggle(song)
                } label: {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 34))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(palette.accent)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isPlaying
                        ? Text("Stop preview", comment: "Song card action")
                        : Text("Play preview", comment: "Song card action"))
            }
        }
        .padding(AlohaMetrics.space3)
        .background(
            palette.surfaceRaised,
            in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous))
    }
}

/// The card a post's link gets: a song card for an Apple Music song, the
/// link card for everything else.
struct StatusLinkCard: View {
    let card: Card
    let onOpen: () -> Void

    var body: some View {
        if let id = AppleMusicLink.songID(in: card.url) {
            AppleMusicCardView(card: card, songID: id, onOpen: onOpen)
        } else {
            LinkCardView(card: card, onOpen: onOpen)
        }
    }
}
