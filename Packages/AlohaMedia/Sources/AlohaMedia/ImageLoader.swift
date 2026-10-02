// SPDX-License-Identifier: MIT

import CoreGraphics
import CryptoKit
import AlohaNetwork
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// Two-tier image cache: memory by URL and target size, disk in the app group
/// with an LRU ceiling. Downsamples at decode time — a full-size bitmap is
/// never held for a list cell (docs/01 §3).
public actor ImageLoader {
    public static let shared = ImageLoader()

    private let memory = NSCache<NSString, CGImageBox>()
    private let session: URLSession
    private let diskDirectory: URL?
    private let diskCeiling: Int
    private var inFlight: [String: Task<CGImage?, Never>] = [:]
    private let logger = Logger(subsystem: "com.nextcloud.alohasocial", category: "images")

    public init(
        session: URLSession = URLSession(configuration: .imageLoading),
        diskCeiling: Int = 512 * 1024 * 1024
    ) {
        self.session = session
        self.diskCeiling = diskCeiling
        memory.totalCostLimit = 96 * 1024 * 1024

        let groupBase =
            AppGroup.isEnabled
            ? FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppGroup.identifier)
            : nil
        let base = groupBase
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first

        diskDirectory = base?.appending(path: "ImageCache")
        if let diskDirectory {
            try? FileManager.default.createDirectory(
                at: diskDirectory, withIntermediateDirectories: true)
        }
    }

    final class CGImageBox: NSObject, @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    /// Warms the cache for rows about to arrive, and cancels what is no longer
    /// coming (docs/05 §3). Without this a scroll shows a blurhash for every
    /// row and then a pop, which is most of why a timeline feels slow.
    private var prefetching: [String: Task<Void, Never>] = [:]

    public func prefetch(_ urls: [URL], targetSize: CGSize) {
        for url in urls {
            let key = cacheKey(url: url, targetSize: targetSize)
            guard memory.object(forKey: key as NSString) == nil,
                inFlight[key] == nil,
                prefetching[key] == nil
            else { continue }

            prefetching[key] = Task(priority: .utility) { [weak self] in
                _ = await self?.image(for: url, targetSize: targetSize)
                await self?.finishPrefetch(key)
            }
        }
    }

    /// Called on a scroll-direction change: whatever was being fetched for rows
    /// now moving away is no longer worth the bandwidth.
    public func cancelPrefetch(_ urls: [URL], targetSize: CGSize) {
        for url in urls {
            let key = cacheKey(url: url, targetSize: targetSize)
            prefetching.removeValue(forKey: key)?.cancel()
        }
    }

    private func finishPrefetch(_ key: String) {
        prefetching.removeValue(forKey: key)
    }

    public func image(for url: URL, targetSize: CGSize) async -> CGImage? {
        let key = cacheKey(url: url, targetSize: targetSize)

        if let cached = memory.object(forKey: key as NSString) { return cached.image }
        if let existing = inFlight[key] { return await existing.value }

        let task = Task<CGImage?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.load(url: url, targetSize: targetSize, key: key)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    private func load(url: URL, targetSize: CGSize, key: String) async -> CGImage? {
        if let data = readFromDisk(key: key), let image = downsample(data, to: targetSize) {
            store(image, forKey: key)
            return image
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 20
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
            else { return nil }

            guard let image = downsample(data, to: targetSize) else { return nil }
            // Only persist bytes ImageIO actually accepted. Error pages and
            // mislabeled media otherwise poison the custom cache until it is
            // manually cleared.
            writeToDisk(data, key: key)
            store(image, forKey: key)
            return image
        } catch {
            logger.debug(
                "image request failed for \(url.host() ?? "unknown", privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Decode straight to the size that will be drawn. This is the single
    /// biggest lever on memory in a scrolling list.
    private nonisolated func downsample(_ data: Data, to targetSize: CGSize) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let maximumDimension = max(targetSize.width, targetSize.height) * 2
        let options =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
            ] as CFDictionary

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
            ?? CGImageSourceCreateImageAtIndex(source, 0, sourceOptions)
    }

    private func store(_ image: CGImage, forKey key: String) {
        let cost = image.bytesPerRow * image.height
        memory.setObject(CGImageBox(image), forKey: key as NSString, cost: cost)
    }

    private func cacheKey(url: URL, targetSize: CGSize) -> String {
        // Swift's Hashable seed intentionally changes for every process. A
        // SHA-256 filename stays valid after the next app launch.
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(digest)-\(Int(targetSize.width.rounded(.up)))x\(Int(targetSize.height.rounded(.up)))"
    }

    // MARK: - Disk

    private func diskURL(key: String) -> URL? {
        diskDirectory?.appending(path: key.replacingOccurrences(of: "/", with: "_"))
    }

    private func readFromDisk(key: String) -> Data? {
        guard let url = diskURL(key: key) else { return nil }
        return try? Data(contentsOf: url)
    }

    private func writeToDisk(_ data: Data, key: String) {
        guard let url = diskURL(key: key) else { return }
        try? data.write(to: url, options: .atomic)
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
