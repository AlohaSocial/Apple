// SPDX-License-Identifier: MIT
import AlohaModels
import Foundation
import Testing
@testable import AlohaUI

@Suite("Discover media selection")
struct DiscoverMediaTests {
    @Test("Mixed posts open the attachment matching the selected section")
    func mixedAttachments() throws {
        let attachments = try JSONDecoder().decode([MediaAttachment].self, from: Data("""
        [{"id":"1","type":"audio"},{"id":"2","type":"image"},{"id":"3","type":"video"}]
        """.utf8))
        #expect(DiscoverMediaGrid.Media.image.index(in: attachments) == 1)
        #expect(DiscoverMediaGrid.Media.video.index(in: attachments) == 2)
    }

    @Test("Audio and unknown attachments are not pictures or videos")
    func excludesNonVisualMedia() throws {
        let attachments = try JSONDecoder().decode([MediaAttachment].self, from: Data("""
        [{"id":"1","type":"audio"},{"id":"2","type":"unknown"}]
        """.utf8))
        #expect(DiscoverMediaGrid.Media.image.index(in: attachments) == nil)
        #expect(DiscoverMediaGrid.Media.video.index(in: attachments) == nil)
    }
}
