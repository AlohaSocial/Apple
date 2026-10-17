// SPDX-License-Identifier: MIT

import Testing
import UniformTypeIdentifiers

@testable import AlohaUI

@Suite("What a share extension uploads")
struct SharedItemTypeTests {
    @Test("A TIFF-first Mac image goes up as the PNG it also offers")
    func skipsTIFF() {
        let picked = SharedItemType.pick(
            from: [UTType.tiff.identifier, UTType.png.identifier],
            preferring: SharedItemType.uploadableImages)
        #expect(picked == .png)
    }

    @Test("The preference order decides, not the order the source registered")
    func preferenceOrder() {
        let picked = SharedItemType.pick(
            from: [UTType.png.identifier, UTType.jpeg.identifier],
            preferring: SharedItemType.uploadableImages)
        #expect(picked == .jpeg)
    }

    @Test("Only a type that needs converting picks nothing")
    func onlyTIFF() {
        #expect(
            SharedItemType.pick(
                from: [UTType.tiff.identifier], preferring: SharedItemType.uploadableImages)
                == nil)
    }

    @Test("A QuickTime movie is accepted as itself")
    func quickTime() {
        let picked = SharedItemType.pick(
            from: [UTType.quickTimeMovie.identifier],
            preferring: SharedItemType.uploadableMovies)
        #expect(picked == .quickTimeMovie)
    }

    @Test("Uploads are named for their real type")
    func naming() {
        let upload = SharedItemType.upload(for: .png)
        #expect(upload.mimeType == "image/png")
        #expect(upload.filename.hasSuffix(".png"))
    }
}
