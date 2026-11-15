// SPDX-License-Identifier: MIT

import Foundation

/// A song on music.apple.com, from the link a post or its card carries.
///
/// Apple Music writes a song's link two ways: as the song itself,
/// `music.apple.com/<storefront>/song/<name>/<id>`, and — what the Share
/// button in Music writes — as its album with the track picked out,
/// `music.apple.com/<storefront>/album/<name>/<album id>?i=<song id>`. Both
/// name the song by its catalog id, which is all MusicKit needs.
nonisolated enum AppleMusicLink {
    static func songID(in url: URL?) -> String? {
        guard let url, let host = url.host()?.lowercased(),
            host == "music.apple.com" || host == "geo.music.apple.com"
        else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        if let picked = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "i" })?.value, isCatalogID(picked),
            path.contains("album")
        {
            return picked
        }
        guard let song = path.firstIndex(of: "song"), let last = path.last,
            path.index(after: song) < path.endIndex, isCatalogID(last)
        else { return nil }
        return last
    }

    /// Catalog ids are digits; a playlist's `pl.…` or a library's `l.…` id
    /// is not a song MusicKit can look up in the catalog.
    private static func isCatalogID(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy(\.isNumber)
    }

    /// The words and link the composer inserts for a song.
    static func shareText(title: String, artist: String, url: URL) -> String {
        let line = String(
            localized: "Listening to \(title) by \(artist)",
            comment: "Composer text for the song playing in Apple Music, before its link")
        return "\(line)\n\(url.absoluteString)"
    }
}
