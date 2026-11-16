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
            // A picture the server does not take is written again as HEIC,
            // or as JPEG on a server without HEIC (`ImageFormat.target`); a
            // QuickTime video goes through the exporter to MP4.
            if let target = transcodeTarget(for: mimeType, limits: limits) {
                return .needsTranscode(from: mimeType, to: target)
            }
            return .unsupported(mimeType: mimeType)
        }

        if fileSize > limit {
            return .tooLarge(size: fileSize, limit: limit, isVideo: isVideo)
        }
        return .ready(mimeType: mimeType)
    }

    /// Picture types the app can decode and write again in another format.
    /// Not GIF or WebP: they can be animated, and would arrive as their
    /// first frame.
    static let convertibleImages: Set<String> = [
        "image/heic", "image/heif", "image/jpeg", "image/png", "image/tiff",
        "image/x-adobe-dng", "image/bmp",
    ]

    static func transcodeTarget(
        for mimeType: String, limits: ServerLimits,
        writable: (ImageFormat) -> Bool = \.isWritable
    ) -> String? {
        let type = mimeType.lowercased()
        if convertibleImages.contains(type) {
            return ImageFormat.target(accepting: limits.accepts(mimeType:), writable: writable)
                .map(\.mimeType)
                .flatMap { $0 == type ? nil : $0 }
        }
        switch type {
        case "video/quicktime", "video/x-m4v":
            return limits.accepts(mimeType: "video/mp4") ? "video/mp4" : nil
        default:
            return nil
        }
    }

    /// What happens to a picture before it goes up. Pure, so each decision
    /// can be tested without a picture (docs/07 §4):
    ///
    /// 1. A type the server takes, under its limit, goes up as it is — HEIC
    ///    included, and a spatial photo with both its eyes. Only the
    ///    personal metadata is copied out, losslessly.
    /// 2. A type the server does not take is written again as HEIC, or as
    ///    JPEG on a server that does not take HEIC either.
    /// 3. A picture over the limit is written again, smaller, in the same
    ///    format a conversion would use — except a spatial photo, which
    ///    would lose an eye, and is refused with the limit named instead.
    public enum ImagePlan: Sendable, Hashable {
        case original
        case convert(to: ImageFormat)
        case shrink(to: ImageFormat)
        case spatialTooLarge(size: Int, limit: Int)
        case refuse(Verdict)
    }

    public static func imagePlan(
        fileSize: Int, mimeType: String, isSpatial: Bool, limits: ServerLimits
    ) -> ImagePlan {
        imagePlan(
            fileSize: fileSize, mimeType: mimeType, isSpatial: isSpatial, limits: limits,
            writable: \.isWritable)
    }

    static func imagePlan(
        fileSize: Int, mimeType: String, isSpatial: Bool, limits: ServerLimits,
        writable: (ImageFormat) -> Bool
    ) -> ImagePlan {
        let limit = limits.imageSizeLimit
        let target = ImageFormat.target(accepting: limits.accepts(mimeType:), writable: writable)
        if limits.accepts(mimeType: mimeType) {
            guard fileSize > limit else { return .original }
            if isSpatial { return .spatialTooLarge(size: fileSize, limit: limit) }
            guard let target else {
                return .refuse(.tooLarge(size: fileSize, limit: limit, isVideo: false))
            }
            return .shrink(to: target)
        }
        // A spatial photo on a server without HEIC cannot stay spatial
        // whatever is done; it goes up as an ordinary picture, its first
        // eye, rather than not at all.
        guard convertibleImages.contains(mimeType.lowercased()), let target else {
            return .refuse(.unsupported(mimeType: mimeType))
        }
        return .convert(to: target)
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

    /// Why a spatial photo was not sent. Named apart from "too large",
    /// because the cure is not the one a picture usually gets.
    public static func spatialTooLargeExplanation(limit: Int) -> String {
        let formatted = limit.formatted(.byteCount(style: .file))
        return String(
            localized:
                "This spatial photo is over your server's limit of \(formatted). Making it smaller would lose its depth, so it wasn't added.",
            comment: "Upload refused: a spatial (3D) photo larger than the server allows")
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

    /// Writes an image again, as `format`, at a bounded size. `nil` maximum
    /// keeps the original dimensions and only changes the container.
    ///
    /// The format is always the caller's choice — HEIC unless the server
    /// does not take it (`ImageFormat.target(for:)`) — so nothing becomes a
    /// JPEG without somebody having decided it should.
    ///
    /// Only the pixels are carried over, so the result has no EXIF, GPS or
    /// IPTC metadata whatever the original had. Only the first picture is
    /// drawn: never call this for a spatial photo that should stay one.
    public func prepareImage(
        _ data: Data, filename: String, quality: Quality = .high, format: ImageFormat,
        compression: CGFloat = 0.85
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
        if let maximum = quality.maximumPixelSize ?? (longestSide > 0 ? CGFloat(longestSide) : nil)
        {
            options[kCGImageSourceThumbnailMaxPixelSize] = maximum
        }

        let image =
            CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)

        guard let image, let output = Self.encode(image, as: format, quality: compression)
        else { return nil }

        let base = (filename as NSString).deletingPathExtension
        return Prepared(
            data: output, filename: "\(base).\(format.fileExtension)", mimeType: format.mimeType)
    }

    /// One picture as `format`, with no metadata. Nil where the device has
    /// no encoder for it.
    public static func encode(
        _ image: CGImage, as format: ImageFormat, quality: CGFloat = 0.85
    ) -> Data? {
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, format.type.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            destination, image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// A picture made ready for this server, or why it cannot be: the whole
    /// of `UploadPreflight.imagePlan` carried out. The composer, the share
    /// sheet and Shortcuts all send pictures through here, so none of them
    /// can send one with its location in it, or one this server refuses.
    ///
    /// Heavy — a 48-megapixel decode when a picture has to be written again
    /// — so callers run it off the main actor.
    public func prepareForUpload(
        image data: Data, filename: String, mimeType: String, limits: ServerLimits
    ) -> ImageUpload {
        let isSpatial = SpatialPhoto.isSpatial(data)
        let limit = limits.imageSizeLimit
        let fallback = ImageFormat.target(for: limits) ?? .jpeg

        func shrink(to format: ImageFormat, from size: Int) -> ImageUpload {
            guard
                let smaller = prepareImage(
                    data, filename: filename, quality: .high, format: format),
                smaller.data.count <= limit
            else {
                return .refused(
                    UploadPreflight.explanation(
                        for: .tooLarge(size: size, limit: limit, isVideo: false)) ?? "")
            }
            return .ready(smaller, isSpatial: false)
        }

        switch UploadPreflight.imagePlan(
            fileSize: data.count, mimeType: mimeType, isSpatial: isSpatial, limits: limits)
        {
        case .original:
            guard
                let cleaned = removingPersonalMetadata(
                    fromImage: data, filename: filename, mimeType: mimeType, fallback: fallback)
            else { return .refused(Self.couldNotPrepare) }
            if cleaned.data.count <= limit {
                // Still spatial only if it is still the same file type: the
                // copy is lossless, so it is.
                return .ready(cleaned, isSpatial: isSpatial && cleaned.mimeType == mimeType)
            }
            // A picture written again can come out a little larger than it
            // went in; it gets the one attempt an oversized picture gets.
            if isSpatial {
                return .refused(UploadPreflight.spatialTooLargeExplanation(limit: limit))
            }
            return shrink(to: fallback, from: cleaned.data.count)

        case .convert(let format):
            guard
                let converted = prepareImage(
                    data, filename: filename, quality: .original, format: format)
            else { return .refused(Self.couldNotPrepare) }
            if converted.data.count <= limit { return .ready(converted, isSpatial: false) }
            return shrink(to: format, from: converted.data.count)

        case .shrink(let format):
            return shrink(to: format, from: data.count)

        case .spatialTooLarge(_, let limit):
            return .refused(UploadPreflight.spatialTooLargeExplanation(limit: limit))

        case .refuse(let verdict):
            return .refused(UploadPreflight.explanation(for: verdict) ?? Self.couldNotPrepare)
        }
    }

    /// What `prepareForUpload` decided.
    public enum ImageUpload: Sendable {
        /// The bytes to send. `isSpatial` when both eyes are still there.
        case ready(Prepared, isSpatial: Bool)
        /// Not sent, and why, in words for the person.
        case refused(String)
    }

    static var couldNotPrepare: String {
        String(localized: "That image couldn't be converted.", comment: "Upload failure")
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
    /// JPEG, HEIC/HEIF, PNG and TIFF are copied without decoding
    /// (`CGImageDestinationCopyImageSource`): no pixel is recompressed, and
    /// everything in the container that is not metadata stays — the second
    /// eye of a spatial photo, a depth map, an HDR gain map, the colour
    /// profile. Other kinds are drawn again in their own format, and one
    /// whose format cannot be written (WebP) becomes `fallback`. A spatial
    /// photo is never drawn again: if it cannot be copied, nothing is
    /// returned. `nil` when the bytes are not a picture.
    public func removingPersonalMetadata(
        fromImage data: Data, filename: String, mimeType: String,
        fallback: ImageFormat = .heic
    ) -> Prepared? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let type = CGImageSourceGetType(source),
            CGImageSourceGetCount(source) > 0
        else { return nil }
        guard Self.carriesPersonalMetadata(source) else {
            return Prepared(data: data, filename: filename, mimeType: mimeType)
        }

        if let uniformType = UTType(type as String),
            Self.copiesLosslessly.contains(where: { uniformType.conforms(to: $0) }),
            let copy = Self.copyWithoutMetadata(source, type: type),
            Self.isFaithfulCopy(copy, of: source)
        {
            return Prepared(data: copy, filename: filename, mimeType: mimeType)
        }
        guard !SpatialPhoto.isSpatial(source) else { return nil }
        if let redrawn = Self.redrawWithoutMetadata(source, type: type),
            !Self.carriesPersonalMetadata(redrawn)
        {
            return Prepared(data: redrawn, filename: filename, mimeType: mimeType)
        }
        guard let format = [fallback, .jpeg].first(where: \.isWritable) else { return nil }
        return prepareImage(data, filename: filename, quality: .original, format: format)
    }

    /// The containers ImageIO copies with new metadata and no re-encoding.
    static let copiesLosslessly: [UTType] = [.jpeg, .heic, .heif, .png, .tiff]

    /// A copy that kept every picture and its groups and lost the personal
    /// metadata — anything less is not used.
    private static func isFaithfulCopy(_ copy: Data, of source: CGImageSource) -> Bool {
        guard let copied = CGImageSourceCreateWithData(copy as CFData, nil),
            CGImageSourceGetCount(copied) == CGImageSourceGetCount(source),
            !carriesPersonalMetadata(copied)
        else { return false }
        return SpatialPhoto.isSpatial(copied) == SpatialPhoto.isSpatial(source)
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
            (
                kCGImagePropertyTIFFDictionary,
                [kCGImagePropertyTIFFArtist, kCGImagePropertyTIFFHostComputer]
            ),
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

    /// The compressed data copied into a new file whose only metadata is the
    /// orientation. Lossless, and no pixels are decoded.
    ///
    /// The metadata has to be *replaced*: `kCGImageMetadataShouldExcludeGPS`
    /// on its own, without `kCGImageDestinationMetadata`, leaves the GPS
    /// dictionary where it was (checked on a HEIC; the tests pin it).
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
            CGImageDestinationAddImageFromSource(
                destination, source, index, removed as CFDictionary)
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
