// SPDX-License-Identifier: MIT

import SwiftUI

#if os(iOS) || os(visionOS)
    /// "Share what's playing": the song playing in Apple Music, as a line
    /// with its title and artist and its music.apple.com link, which a
    /// timeline then draws as a song card with a preview to play
    /// (`AppleMusicCardView`).
    extension ComposerView {
        func insertNowPlaying() async {
            nowPlayingMessage = nil
            let outcome = await NowPlayingSong.current()
            if case .song(let title, let artist, let url) = outcome {
                insertAtCursor(AppleMusicLink.shareText(title: title, artist: artist, url: url))
            } else {
                nowPlayingMessage = NowPlayingSong.explanation(for: outcome)
            }
        }
    }
#endif
