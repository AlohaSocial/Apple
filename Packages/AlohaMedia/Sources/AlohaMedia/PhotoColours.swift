// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation

/// The few colours a photograph is mostly made of, for tinting the screen
/// around it the way Music tints its player around the album art.
///
/// Only ever taken from pixels the app already holds: the bytes the image
/// loader cached on disk when the picture was drawn, or the post's blurhash,
/// which arrived with the post. A tint is a decoration, and nothing is
/// downloaded for one — a thread opened offline, or before its picture has
/// arrived, takes its colours from the blurhash or goes without.
///
/// The work is a 24-pixel thumbnail and a 512-bucket histogram, done off the
/// main actor and remembered per picture, so opening the same post twice
/// costs one dictionary lookup.
public nonisolated struct PhotoColours: Sendable, Hashable {
    /// One colour and how much of the picture it covers, 0…1.
    public struct Swatch: Sendable, Hashable {
        public var red: Double
        public var green: Double
        public var blue: Double
        public var weight: Double

        public init(red: Double, green: Double, blue: Double, weight: Double) {
            self.red = red
            self.green = green
            self.blue = blue
            self.weight = weight
        }
    }

    /// Most prominent first; never empty.
    public let swatches: [Swatch]

    public init?(swatches: [Swatch]) {
        guard !swatches.isEmpty else { return nil }
        self.swatches = swatches
    }

    // MARK: - From pixels

    /// The side the picture is shrunk to before counting. Colour, not
    /// detail, is the question, and 576 pixels answer it.
    static let sampleSide = 24

    /// The main colours of `image`, at most `maximum`, distinct from each
    /// other.
    ///
    /// Buckets are ranked by how much of the picture they cover, nudged
    /// towards the colourful: a portrait on a white wall should tint by the
    /// face and the jumper as well as by the wall. A picture that really is
    /// grey stays grey — the nudge only reorders, it never invents a hue.
    public static func extract(from image: CGImage, maximum: Int = 3) -> PhotoColours? {
        let side = sampleSide
        guard let pixels = rgbaPixels(of: image, side: side) else { return nil }
        return extract(rgba: pixels, maximum: maximum)
    }

    /// The same, from raw RGBA8 bytes: what `extract(from:)` draws the
    /// thumbnail into, and what the tests hand in directly.
    static func extract(rgba pixels: [UInt8], maximum: Int = 3) -> PhotoColours? {
        guard maximum > 0, pixels.count >= 4 else { return nil }

        // 3 bits per channel: 512 buckets, coarse enough that one colour in a
        // photograph lands in one or two of them.
        var sums = [SIMD4<Double>](repeating: .zero, count: 512)
        var counted = 0
        var index = 0
        while index + 3 < pixels.count {
            let alpha = pixels[index + 3]
            if alpha > 127 {
                let red = Int(pixels[index])
                let green = Int(pixels[index + 1])
                let blue = Int(pixels[index + 2])
                let bucket = (red >> 5) << 6 | (green >> 5) << 3 | (blue >> 5)
                sums[bucket] += SIMD4(Double(red), Double(green), Double(blue), 1)
                counted += 1
            }
            index += 4
        }
        guard counted > 0 else { return nil }

        struct Candidate {
            var red, green, blue, weight, score: Double
        }
        var candidates: [Candidate] = []
        for sum in sums where sum.w > 0 {
            let red = sum.x / sum.w / 255
            let green = sum.y / sum.w / 255
            let blue = sum.z / sum.w / 255
            let weight = sum.w / Double(counted)
            let score = weight * (0.35 + saturation(red, green, blue))
            candidates.append(
                Candidate(red: red, green: green, blue: blue, weight: weight, score: score))
        }
        candidates.sort { $0.score > $1.score }

        // Neighbouring buckets of one colour are folded into the one already
        // chosen, so three swatches are three colours rather than one colour
        // three times.
        var chosen: [Candidate] = []
        for candidate in candidates {
            if let near = chosen.firstIndex(where: {
                distance(
                    ($0.red, $0.green, $0.blue), (candidate.red, candidate.green, candidate.blue))
                    < 0.25
            }) {
                chosen[near].weight += candidate.weight
            } else if chosen.count < maximum {
                chosen.append(candidate)
            }
        }
        return PhotoColours(
            swatches: chosen.map {
                Swatch(red: $0.red, green: $0.green, blue: $0.blue, weight: min($0.weight, 1))
            })
    }

    /// The colours of a blurhash: the placeholder decoded small and counted
    /// as a picture would be. A blurhash is the photograph with the detail
    /// taken out, which is exactly what a tint wants.
    public static func extract(blurhash: String) -> PhotoColours? {
        guard let image = BlurHash.decode(blurhash, size: CGSize(width: 8, height: 8)) else {
            return nil
        }
        return extract(from: image)
    }

    // MARK: - Without downloading

    /// The colours of a picture the app has already fetched — any of `urls`,
    /// in order, as the image loader cached it — or else of its blurhash.
    /// `nil` when there is neither: never a network request.
    @concurrent
    public static func cached(imageURLs urls: [URL], blurhash: String?) async -> PhotoColours? {
        let key = urls.first?.absoluteString ?? blurhash ?? ""
        if !key.isEmpty, let hit = memory.colours(for: key) { return hit }

        for url in urls {
            // The disk cache, read straight to a thumbnail: the bytes of
            // whatever size the row or the viewer drew.
            if let image = ImageLoader.cachedImage(for: url, maxPixels: 64),
                let colours = extract(from: image)
            {
                if !key.isEmpty { memory.store(colours, for: key) }
                return colours
            }
        }
        // Not remembered: next time the photograph itself may have arrived,
        // and its own colours are the better answer.
        return blurhash.flatMap { extract(blurhash: $0) }
    }

    private static let memory = Memory()

    /// `@unchecked` because its only state is an `NSCache`, which is
    /// thread-safe by contract but not annotated `Sendable`.
    private final class Memory: @unchecked Sendable {
        private let cache: NSCache<NSString, Box> = {
            let cache = NSCache<NSString, Box>()
            cache.countLimit = 200
            return cache
        }()

        final class Box: NSObject, @unchecked Sendable {
            let colours: PhotoColours
            init(_ colours: PhotoColours) { self.colours = colours }
        }

        func colours(for key: String) -> PhotoColours? {
            cache.object(forKey: key as NSString)?.colours
        }

        func store(_ colours: PhotoColours, for key: String) {
            cache.setObject(Box(colours), forKey: key as NSString)
        }
    }

    // MARK: - Arithmetic

    private static func rgbaPixels(of image: CGImage, side: Int) -> [UInt8]? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                    bytesPerRow: side * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? pixels : nil
    }

    static func saturation(_ red: Double, _ green: Double, _ blue: Double) -> Double {
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        guard high > 0 else { return 0 }
        return (high - low) / high
    }

    private static func distance(
        _ a: (Double, Double, Double), _ b: (Double, Double, Double)
    ) -> Double {
        let red = a.0 - b.0
        let green = a.1 - b.1
        let blue = a.2 - b.2
        return (red * red + green * green + blue * blue).squareRoot()
    }
}
