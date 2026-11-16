// SPDX-License-Identifier: MIT

import Foundation

/// The Mac's own switches, by the key each is stored under. Named once here
/// so the Settings pane that sets one and the view that reads it cannot
/// disagree about its spelling.
public enum MacOptions {
    /// The blurred desktop as the window's ground. On unless switched off.
    public static let translucentWindowKey = "aloha.mac.translucentWindow"
    /// The reading column's width in points; zero is the default measure.
    public static let columnWidthKey = "aloha.mac.columnWidth"
    /// The column of trends and suggestions beside the feed.
    public static let contextColumnKey = "aloha.mac.contextColumn"
    /// Home, Activities and Local side by side in place of one timeline.
    public static let deckKey = "aloha.mac.deck"
    /// Whether a link card without a picture fetches one from the page it
    /// links to. Off unless asked for: it tells that site somebody looked.
    public static let linkPreviewsKey = "aloha.mac.linkPreviews"

    public static let narrowColumn: Double = 560
    public static let mediumColumn: Double = 680
    public static let wideColumn: Double = 860
}
