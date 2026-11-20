// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaStore

/// A defaults domain of its own per test, removed afterwards: the suites run
/// in parallel, and `.standard` is shared by all of them.
private func scratchDefaults() -> (UserDefaults, String) {
    let name = "aloha.tests.\(UUID().uuidString)"
    return (UserDefaults(suiteName: name) ?? .standard, name)
}

private func scratchDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "aloha-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Widget favourites")
struct WidgetFavouritesTests {
    let account = UUID()

    @Test("A tap is read back for its own post and account only")
    func readsBackPerPostAndAccount() {
        let (defaults, name) = scratchDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        WidgetFavourites.set(true, statusID: "1", accountID: account, in: defaults)
        #expect(WidgetFavourites.state(statusID: "1", accountID: account, in: defaults) == true)
        #expect(WidgetFavourites.state(statusID: "2", accountID: account, in: defaults) == nil)
        #expect(WidgetFavourites.state(statusID: "1", accountID: UUID(), in: defaults) == nil)
    }

    @Test("An unfavourite is remembered as false, not as nothing")
    func unfavouriteIsRemembered() {
        let (defaults, name) = scratchDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        WidgetFavourites.set(false, statusID: "1", accountID: account, in: defaults)
        #expect(WidgetFavourites.state(statusID: "1", accountID: account, in: defaults) == false)
    }

    @Test("After a day the cache has the server's word, and the tap is forgotten")
    func expires() {
        let (defaults, name) = scratchDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        let then = Date(timeIntervalSince1970: 1_000_000)
        WidgetFavourites.set(true, statusID: "1", accountID: account, now: then, in: defaults)
        let later = then.addingTimeInterval(WidgetFavourites.lifetime + 1)
        #expect(
            WidgetFavourites.state(statusID: "1", accountID: account, now: later, in: defaults)
                == nil)
    }

    @Test("A refused tap is taken back")
    func clear() {
        let (defaults, name) = scratchDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        WidgetFavourites.set(true, statusID: "1", accountID: account, in: defaults)
        WidgetFavourites.clear(statusID: "1", accountID: account, in: defaults)
        #expect(WidgetFavourites.state(statusID: "1", accountID: account, in: defaults) == nil)
    }
}
