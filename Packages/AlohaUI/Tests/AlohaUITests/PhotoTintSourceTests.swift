// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import Foundation
import SwiftUI
import Testing

@testable import AlohaUI

@Suite("Which photograph tints a thread, and when it may not")
struct PhotoTintSourceTests {

    private let author = Account(id: "1", username: "alice", acct: "alice")

    private func photo(_ id: String = "m1") -> MediaAttachment {
        MediaAttachment(
            id: id, type: .image, url: URL(string: "https://example.test/\(id).jpg"),
            previewURL: URL(string: "https://example.test/\(id)-small.jpg"),
            blurhash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj")
    }

    private func post(
        media: [MediaAttachment], spoiler: String = "", sensitive: Bool = false
    ) -> Status {
        Status(
            id: "s", spoilerText: spoiler, sensitive: sensitive, account: author,
            mediaAttachments: media)
    }

    @Test("A photo post's first picture is the source")
    func photoPost() {
        let status = post(media: [photo("a"), photo("b")])
        #expect(PhotoTintSource.attachment(of: status, policy: .blur)?.id == "a")
    }

    @Test("A boost is tinted by the post it boosts")
    func boost() {
        let inner = post(media: [photo("a")])
        let wrapper = Status(id: "w", account: author, reblog: Box(inner))
        #expect(PhotoTintSource.attachment(of: wrapper, policy: .blur)?.id == "a")
    }

    @Test("A video or a text post has nothing to tint with")
    func notAPhoto() {
        let video = MediaAttachment(id: "v", type: .video)
        #expect(PhotoTintSource.attachment(of: post(media: [video]), policy: .showAll) == nil)
        #expect(PhotoTintSource.attachment(of: post(media: []), policy: .showAll) == nil)
    }

    @Test("A picture behind a content warning gives nothing away")
    func contentWarning() {
        let status = post(media: [photo()], spoiler: "eye strain")
        #expect(PhotoTintSource.attachment(of: status, policy: .showAll) == nil)
    }

    @Test("A sensitive picture tints only where the reader shows all")
    func sensitive() {
        let status = post(media: [photo()], sensitive: true)
        #expect(PhotoTintSource.attachment(of: status, policy: .blur) == nil)
        #expect(PhotoTintSource.attachment(of: status, policy: .hideAll) == nil)
        #expect(PhotoTintSource.attachment(of: status, policy: .showAll) != nil)
    }

    @Test("Reduce Transparency, Increase Contrast and the high-contrast themes keep the palette")
    func accessibilityFallsBack() {
        #expect(PhotoTintSource.allows(reduceTransparency: false, contrast: .standard))
        #expect(!PhotoTintSource.allows(reduceTransparency: true, contrast: .standard))
        #expect(!PhotoTintSource.allows(reduceTransparency: false, contrast: .increased))
        #expect(
            !PhotoTintSource.allows(
                reduceTransparency: false, contrast: .standard, theme: .highContrastDark))
        #expect(
            PhotoTintSource.allows(reduceTransparency: false, contrast: .standard, theme: .warmDark)
        )
    }

    @Test("The cached addresses are tried drawn-size first, without repeats")
    func cachedURLs() {
        let urls = PhotoTintSource.cachedURLs(for: photo("a"))
        #expect(urls.map(\.lastPathComponent) == ["a-small.jpg", "a.jpg"])
    }
}
