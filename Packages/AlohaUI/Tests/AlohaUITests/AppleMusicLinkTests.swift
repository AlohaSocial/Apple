// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaUI

@Suite("Apple Music song links")
struct AppleMusicLinkTests {
    private func id(_ string: String) -> String? {
        AppleMusicLink.songID(in: URL(string: string))
    }

    @Test("A song's own link names it")
    func songLink() {
        #expect(id("https://music.apple.com/us/song/blinding-lights/1488408568") == "1488408568")
        #expect(id("https://music.apple.com/de/song/1488408568") == "1488408568")
    }

    @Test("An album link with a track picked out names the track")
    func albumWithTrack() {
        #expect(
            id("https://music.apple.com/gb/album/after-hours/1499378108?i=1499378615")
                == "1499378615")
        #expect(
            id("https://geo.music.apple.com/us/album/x/1499378108?i=1499378615&l=en")
                == "1499378615")
    }

    @Test("Albums, playlists, artists and other hosts are not songs")
    func notSongs() {
        #expect(id("https://music.apple.com/us/album/after-hours/1499378108") == nil)
        #expect(
            id(
                "https://music.apple.com/us/playlist/todays-hits/pl.f4d106fed2bd41149aaacabb233eb5eb"
            ) == nil)
        #expect(id("https://music.apple.com/us/artist/the-weeknd/479756766") == nil)
        #expect(id("https://example.com/us/song/x/1488408568") == nil)
        #expect(id("https://music.apple.com/us/song/x/l.abc123") == nil)
    }

    @Test("The composer's text has the song, the artist and the link")
    func shareText() throws {
        let url = try #require(URL(string: "https://music.apple.com/us/song/x/1"))
        let text = AppleMusicLink.shareText(title: "Song", artist: "Band", url: url)
        #expect(text.contains("Song"))
        #expect(text.contains("Band"))
        #expect(text.hasSuffix(url.absoluteString))
    }
}
