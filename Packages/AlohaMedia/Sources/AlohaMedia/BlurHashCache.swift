// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation

/// Decoded blurhash placeholders, by hash.
///
/// A blurhash is cheap to decode once and pointless to decode twice: the same
/// avatar or picture comes back every time its row scrolls into view. The
/// decode runs off the main actor — a row used to decode its placeholder in
/// `body`'s task on the main thread, once per appearance.
///
/// `@unchecked` because its only state is an `NSCache`, which is thread-safe
/// by contract but not annotated `Sendable`.
public final class BlurHashCache: @unchecked Sendable {
    public static let shared = BlurHashCache()

    /// The size a placeholder is decoded at. It is drawn stretched and
    /// blurred, so more pixels buy nothing.
    public static let placeholderSize = CGSize(width: 24, height: 24)

    private let cache: NSCache<NSString, Box>

    final class Box: NSObject, @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    public init(countLimit: Int = 600) {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = countLimit
        self.cache = cache
    }

    /// A placeholder already decoded, without waiting — what a row paints in
    /// its first frame when the hash has been seen before.
    public func cached(_ hash: String) -> CGImage? {
        cache.object(forKey: hash as NSString)?.image
    }

    public func placeholder(for hash: String) async -> CGImage? {
        if let hit = cached(hash) { return hit }
        guard let image = await Self.decode(hash) else { return nil }
        cache.setObject(Box(image), forKey: hash as NSString)
        return image
    }

    @concurrent
    private static func decode(_ hash: String) async -> CGImage? {
        BlurHash.decode(hash, size: placeholderSize)
    }
}
