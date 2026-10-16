// SPDX-License-Identifier: MIT

import AlohaModels
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import AlohaUI

@Suite("Memories widget snapshot")
@MainActor
struct MemoriesWidgetTests {
    private let author = Account(id: "1", username: "ana", acct: "ana", displayName: "Ana")

    private func status(
        _ id: String, year: Int, content: String = "<p>At the sea</p>", spoiler: String = "",
        sensitive: Bool = false, media: [MediaAttachment] = []
    ) -> Status {
        let date =
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: year, month: 10, day: 16, hour: 12)) ?? Date()
        return Status(
            id: id, createdAt: date, content: content, spoilerText: spoiler, sensitive: sensitive,
            account: author, mediaAttachments: media)
    }

    private func picture(_ name: String) -> MediaAttachment {
        MediaAttachment(
            id: name, type: .image, url: URL(string: "https://example.com/\(name).jpg"),
            previewURL: URL(string: "https://example.com/\(name)-small.jpg"))
    }

    @Test("Newest first, as many as the largest widget shows, in plain text")
    func newestFirstPlainText() {
        let memories = MemoriesWidgetWriter.memories(
            from: (2018...2024).map { status("\($0)", year: $0) })
        #expect(memories.map(\.id) == ["2024", "2023", "2022", "2021"])
        #expect(memories.first?.text == "At the sea")
        #expect(memories.first?.author == "Ana")
    }

    @Test("A post behind a warning shows its warning, not its words")
    func contentWarningReplacesText() {
        let memories = MemoriesWidgetWriter.memories(
            from: [status("1", year: 2020, content: "<p>secret</p>", spoiler: "Food")])
        #expect(memories.first?.text == "Food")
    }

    @Test("The picture is the preview, and never one behind a warning")
    func pictureRespectsWarnings() {
        let open = status("1", year: 2020, media: [picture("a")])
        let sensitive = status("2", year: 2020, sensitive: true, media: [picture("b")])
        let warned = status("3", year: 2020, spoiler: "CW", media: [picture("c")])
        let video = status(
            "4", year: 2020, media: [MediaAttachment(id: "v", type: .video)])

        #expect(
            MemoriesWidgetWriter.pictureURL(of: open)?.absoluteString
                == "https://example.com/a-small.jpg")
        #expect(MemoriesWidgetWriter.pictureURL(of: sensitive) == nil)
        #expect(MemoriesWidgetWriter.pictureURL(of: warned) == nil)
        #expect(MemoriesWidgetWriter.pictureURL(of: video) == nil)
    }

    @Test("A large picture is shrunk to a widget-sized JPEG")
    func shrinksPictures() throws {
        let large = try #require(Self.png(width: 2000, height: 1000))
        let small = try #require(MemoriesWidgetWriter.jpeg(from: large))
        let source = try #require(CGImageSourceCreateWithData(small as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(CGFloat(max(image.width, image.height)) <= MemoriesWidgetWriter.thumbnailPixels)
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
    }

    @Test("The widget's link opens Memories")
    func memoriesLink() throws {
        let url = try #require(URL(string: "alohasocial://memories"))
        #expect(RouteResolver.route(for: url) == .memories)
    }

    private static func png(width: Int, height: Int) -> Data? {
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
