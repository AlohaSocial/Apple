// SPDX-License-Identifier: MIT

import Foundation

/// Where a video was when its player went away, for the player built in its
/// place a moment later.
///
/// Folding or unfolding an iPhone Duo builds the shell again, and every
/// player in it with it: a short or a watch page started again from its
/// first frame. A player that goes away records its position here, and one
/// that opens the same video soon after starts from it. Only for a short
/// while (`window`) — this is a hand-over between two views, not a memory of
/// what was watched, which is the server's (`WatchPositionRules`).
struct PlaybackHandover {
    struct Position: Equatable {
        var seconds: Double
        /// Whether it was playing, so a paused video stays paused.
        var wasPlaying: Bool
    }

    /// Long enough for a shell to be rebuilt and a player to open again on a
    /// slow network; short enough that a video opened again on purpose
    /// starts at the beginning.
    static let window: TimeInterval = 30
    /// Under this a video has barely started, and starting it again is what
    /// the reader would expect anyway.
    static let minimumSeconds: Double = 1
    /// More than a screenful of players is never handed over at once.
    static let capacity = 16

    private var entries: [String: (position: Position, recorded: Date)] = [:]

    mutating func record(
        _ seconds: Double, wasPlaying: Bool, for attachmentID: String, now: Date = .now
    ) {
        guard seconds.isFinite, seconds >= Self.minimumSeconds else {
            entries[attachmentID] = nil
            return
        }
        entries[attachmentID] = (Position(seconds: seconds, wasPlaying: wasPlaying), now)
        guard entries.count > Self.capacity else { return }
        // The stalest goes first.
        if let oldest = entries.min(by: { $0.value.recorded < $1.value.recorded })?.key {
            entries[oldest] = nil
        }
    }

    /// The position to start from, if one was recorded within the window.
    /// Not consumed: a watch page asks before its player does, so it does not
    /// also seek to the server's older position.
    func position(for attachmentID: String, now: Date = .now) -> Position? {
        guard let entry = entries[attachmentID],
            now.timeIntervalSince(entry.recorded) <= Self.window
        else { return nil }
        return entry.position
    }

    /// The app's one ledger. Players live on the main actor.
    @MainActor static var shared = PlaybackHandover()
}
