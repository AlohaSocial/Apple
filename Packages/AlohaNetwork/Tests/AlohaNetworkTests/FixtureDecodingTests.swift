// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaNetwork

/// Every mock fixture must decode as the real entity, or the screen tours
/// silently lose the very rows they were meant to exercise.
@Suite struct FixtureDecodingTests {
    @Test(arguments: 0..<12)
    func statusFixtureDecodes(index: Int) throws {
        let json = Fixtures.status(index: index)
        let data = try JSONSerialization.data(withJSONObject: json)
        let status = try AlohaJSON.decoder.decode(Status.self, from: data)
        #expect(status.id == json["id"] as? String)
        if index == 3 { #expect(status.poll != nil, "poll dropped") }
        if index == 4 { #expect(status.card != nil, "card dropped") }
        if index == 6 { #expect(status.reblog != nil, "boost dropped") }
        if index == 8 { #expect(status.inReplyToID != nil, "reply dropped") }
    }
}
