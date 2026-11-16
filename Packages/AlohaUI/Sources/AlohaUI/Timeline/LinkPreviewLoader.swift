// SPDX-License-Identifier: MIT

import SwiftUI

#if os(macOS)
    import LinkPresentation
    import UniformTypeIdentifiers

    /// The picture a page offers for itself, fetched from that page, for a
    /// link card the server sent without one.
    ///
    /// Only when the reader has asked for it (`MacOptions.linkPreviewsKey`):
    /// the request goes to the site the link leads to, which learns an
    /// address and a time, and a timeline should not make that call on a
    /// reader's behalf. Kept for the life of the process, so a card scrolled
    /// past twice asks once.
    @MainActor
    final class LinkPreviewLoader {
        static let shared = LinkPreviewLoader()

        private var images: [URL: Image] = [:]
        private var failed: Set<URL> = []

        func image(for url: URL) async -> Image? {
            if let image = images[url] { return image }
            if failed.contains(url) { return nil }
            guard let data = await Self.pictureData(for: url), let picture = NSImage(data: data)
            else {
                failed.insert(url)
                return nil
            }
            let image = Image(nsImage: picture)
            images[url] = image
            return image
        }

        private static func pictureData(for url: URL) async -> Data? {
            let provider = LPMetadataProvider()
            provider.timeout = 8
            guard let metadata = try? await provider.startFetchingMetadata(for: url),
                let item = metadata.imageProvider ?? metadata.iconProvider
            else { return nil }
            return await withCheckedContinuation { continuation in
                _ = item.loadDataRepresentation(for: UTType.image) { data, _ in
                    continuation.resume(returning: data)
                }
            }
        }
    }
#endif
