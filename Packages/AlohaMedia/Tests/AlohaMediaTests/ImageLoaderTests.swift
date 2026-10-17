// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import Testing
import UniformTypeIdentifiers

@testable import AlohaMedia

@Suite("Image loader sizes")
struct ImageLoaderSizeTests {

    @Test("A request is rounded up to the next pixel bucket at the screen's scale")
    func bucketsFollowScale() {
        let avatar = CGSize(width: 46, height: 46)
        #expect(ImageLoader.pixelBucket(for: avatar, scale: 2) == 96)
        #expect(ImageLoader.pixelBucket(for: avatar, scale: 3) == 192)
        // A 3× phone gets 3× pixels: the bucket is never below what is drawn.
        #expect(ImageLoader.pixelBucket(for: CGSize(width: 300, height: 200), scale: 3) == 1024)
    }

    @Test("Nothing is decoded for a size measured before layout")
    func zeroSizeIsNothing() {
        #expect(ImageLoader.pixelBucket(for: .zero, scale: 3) == nil)
        #expect(ImageLoader.pixelBucket(for: CGSize(width: 10, height: 10), scale: 0) == nil)
    }

    /// The point of the buckets: a prefetch that guessed a slightly different
    /// size than the row later measured still lands in the row's entry.
    @Test("A prefetch and a row a few points apart share one cache entry")
    func nearbySizesShareAKey() {
        let prefetched = ImageLoader.pixelBucket(for: CGSize(width: 300, height: 300), scale: 3)
        let measured = ImageLoader.pixelBucket(for: CGSize(width: 312, height: 280), scale: 3)
        #expect(prefetched == measured)
    }

    @Test("Beyond the table, sizes step by 512 pixels")
    func largeSizes() {
        #expect(ImageLoader.pixelBucket(for: CGSize(width: 1000, height: 800), scale: 3) == 3072)
    }
}

@Suite("Image loader loading", .serialized)
struct ImageLoaderLoadingTests {

    private func makeLoader() -> (ImageLoader, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ImageLoaderTests-\(UUID().uuidString)")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CountingImageProtocol.self]
        let loader = ImageLoader(
            session: URLSession(configuration: configuration), diskDirectory: directory)
        return (loader, directory)
    }

    @Test("Concurrent requests for one image and size make one network request")
    func concurrentRequestsCoalesce() async throws {
        let (loader, directory) = makeLoader()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = URL(string: "https://images.test/coalesce-\(UUID().uuidString).png")!
        let size = CGSize(width: 40, height: 40)

        async let first = loader.image(for: url, targetSize: size, scale: 2)
        async let second = loader.image(for: url, targetSize: size, scale: 2)
        async let third = loader.image(for: url, targetSize: size, scale: 2)
        let results = await [first, second, third]

        #expect(results.allSatisfy { $0 != nil })
        #expect(CountingImageProtocol.requests(for: url) == 1)
    }

    @Test("A larger decode in memory answers a smaller request without a fetch")
    func largerDecodeServesSmaller() async throws {
        let (loader, directory) = makeLoader()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = URL(string: "https://images.test/reuse-\(UUID().uuidString).png")!

        _ = await loader.image(for: url, targetSize: CGSize(width: 200, height: 200), scale: 2)
        let small = await loader.image(
            for: url, targetSize: CGSize(width: 40, height: 40), scale: 2)

        #expect(small != nil)
        #expect(CountingImageProtocol.requests(for: url) == 1)
    }

    @Test("Once in memory, an image is there without waiting")
    func memoryPeek() async throws {
        let (loader, directory) = makeLoader()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = URL(string: "https://images.test/peek-\(UUID().uuidString).png")!
        let size = CGSize(width: 64, height: 64)

        #expect(loader.memoryImage(for: url, targetSize: size, scale: 2) == nil)
        _ = await loader.image(for: url, targetSize: size, scale: 2)
        #expect(loader.memoryImage(for: url, targetSize: size, scale: 2) != nil)
    }

    @Test("The decode is no larger than the bucket asked for")
    func decodeIsBounded() async throws {
        let (loader, directory) = makeLoader()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = URL(string: "https://images.test/bounded-\(UUID().uuidString).png")!

        let image = await loader.image(
            for: url, targetSize: CGSize(width: 20, height: 20), scale: 2)
        let decoded = try #require(image)
        #expect(max(decoded.width, decoded.height) <= 64)
    }
}

/// Serves one 256×256 PNG for every request and counts requests per URL.
final class CountingImageProtocol: URLProtocol {
    private static let counts = Mutex<[URL: Int]>([:])

    static func requests(for url: URL) -> Int {
        counts.withLock { $0[url] ?? 0 }
    }

    static let png: Data = {
        let side = 256
        guard
            let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return Data() }
        context.setFillColor(CGColor(red: 0.9, green: 0.4, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        guard let image = context.makeImage() else { return Data() }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.png.identifier as CFString, 1, nil)
        else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.counts.withLock { $0[url, default: 0] += 1 }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"])
        if let response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: Self.png)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
