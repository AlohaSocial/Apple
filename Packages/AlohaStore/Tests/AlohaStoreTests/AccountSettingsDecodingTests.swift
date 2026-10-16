// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaStore

@Suite("Account settings decoding")
struct AccountSettingsDecodingTests {
    private func decode(_ json: String) throws -> AccountSettings {
        try AlohaJSON.decoder.decode(AccountSettings.self, from: Data(json.utf8))
    }

    @Test("A blob written before the swipe settings existed keeps every other setting")
    func olderBlobKeepsItsSettings() throws {
        // What an earlier build wrote: no swipe keys at all. The synthesised
        // decoder threw here, and the store then replaced everything with
        // the defaults.
        let settings = try decode(
            """
            {"defaultVisibility":"private","defaultSensitive":true,
             "showPopularityCounts":false,"enabledModes":["photos","audio"],
             "digestTimes":[7,19]}
            """)
        #expect(settings.defaultVisibility == .private)
        #expect(settings.defaultSensitive)
        #expect(!settings.showPopularityCounts)
        #expect(settings.enabledModes == [.photos, .audio])
        #expect(settings.digestTimes == [7, 19])
        #expect(settings.leadingSwipeAction == .reply)
        #expect(settings.trailingSwipeAction == .favourite)
    }

    @Test("Swipe actions survive a round trip")
    func swipeActionsRoundTrip() throws {
        var settings = AccountSettings()
        settings.leadingSwipeAction = .bookmark
        settings.trailingSwipeAction = .none
        let data = try JSONEncoder().encode(settings)
        let restored = try AlohaJSON.decoder.decode(AccountSettings.self, from: data)
        #expect(restored == settings)
    }

    @Test("A swipe action this build does not know falls back to that one default")
    func unknownSwipeActionFallsBack() throws {
        let settings = try decode(
            #"{"leadingSwipeAction":"teleport","trailingSwipeAction":"boost","loopShorts":false}"#)
        #expect(settings.leadingSwipeAction == .reply)
        #expect(settings.trailingSwipeAction == .boost)
        #expect(!settings.loopShorts)
    }
}
