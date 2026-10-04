import AVFoundation
import Foundation
import Testing
@testable import AlohaUI

@Suite("Active video startup")
struct PlaybackStartupTests {
    @MainActor
    @Test("Active playback gets a player without waiting for the metadata deadline")
    func immediateHandoff() async {
        let clock = ContinuousClock()
        let started = clock.now
        let result = await PlaybackReadiness.open(
            url: URL(fileURLWithPath: "/aloha-missing-startup-test.mp4"),
            headers: [:], deadline: .zero)
        #expect(started.duration(to: clock.now) < .seconds(2))
        if case .playable(let player, let item, _) = result {
            #expect(player.currentItem === item)
            #expect(player.rate == 0)
            player.replaceCurrentItem(with: nil)
        }
    }
}
