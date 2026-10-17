// SPDX-License-Identifier: MIT

import AlohaNetwork
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// Two-tier image cache: memory by URL and decoded pixel size, disk in the app
/// group with an LRU ceiling. Downsamples at decode time — a full-size bitmap
/// is never held for a list cell (docs/01 §3).
///
/// The actor only owns the bookkeeping: which decodes are in flight, which
/// sizes are in memory. Reading from disk, the network and the decode itself
/// run on the concurrent executor, so a screenful of rows decodes in parallel
/// instead of one image after another behind the actor.
public actor ImageLoader {
    public static let shared = ImageLoader()

    /// `nonisolated(unsafe)` so `memoryImage` can answer without a hop onto
    /// the actor: `NSCache` is thread-safe by contract, it is only not
    /// annotated `Sendable`.
    private nonisolated(unsafe) let memory = NSCache<NSString, CGImageBox>()
    private let session: URLSession
    private let diskDirectory: URL?
    private let diskCeiling: Int
    private var inFlight: [String: Task<CGImage?, Never>] = [:]
    /// The pixel buckets decoded per resource, so a request can be served by
    /// a larger decode that is already in memory — the avatar a profile
    /// header decoded at 256 px serves the 120 px row without a second decode.
    private var decodedBuckets: [String: Set<Int>] = [:]
    private let logger = Logger(subsystem: "social.aloha.app", category: "images")

    public init(
        session: URLSession = URLSession(configuration: .imageLoading),
        diskCeiling: Int = 512 * 1024 * 1024,
        diskDirectory: URL? = nil
    ) {
        self.session = session
        self.diskCeiling = diskCeiling
        memory.totalCostLimit = 96 * 1024 * 1024

        if let diskDirectory {
            self.diskDirectory = diskDirectory
        } else {
            let groupBase =
                AppGroup.isEnabled
                ? FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: AppGroup.identifier)
                : nil
            let base =
                groupBase
                ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            self.diskDirectory = base?.appending(path: "ImageCache")
        }
        if let directory = self.diskDirectory {
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        }
    }

    final class CGImageBox: NSObject, @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    // MARK: - Sizes

    /// The decode sizes, in pixels along the longer edge. A request is
    /// rounded **up** to one of these, so a row that measured 41 pt and the
    /// prefetch that guessed 40 pt share one decode, and nothing is ever
    /// drawn softer than the screen it is on.
    static let pixelBuckets = [32, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048]

    /// The bucket a request lands in, or nil for a size nothing can be drawn
    /// at yet (a view measured before layout reports 0×0).
    static func pixelBucket(for targetSize: CGSize, scale: CGFloat) -> Int? {
        let points = max(targetSize.width, targetSize.height)
        guard points > 0, scale > 0, points.isFinite else { return nil }
        let pixels = Int((points * scale).rounded(.up))
        if let bucket = pixelBuckets.first(where: { $0 >= pixels }) { return bucket }
        // Beyond the table (a full-screen photo on a large display): whole
        // steps of 512, still shared by everything within one step.
        return ((pixels + 511) / 512) * 512
    }

    static func cacheKey(resource: String, bucket: Int) -> String {
        "\(resource)-\(bucket)"
    }

    // MARK: - Prefetching

    /// Warms the cache for rows about to arrive, and cancels what is no longer
    /// coming (docs/05 §3). Without this a scroll shows a blurhash for every
    /// row and then a pop, which is most of why a timeline feels slow.
    private var prefetching: [String: Task<Void, Never>] = [:]

    public func prefetch(_ urls: [URL], targetSize: CGSize, scale: CGFloat = 2) {
        guard let bucket = Self.pixelBucket(for: targetSize, scale: scale) else { return }
        for url in urls {
            let resource = Self.resourceKey(url)
            let key = Self.cacheKey(resource: resource, bucket: bucket)
            guard cached(resource: resource, bucket: bucket) == nil,
                inFlight[key] == nil,
                prefetching[key] == nil
            else { continue }

            prefetching[key] = Task(priority: .utility) { [weak self] in
                _ = await self?.image(for: url, targetSize: targetSize, scale: scale)
                await self?.finishPrefetch(key)
            }
        }
    }

    /// Called on a scroll-direction change: whatever was being fetched for rows
    /// now moving away is no longer worth the bandwidth.
    public func cancelPrefetch(_ urls: [URL], targetSize: CGSize, scale: CGFloat = 2) {
        guard let bucket = Self.pixelBucket(for: targetSize, scale: scale) else { return }
        for url in urls {
            let key = Self.cacheKey(resource: Self.resourceKey(url), bucket: bucket)
            prefetching.removeValue(forKey: key)?.cancel()
        }
    }

    private func finishPrefetch(_ key: String) {
        prefetching.removeValue(forKey: key)
    }

    // MARK: - Loading

    /// The image for `url`, decoded for `targetSize` points at `scale`.
    ///
    /// Concurrent requests for the same resource and size share one load;
    /// a larger decode already in memory answers a smaller request.
    public func image(for url: URL, targetSize: CGSize, scale: CGFloat = 2) async -> CGImage? {
        guard let bucket = Self.pixelBucket(for: targetSize, scale: scale) else { return nil }
        let resource = Self.resourceKey(url)
        let key = Self.cacheKey(resource: resource, bucket: bucket)

        if let cached = cached(resource: resource, bucket: bucket) { return cached }
        if let existing = inFlight[key] { return await existing.value }

        let session = session
        let directory = diskDirectory
        let logger = logger
        let task = Task<CGImage?, Never>(priority: .userInitiated) {
            await Self.load(
                url: url, pixels: bucket, resource: resource, session: session,
                diskDirectory: directory, logger: logger)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { store(result, resource: resource, bucket: bucket) }
        return result
    }

    /// What memory already holds for exactly this size, without waiting.
    ///
    /// A row scrolling back into view asks this first, so an image it showed
    /// a moment ago is there in its first frame instead of fading in again
    /// behind the placeholder.
    public nonisolated func memoryImage(
        for url: URL, targetSize: CGSize, scale: CGFloat = 2
    ) -> CGImage? {
        guard let bucket = Self.pixelBucket(for: targetSize, scale: scale) else { return nil }
        let key = Self.cacheKey(resource: Self.resourceKey(url), bucket: bucket)
        return memory.object(forKey: key as NSString)?.image
    }

    /// Exact bucket first, then the smallest larger decode still in memory.
    private func cached(resource: String, bucket: Int) -> CGImage? {
        let exact = Self.cacheKey(resource: resource, bucket: bucket)
        if let hit = memory.object(forKey: exact as NSString) { return hit.image }
        guard let known = decodedBuckets[resource] else { return nil }
        for larger in known.sorted() where larger > bucket {
            let key = Self.cacheKey(resource: resource, bucket: larger)
            if let hit = memory.object(forKey: key as NSString) { return hit.image }
        }
        return nil
    }

    private func store(_ image: CGImage, resource: String, bucket: Int) {
        let cost = image.bytesPerRow * image.height
        let key = Self.cacheKey(resource: resource, bucket: bucket)
        memory.setObject(CGImageBox(image), forKey: key as NSString, cost: cost)
        decodedBuckets[resource, default: []].insert(bucket)
    }

    /// Disk, then network, then decode — all off the actor.
    @concurrent
    private static func load(
        url: URL, pixels: Int, resource: String, session: URLSession,
        diskDirectory: URL?, logger: Logger
    ) async -> CGImage? {
        // Original bytes are independent of the display size. A prefetched
        // image can therefore serve both an avatar and a larger profile view.
        let file = diskDirectory.map { diskURL(in: $0, resource: resource) }
        if let file, let data = try? Data(contentsOf: file),
            let image = downsample(data, maxPixels: pixels)
        {
            return image
        }
        guard !Task.isCancelled else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue(
                "image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 20
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
            else { return nil }

            guard let image = downsample(data, maxPixels: pixels) else { return nil }
            // Only persist bytes ImageIO actually accepted. Error pages and
            // mislabeled media otherwise poison the custom cache until it is
            // manually cleared.
            if let file { try? data.write(to: file, options: .atomic) }
            return image
        } catch {
            logger.debug(
                "image request failed for \(url.host() ?? "unknown", privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// Decode straight to the size that will be drawn. This is the single
    /// biggest lever on memory in a scrolling list.
    static func downsample(_ data: Data, maxPixels: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let options =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            ] as CFDictionary

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
            ?? CGImageSourceCreateImageAtIndex(source, 0, sourceOptions)
    }

    static func resourceKey(_ url: URL) -> String {
        // Swift's Hashable seed intentionally changes for every process. A
        // SHA-256 filename stays valid after the next app launch.
        SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    // MARK: - Disk

    private static func diskURL(in directory: URL, resource: String) -> URL {
        directory.appending(path: resource.replacingOccurrences(of: "/", with: "_"))
    }

    /// LRU eviction down to the ceiling. Runs in the maintenance background
    /// task, never on a launch path.
    public func evictDiskCacheIfNeeded() {
        guard let diskDirectory else { return }
        let manager = FileManager.default
        guard
            let entries = try? manager.contentsOfDirectory(
                at: diskDirectory,
                includingPropertiesForKeys: [.contentAccessDateKey, .fileSizeKey])
        else { return }

        var files = entries.compactMap { url -> (URL, Date, Int)? in
            guard
                let values = try? url.resourceValues(forKeys: [.contentAccessDateKey, .fileSizeKey])
            else { return nil }
            return (url, values.contentAccessDate ?? .distantPast, values.fileSize ?? 0)
        }

        var total = files.reduce(0) { $0 + $1.2 }
        guard total > diskCeiling else { return }

        files.sort { $0.1 < $1.1 }
        for file in files where total > diskCeiling {
            try? manager.removeItem(at: file.0)
            total -= file.2
        }
        logger.debug("image cache evicted to \(total, privacy: .public) bytes")
    }

    public func clear() {
        memory.removeAllObjects()
        decodedBuckets.removeAll()
        guard let diskDirectory else { return }
        try? FileManager.default.removeItem(at: diskDirectory)
        try? FileManager.default.createDirectory(
            at: diskDirectory, withIntermediateDirectories: true)
    }

    public func currentDiskSize() -> Int {
        guard let diskDirectory,
            let entries = try? FileManager.default.contentsOfDirectory(
                at: diskDirectory, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        return entries.reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }
}

extension URLSessionConfiguration {
    public static var imageLoading: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 0)
        configuration.httpMaximumConnectionsPerHost = 8
        configuration.timeoutIntervalForRequest = 20
        return configuration
    }
}
