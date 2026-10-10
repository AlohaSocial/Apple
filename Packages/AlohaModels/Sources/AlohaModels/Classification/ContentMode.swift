// SPDX-License-Identifier: MIT

import Foundation

/// A top-level content destination. Modes are not filters bolted onto one list:
/// each owns its timeline key and cache, its source selection, its layout and
/// gestures, and its Explore surface (docs/06 §1).
public enum FeedMode: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case home
    case photos
    case video
    case shorts
    case news
    case audio

    public var id: String { rawValue }

    /// Off by default; enabled in Settings.
    public var isOptional: Bool { self == .news || self == .audio }

    public static let defaultEnabled: [FeedMode] = [.home, .photos, .video, .shorts]

    /// Each mode needs a silhouette of its own at 24pt. Photos, Video and
    /// Shorts were all a rounded rectangle with a mark in it, so the tab bar
    /// read as three of the same thing.
    ///
    /// Every name here has a [selectedSymbolName](doc:selectedSymbolName) to
    /// fill, because that is how a tab says "on": Apple's own apps switch
    /// weight rather than colour, and an outline icon beside a filled one
    /// reads as off instead of as a different drawing style.
    public var symbolName: String {
        switch self {
        case .home: "house"
        case .photos: "photo.stack"
        case .video: "play.rectangle"
        // A short is a tall video: the silhouette says so where a filmstrip
        // could have been the video feed's twin.
        case .shorts: "rectangle.portrait"
        case .news: "newspaper"
        case .audio: "speaker.wave.2"
        }
    }

    /// The selected spelling of [symbolName](doc:symbolName).
    public var selectedSymbolName: String {
        switch self {
        case .home: "house.fill"
        case .photos: "photo.stack.fill"
        case .video: "play.rectangle.fill"
        case .shorts: "rectangle.portrait.fill"
        case .news: "newspaper.fill"
        case .audio: "speaker.wave.2.fill"
        }
    }
}

/// What a status *is*, decided once on insert and persisted.
public enum ContentKind: String, Codable, Sendable, Hashable {
    case text
    case photo
    case video
    case short
    case audio
    case news
    /// The server filled in no `meta`, so the decision waits until a player
    /// reports real dimensions. Provisionally excluded from Shorts.
    case undetermined

    public func belongs(in mode: FeedMode) -> Bool {
        switch mode {
        case .home: true
        case .photos: self == .photo
        case .video: self == .video || self == .short
        case .shorts: self == .short
        case .news: self == .news
        case .audio: self == .audio
        }
    }
}
