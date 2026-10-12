// SPDX-License-Identifier: MIT

import AVFoundation
import AlohaModels
import CoreGraphics
import Foundation
import ImageIO
import OSLog
import Observation
import UniformTypeIdentifiers

/// What the composer checks before a byte leaves the device.
///
/// Pre-flight against the server's own limits produces an explanation the
/// person can act on, rather than a 422 they have to interpret (docs/07 §4).
public enum UploadPreflight {

    public enum Verdict: Sendable, Hashable {
        case ready(mimeType: String)
        /// Convertible: the server does not take this type, but a transcode
        /// would produce one it does.
        case needsTranscode(from: String, to: String)
        case tooLarge(size: Int, limit: Int, isVideo: Bool)
        case unsupported(mimeType: String)
    }

    public static func check(
        fileSize: Int, mimeType: String, limits: ServerLimits
    ) -> Verdict {
        let isVideo = mimeType.hasPrefix("video/")
        let limit = limits.sizeLimit(forMIMEType: mimeType)

        if !limits.accepts(mimeType: mimeType) {
            // HEIC and ProRAW are transcoded to JPEG unless the server takes
            // them; a Live Photo posts as its still.
            if let target = transcodeTarget(for: mimeType), limits.accepts(mimeType: target) {
                return .needsTranscode(from: mimeType, to: target)
            }
            return .unsupported(mimeType: mimeType)
        }

        if fileSize > limit {
            return .tooLarge(size: fileSize, limit: limit, isVideo: isVideo)
        }
        return .ready(mimeType: mimeType)
    }

    static func transcodeTarget(for mimeType: String) -> String? {
        switch mimeType {
        case "image/heic", "image/heif", "image/tiff", "image/x-adobe-dng": "image/jpeg"
        case "video/quicktime", "video/x-m4v": "video/mp4"
        default: nil
        }
    }

    /// The message shown in the composer. Names the ceiling, because "too
    /// large" without a number is not actionable.
    public static func explanation(for verdict: Verdict) -> String? {
        switch verdict {
        case .ready:
            return nil
        case .needsTranscode:
            return String(
                localized: "This will be converted before it's posted.",
                comment: "Upload pre-flight notice")
        case .tooLarge(_, let limit, let isVideo):
            let formatted = limit.formatted(.byteCount(style: .file))
            return isVideo
                ? String(
                    localized: "Videos on your server have to be under \(formatted).",
                    comment: "Upload too large")
                : String(
                    localized: "Images on your server have to be under \(formatted).",
                    comment: "Upload too large")
        case .unsupported:
            return String(
                localized: "Your server doesn't accept this kind of file.",
                comment: "Upload unsupported type")
        }
    }
}

/// Prepares bytes for upload: transcoding, downscaling and trimming.
public struct MediaPreparer: Sendable {
    private let logger = Logger(subsystem: "com.nextcloud.alohasocial", category: "media")

    public init() {}

    public struct Prepared: Sendable {
        public var data: Data
        public var filename: String
        public var mimeType: String

        public init(data: Data, filename: String, mimeType: String) {
            self.data = data
            self.filename = filename
            self.mimeType = mimeType
        }
    }

    public enum Quality: String, Sendable, CaseIterable, Identifiable {
        case original, high, medium

        public var id: String { rawValue }

        public var maximumPixelSize: CGFloat? {
            switch self {
            case .original: nil
            case .high: 2048
            case .medium: 1280
            }
        }

        public var exportPreset: String {
            switch self {
            case .original: AVAssetExportPresetHighestQuality
            case .high: AVAssetExportPreset1920x1080
            case .medium: AVAssetExportPreset1280x720
            }
        }
    }

    /// Re-encodes an image to JPEG at a bounded size. `nil` maximum keeps the
    /// original dimensions and only changes the container.
    public func prepareImage(
        _ data: Data, filename: String, quality: Quality = .high, compression: CGFloat = 0.85
    ) -> Prepared? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let maximum = quality.maximumPixelSize {
            options[kCGImageSourceThumbnailMaxPixelSize] = maximum
        }

        let image =
            (quality.maximumPixelSize != nil
                ? CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                : CGImageSourceCreateImageAtIndex(source, 0, nil))
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)

        guard let image else { return nil }

        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }

        CGImageDestinationAddImage(
            destination, image,
            [kCGImageDestinationLossyCompressionQuality: compression] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }

        let base = (filename as NSString).deletingPathExtension
        return Prepared(
            data: output as Data, filename: "\(base).jpg", mimeType: "image/jpeg")
    }

    /// Trims and re-encodes a video. A file that cannot be brought under the
    /// ceiling is refused with the ceiling stated, rather than uploaded and
    /// rejected by the server.
    public func prepareVideo(
        at url: URL, trim: ClosedRange<Double>? = nil, quality: Quality = .high
    ) async throws -> Prepared {
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: quality.exportPreset)
        else { throw PreparationError.cannotExport }

        if let trim {
            let start = CMTime(seconds: trim.lowerBound, preferredTimescale: 600)
            let end = CMTime(seconds: trim.upperBound, preferredTimescale: 600)
            export.timeRange = CMTimeRange(start: start, end: end)
        }

        let output = FileManager.default.temporaryDirectory
            .appending(path: "aloha-\(UUID().uuidString).mp4")

        try await export.export(to: output, as: .mp4)
        let data = try Data(contentsOf: output)
        try? FileManager.default.removeItem(at: output)

        return Prepared(
            data: data,
            filename: url.lastPathComponent.replacingOccurrences(
                of: url.pathExtension, with: "mp4"),
            mimeType: "video/mp4")
    }

    public enum PreparationError: Error, Sendable {
        case cannotExport
        case cannotReduceBelowLimit(limit: Int)
    }

    public func mimeType(for url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
    }
}

/// Progress for a batch of uploads, shared with the Live Activity.
@Observable
public final class UploadProgress: @unchecked Sendable {
    public struct Item: Sendable, Hashable, Identifiable {
        public var id: UUID
        public var filename: String
        public var fractionCompleted: Double
        public var isFinished: Bool
        public var failed: Bool

        public init(
            id: UUID = UUID(), filename: String, fractionCompleted: Double = 0,
            isFinished: Bool = false, failed: Bool = false
        ) {
            self.id = id
            self.filename = filename
            self.fractionCompleted = fractionCompleted
            self.isFinished = isFinished
            self.failed = failed
        }
    }

    public private(set) var items: [Item] = []

    public init() {}

    public var overallFraction: Double {
        guard !items.isEmpty else { return 0 }
        return items.reduce(0) { $0 + $1.fractionCompleted } / Double(items.count)
    }

    public var isFinished: Bool { !items.isEmpty && items.allSatisfy(\.isFinished) }

    public func begin(_ filename: String) -> UUID {
        let item = Item(filename: filename)
        items.append(item)
        return item.id
    }

    public func update(_ id: UUID, fraction: Double) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].fractionCompleted = fraction
    }

    public func finish(_ id: UUID, failed: Bool = false) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].fractionCompleted = 1
        items[index].isFinished = true
        items[index].failed = failed
    }

    public func reset() { items = [] }
}
