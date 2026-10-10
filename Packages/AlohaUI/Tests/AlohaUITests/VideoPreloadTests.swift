// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import AlohaUI

@Suite("Video preloading policy")
struct VideoPreloadTests {
    @Test("Preloading respects network, power, autoplay and sensitive-content consent")
    func resourcePolicy() {
        #expect(NextVideoPreloader.permits(networkAllowed: true, lowPower: false, autoplay: true, covered: false))
        #expect(!NextVideoPreloader.permits(networkAllowed: false, lowPower: false, autoplay: true, covered: false))
        #expect(!NextVideoPreloader.permits(networkAllowed: true, lowPower: true, autoplay: true, covered: false))
        #expect(!NextVideoPreloader.permits(networkAllowed: true, lowPower: false, autoplay: false, covered: false))
        #expect(!NextVideoPreloader.permits(networkAllowed: true, lowPower: false, autoplay: true, covered: true))
    }

    @Test("Prepared players cannot cross account boundaries or collide on joined identifiers")
    func cacheIdentity() {
        let account = UUID()
        let key = NextVideoPreloader.key(accountID: account, statusID: "a:b", attachmentID: "c")
        #expect(key != NextVideoPreloader.key(accountID: UUID(), statusID: "a:b", attachmentID: "c"))
        #expect(key != NextVideoPreloader.key(accountID: account, statusID: "a", attachmentID: "b:c"))
    }
}
