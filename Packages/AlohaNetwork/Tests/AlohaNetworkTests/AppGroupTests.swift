// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaNetwork

@Suite("App group defaults")
struct AppGroupTests {
    /// Two throwaway domains: the "app's own" and the "group".
    private func domains() -> (UserDefaults, UserDefaults, [String]) {
        let names = ["aloha.tests.\(UUID().uuidString)", "aloha.tests.\(UUID().uuidString)"]
        return (
            UserDefaults(suiteName: names[0]) ?? .standard,
            UserDefaults(suiteName: names[1]) ?? .standard, names
        )
    }

    private func remove(_ names: [String]) {
        for name in names { UserDefaults.standard.removePersistentDomain(forName: name) }
    }

    @Test("The app's own keys move into the group, and only the app's")
    func movesAlohaKeys() {
        let (standard, group, names) = domains()
        defer { remove(names) }
        standard.set("A", forKey: AppGroup.activeAccountKey)
        standard.set("unrelated", forKey: "NSSomethingTheSystemWrote")

        AppGroup.adoptStandardDefaultsIfNeeded(from: standard, into: group, isApp: true)

        #expect(group.string(forKey: AppGroup.activeAccountKey) == "A")
        #expect(group.object(forKey: "NSSomethingTheSystemWrote") == nil)
    }

    @Test("What the group already holds wins, and the move happens once")
    func groupWinsAndOnce() {
        let (standard, group, names) = domains()
        defer { remove(names) }
        standard.set("old", forKey: AppGroup.activeAccountKey)
        group.set("new", forKey: AppGroup.activeAccountKey)

        AppGroup.adoptStandardDefaultsIfNeeded(from: standard, into: group, isApp: true)
        #expect(group.string(forKey: AppGroup.activeAccountKey) == "new")

        standard.set("later", forKey: AppGroup.unreadTotalKey)
        AppGroup.adoptStandardDefaultsIfNeeded(from: standard, into: group, isApp: true)
        #expect(group.object(forKey: AppGroup.unreadTotalKey) == nil)
    }

    @Test("An extension running first does not mark the move as done")
    func extensionDoesNothing() {
        let (standard, group, names) = domains()
        defer { remove(names) }
        standard.set("A", forKey: AppGroup.activeAccountKey)

        AppGroup.adoptStandardDefaultsIfNeeded(from: standard, into: group, isApp: false)
        #expect(!group.bool(forKey: AppGroup.adoptedStandardKey))

        AppGroup.adoptStandardDefaultsIfNeeded(from: standard, into: group, isApp: true)
        #expect(group.string(forKey: AppGroup.activeAccountKey) == "A")
    }
}
