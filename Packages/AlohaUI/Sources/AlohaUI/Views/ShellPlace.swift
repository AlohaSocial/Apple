// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// A top-level place in the sidebar, as the menu bar numbers it.
///
/// ⌘1, ⌘2, … follow the sidebar's own order, the way Mail's follow its
/// mailboxes — so the shortcut for a place is the position you can see it
/// in, and a person who hides a feed does not find every number after it
/// pointing somewhere new and unlisted.
public struct ShellPlace: Hashable, Sendable {
    public var title: String
    public var route: Route

    public init(title: String, route: Route) {
        self.title = title
        self.route = route
    }

    /// ⌘1 to ⌘9; a tenth place has no digit left to give it.
    static let numberedLimit = 9

    /// The digit for the place at `index`, or nil past the ninth.
    static func shortcutDigit(at index: Int) -> Character? {
        guard index >= 0, index < numberedLimit else { return nil }
        return Character(String(index + 1))
    }

    /// The sidebar's top group, in the order it lists it — Nextcloud
    /// Social's own sidebar order: the feeds this account shows, then
    /// activities, then direct messages, then Discover.
    static func sidebarOrder(
        modes: [FeedMode], modeTitle: (FeedMode) -> String
    ) -> [ShellPlace] {
        var places = modes.map {
            ShellPlace(title: modeTitle($0), route: .timeline(TimelineKey(mode: $0, source: .home)))
        }
        places.append(
            ShellPlace(
                title: String(localized: "Activities", comment: "Menu item"),
                route: .notifications))
        places.append(
            ShellPlace(
                title: String(localized: "Direct messages", comment: "Menu item"),
                route: .conversations))
        places.append(
            ShellPlace(title: String(localized: "Discover", comment: "Menu item"), route: .explore))
        return places
    }
}
