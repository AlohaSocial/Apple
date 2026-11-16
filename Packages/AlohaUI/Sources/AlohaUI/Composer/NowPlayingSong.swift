// SPDX-License-Identifier: MIT

import Foundation
import MusicKit

#if os(iOS) || os(visionOS)
    /// The song playing in Apple Music right now, for the composer's "Share
    /// what's playing": its title, its artist and its music.apple.com link.
    ///
    /// Reading the Music app's queue needs the person's permission
    /// (`NSAppleMusicUsageDescription`), asked the first time. A song from
    /// the person's own library has no catalog link of its own; it is found
    /// in the catalog by title and artist, which needs the MusicKit service
    /// on the App ID — without it, only catalog songs can be shared.
    ///
    /// The Mac has no system music player MusicKit can read, so the action
    /// is not offered there.
    enum NowPlayingSong {
        enum Outcome: Sendable {
            case song(title: String, artist: String, url: URL)
            case notAllowed
            case nothingPlaying
            case noLink
        }

        @MainActor
        static func current() async -> Outcome {
            guard await MusicAuthorization.request() == .authorized else { return .notAllowed }
            guard let entry = SystemMusicPlayer.shared.queue.currentEntry else {
                return .nothingPlaying
            }
            let title = entry.title
            let artist = entry.subtitle ?? ""
            if case .song(let song)? = entry.item, let url = song.url {
                return .song(title: song.title, artist: song.artistName, url: url)
            }
            guard let url = await catalogURL(title: title, artist: artist) else { return .noLink }
            return .song(title: title, artist: artist, url: url)
        }

        private static func catalogURL(title: String, artist: String) async -> URL? {
            var request = MusicCatalogSearchRequest(term: "\(title) \(artist)", types: [Song.self])
            request.limit = 5
            guard let songs = try? await request.response().songs else { return nil }
            let match =
                songs.first {
                    $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame
                        && (artist.isEmpty
                            || $0.artistName.localizedCaseInsensitiveContains(artist))
                } ?? songs.first
            return match?.url
        }

        /// What the composer says when there is no song to insert.
        static func explanation(for outcome: Outcome) -> String? {
            switch outcome {
            case .song:
                nil
            case .notAllowed:
                String(
                    localized:
                        "Allow Aloha Social to use Apple Music in Settings to share what's playing.",
                    comment: "Composer: Apple Music access was not granted")
            case .nothingPlaying:
                String(
                    localized: "Nothing is playing in Apple Music.",
                    comment: "Composer: no song is playing")
            case .noLink:
                String(
                    localized: "That song has no Apple Music link to share.",
                    comment: "Composer: the playing song could not be found in the catalog")
            }
        }
    }
#endif
