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

/// Prepares bytes for upload: transcoding, downscaling and trimming, and
/// removing where a picture or a video was taken and who took it.
public struct MediaPreparer: Sendable {
    private let logger = Logger(subsystem: "social.aloha.app", category: "media")

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
    ///
    /// Only the pixels are carried over, so the result has no EXIF, GPS or
    /// IPTC metadata whatever the original had.
    public func prepareImage(
        _ data: Data, filename: String, quality: Quality = .high, compression: CGFloat = 0.85
    ) -> Prepared? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        // Always through the thumbnail call, which is the one that applies the
        // EXIF orientation: the new file carries no metadata to say which way
        // up it is, so a picture drawn as stored would arrive on its side.
        // "Original" asks for the picture's own longest side.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let longestSide = max(
            properties?[kCGImagePropertyPixelWidth] as? Int ?? 0,
            properties?[kCGImagePropertyPixelHeight] as? Int ?? 0)
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let maximum = quality.maximumPixelSize ?? (longestSide > 0 ? CGFloat(longestSide) : nil) {
            options[kCGImageSourceThumbnailMaxPixelSize] = maximum
        }

        let image =
            CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
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
    ///
    /// The export leaves out where the video was taken and who took it, as
    /// `removingPersonalMetadata(fromVideoAt:mimeType:progress:)` does.
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

        try await run(export, to: output, as: .mp4)
        defer { try? FileManager.default.removeItem(at: output) }
        // Mapped rather than read: the pages come from the file as the upload
        // is built, and stay readable after the file itself is removed.
        let data = try Data(contentsOf: output, options: .alwaysMapped)

        return Prepared(
            data: data,
            filename: url.lastPathComponent.replacingOccurrences(
                of: url.pathExtension, with: "mp4"),
            mimeType: "video/mp4")
    }

    /// A copy of the video at `url` without the place it was taken, the
    /// person who took it or anything else the camera wrote about them —
    /// QuickTime's `com.apple.quicktime.location.ISO6709` and its `udta`
    /// twin, MP4's `loci`, author and the like. Nothing is re-encoded: the
    /// streams are copied as they are into the same kind of container, so a
    /// long video costs about as long as copying the file.
    ///
    /// The copy is a new file in the temporary directory, which the caller
    /// removes once it has gone up. Nothing is left behind when the export
    /// fails or the task is cancelled. `progress` hears the fraction done.
    public func removingPersonalMetadata(
        fromVideoAt url: URL, mimeType: String,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        guard let fileType = Self.fileType(forVideoMIMEType: mimeType),
            let export = AVAssetExportSession(
                asset: AVURLAsset(url: url), presetName: AVAssetExportPresetPassthrough)
        else { throw PreparationError.cannotExport }

        let output = FileManager.default.temporaryDirectory
            .appending(path: "aloha-\(UUID().uuidString).\(url.pathExtension)")
        try await run(export, to: output, as: fileType, progress: progress)
        return output
    }

    /// The container a video is copied into when only its metadata changes:
    /// the one it came in, so its MIME type still describes it.
    static func fileType(forVideoMIMEType mimeType: String) -> AVFileType? {
        switch mimeType {
        case "video/mp4": .mp4
        case "video/quicktime": .mov
        case "video/x-m4v": .m4v
        default: nil
        }
    }

    /// Runs an export with the sharing filter, which drops location and
    /// personal items from the movie and its tracks and keeps what playback
    /// needs. It is honoured by the passthrough preset as well as by the
    /// transcoding ones; without it, both copy every item across.
    ///
    /// A cancelled export does not throw — it stops and writes nothing — so
    /// cancellation is checked afterwards, and a missing file is a failure.
    private func run(
        _ export: AVAssetExportSession, to output: URL, as fileType: AVFileType,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        export.metadataItemFilter = .forSharing()
        // The session is not Sendable, but its export and its state updates
        // are made to be awaited side by side; nothing else touches it here.
        nonisolated(unsafe) let session = export
        do {
            try await withThrowingTaskGroup { group in
                group.addTask { try await session.export(to: output, as: fileType) }
                if let progress {
                    group.addTask {
                        for await state in session.states(updateInterval: 0.25) {
                            if case .exporting(let done) = state {
                                progress(done.fractionCompleted)
                            }
                        }
                    }
                }
                try await group.next()
                group.cancelAll()
            }
            try Task.checkCancellation()
            guard FileManager.default.fileExists(atPath: output.path()) else {
                throw PreparationError.cannotExport
            }
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    /// The picture without the place it was taken, the person who took it
    /// or the serial numbers of the camera: GPS, IPTC, maker notes and the
    /// EXIF and TIFF fields that name someone are all gone, the orientation
    /// stays. A picture that carries none of that comes back untouched.
    ///
    /// A JPEG is copied without decoding, so it loses nothing; other kinds
    /// are redrawn in their own format. One whose format cannot be written
    /// (WebP) becomes a JPEG. `nil` when the bytes are not a picture.
    public func removingPersonalMetadata(
        fromImage data: Data, filename: String, mimeType: String
    ) -> Prepared? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let type = CGImageSourceGetType(source),
            CGImageSourceGetCount(source) > 0
        else { return nil }
        guard Self.carriesPersonalMetadata(source) else {
            return Prepared(data: data, filename: filename, mimeType: mimeType)
        }

        if UTType(type as String) == .jpeg,
            let copy = Self.copyWithoutMetadata(source, type: type),
            !Self.carriesPersonalMetadata(copy)
        {
            return Prepared(data: copy, filename: filename, mimeType: mimeType)
        }
        if let redrawn = Self.redrawWithoutMetadata(source, type: type),
            !Self.carriesPersonalMetadata(redrawn)
        {
            return Prepared(data: redrawn, filename: filename, mimeType: mimeType)
        }
        return prepareImage(data, filename: filename, quality: .original)
    }

    static func carriesPersonalMetadata(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return true }
        return carriesPersonalMetadata(source)
    }

    /// Whether any frame has a location, a person's name or a device's
    /// serial number in it. Exposure, colour and size are left alone; they
    /// say nothing about who or where.
    static func carriesPersonalMetadata(_ source: CGImageSource) -> Bool {
        let dictionaries: [CFString] = [
            kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary,
            kCGImagePropertyExifAuxDictionary, kCGImagePropertyMakerAppleDictionary,
            kCGImagePropertyMakerCanonDictionary, kCGImagePropertyMakerNikonDictionary,
            kCGImagePropertyMakerFujiDictionary, kCGImagePropertyMakerOlympusDictionary,
            kCGImagePropertyMakerPentaxDictionary, kCGImagePropertyMakerMinoltaDictionary,
        ]
        let fields: [(CFString, [CFString])] = [
            (
                kCGImagePropertyExifDictionary,
                [
                    kCGImagePropertyExifCameraOwnerName, kCGImagePropertyExifBodySerialNumber,
                    kCGImagePropertyExifLensSerialNumber, kCGImagePropertyExifImageUniqueID,
                ]
            ),
            (kCGImagePropertyTIFFDictionary, [kCGImagePropertyTIFFArtist, kCGImagePropertyTIFFHostComputer]),
            (kCGImagePropertyPNGDictionary, [kCGImagePropertyPNGAuthor]),
        ]
        return (0..<CGImageSourceGetCount(source)).contains { index in
            guard
                let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                    as? [CFString: Any]
            else { return false }
            if dictionaries.contains(where: { properties[$0] != nil }) { return true }
            return fields.contains { dictionary, keys in
                guard let values = properties[dictionary] as? [CFString: Any] else { return false }
                return keys.contains { values[$0] != nil }
            }
        }
    }

    /// A JPEG's compressed data copied into a new file whose only metadata
    /// is the orientation. Lossless, and no pixels are decoded.
    private static func copyWithoutMetadata(_ source: CGImageSource, type: CFString) -> Data? {
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, type, CGImageSourceGetCount(source), nil)
        else { return nil }
        let kept = CGImageMetadataCreateMutable()
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        if let orientation = properties?[kCGImagePropertyOrientation] {
            CGImageMetadataSetValueMatchingImageProperty(
                kept, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation,
                orientation as CFTypeRef)
        }
        let options: [CFString: Any] = [
            kCGImageDestinationMetadata: kept,
            kCGImageDestinationMergeMetadata: false,
            kCGImageMetadataShouldExcludeGPS: true,
            kCGImageMetadataShouldExcludeXMP: true,
        ]
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil)
        else { return nil }
        return output as Data
    }

    /// Every frame drawn again in its own format, with the metadata
    /// dictionaries removed and the orientation and frame timing kept.
    private static func redrawWithoutMetadata(_ source: CGImageSource, type: CFString) -> Data? {
        let count = CGImageSourceGetCount(source)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, count, nil)
        else { return nil }
        var removed: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: kCFNull as Any,
            kCGImagePropertyExifDictionary: kCFNull as Any,
            kCGImagePropertyExifAuxDictionary: kCFNull as Any,
            kCGImagePropertyIPTCDictionary: kCFNull as Any,
            kCGImagePropertyTIFFDictionary: kCFNull as Any,
            kCGImagePropertyMakerAppleDictionary: kCFNull as Any,
            kCGImageMetadataShouldExcludeGPS: true,
            kCGImageMetadataShouldExcludeXMP: true,
            kCGImageDestinationLossyCompressionQuality: 0.92,
        ]
        // A still PNG's text fields go with the rest; an animated one's
        // dictionary holds its frame timing, and stays.
        if count == 1 { removed[kCGImagePropertyPNGDictionary] = kCFNull as Any }
        for index in 0..<count {
            CGImageDestinationAddImageFromSource(destination, source, index, removed as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
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

/// Progress for a batch of uploads, shared with the Live Activity. On the
/// main actor, where the composer updates it and SwiftUI reads it.
@MainActor
@Observable
public final class UploadProgress {
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

    /// A report that arrives after the item finished is too late to count:
    /// it would move the bar back.
    public func update(_ id: UUID, fraction: Double) {
        guard let index = items.firstIndex(where: { $0.id == id }), !items[index].isFinished
        else { return }
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
