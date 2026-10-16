// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaUI

@Suite("Shell polish")
struct ShellPolishTests {
    // MARK: - Settings search

    @Test("Settings search ignores case, accents and surrounding space")
    func settingsSearchMatchingRule() {
        #expect(SettingsSection.matches("DUNKEL", in: ["Darstellung", "dunkel hell"]))
        #expect(SettingsSection.matches("resume", in: ["Résumé"]))
        #expect(SettingsSection.matches("  cache ", in: ["Speicher cache"]))
        #expect(!SettingsSection.matches("bluetooth", in: ["Darstellung", "dunkel hell"]))
    }

    @Test("An empty search shows every section")
    func emptySearchShowsEverything() {
        for section in SettingsSection.allCases {
            #expect(section.matches(""))
            #expect(section.matches("   "))
        }
    }

    @Test("A section is found by its own title and its keywords")
    func sectionsFindThemselves() {
        for section in SettingsSection.allCases {
            #expect(section.matches(section.title))
        }
        #expect(SettingsSection.appearance.matches("dark"))
        #expect(SettingsSection.storage.matches("cache"))
        #expect(!SettingsSection.storage.matches("dark"))
    }

    // MARK: - ⌘1… order

    @Test("The menu bar numbers places in the sidebar's order")
    func placesFollowTheSidebar() {
        let places = ShellPlace.sidebarOrder(
            modes: [.home, .photos, .video], includesActivities: true,
            modeTitle: { "\($0)" })
        #expect(
            places.map(\.route) == [
                .timeline(TimelineKey(mode: .home, source: .home)),
                .timeline(TimelineKey(mode: .photos, source: .home)),
                .timeline(TimelineKey(mode: .video, source: .home)),
                .conversations, .notifications, .explore,
            ])

        let withoutActivities = ShellPlace.sidebarOrder(
            modes: [.home], includesActivities: false, modeTitle: { "\($0)" })
        #expect(!withoutActivities.contains { $0.route == .notifications })
    }

    @Test("Only the first nine places get a digit")
    func digitsStopAtNine() {
        #expect(ShellPlace.shortcutDigit(at: 0) == "1")
        #expect(ShellPlace.shortcutDigit(at: 8) == "9")
        #expect(ShellPlace.shortcutDigit(at: 9) == nil)
        #expect(ShellPlace.shortcutDigit(at: -1) == nil)
    }

    // MARK: - iPad tab customisation

    /// The system stores where a person pinned each tab under these ids, so
    /// two places sharing one would move together, and a place falling back
    /// to the catch-all would lose its position.
    @Test("Every pinnable iPad place has its own customisation id")
    func customisationIDsAreDistinct() {
        let routes: [Route] = [
            .lists, .interests, .subscriptions, .collections(accountID: nil), .bookmarks,
            .favourites, .followRequests, .safety, .archived, .statistics, .settings,
            .notifications, .conversations, .explore,
        ]
        let ids = routes.map(ShellTab.customizationID(for:))
        #expect(Set(ids).count == ids.count)
        #expect(!ids.contains("aloha.tab.other"))
    }

    // MARK: - Haptics

    @Test("Haptics play only when switched on and Reduce Motion is off")
    func hapticsGate() {
        #expect(Senses.allowsHaptics(enabled: true, reduceMotion: false))
        #expect(!Senses.allowsHaptics(enabled: false, reduceMotion: false))
        #expect(!Senses.allowsHaptics(enabled: true, reduceMotion: true))
        #expect(!Senses.allowsHaptics(enabled: false, reduceMotion: true))
    }
}
