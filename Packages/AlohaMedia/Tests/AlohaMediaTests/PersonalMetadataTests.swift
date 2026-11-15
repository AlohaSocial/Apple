// SPDX-License-Identifier: MIT

import AVFoundation
import AlohaModels
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import AlohaMedia

/// Where a video was taken, as an iPhone writes it.
private let location = "+37.3349-122.0090+010.000/"

/// A few frames of a 64-pixel video with a location and an author in it,
/// written the way the camera does: the location both as a QuickTime
/// metadata item and in the older `udta` atom.
private func videoWithLocation(as fileType: AVFileType, pathExtension: String) async throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "metadata-test-\(UUID().uuidString).\(pathExtension)")
    let writer = try AVAssetWriter(outputURL: url, fileType: fileType)

    func item(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return item
    }
    writer.metadata = [
        item(.quickTimeMetadataLocationISO6709, location),
        item(.commonIdentifierLocation, location),
        item(.quickTimeUserDataLocationISO6709, location),
        item(.quickTimeMetadataAuthor, "Jane Appleseed"),
    ]

    let input = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
        ])
    let attributes = CVPixelBufferCreationAttributes(
        pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA),
        size: CVImageSize(width: 64, height: 64))
    let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: attributes)
    try writer.start()
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<5 {
        let buffer = try CVMutablePixelBuffer(attributes)
        try await receiver.append(
            CVReadOnlyPixelBuffer(buffer), with: CMTime(value: CMTimeValue(frame), timescale: 10))
    }
    receiver.finish()
    await writer.finishWriting()
    #expect(writer.status == .completed)
    return url
}

/// Every metadata item in the file, in every format it holds.
private func metadata(at url: URL) async throws -> [AVMetadataItem] {
    let asset = AVURLAsset(url: url)
    var items = try await asset.load(.metadata)
    for format in try await asset.load(.availableMetadataFormats) {
        items += try await asset.loadMetadata(for: format)
    }
    for track in try await asset.load(.tracks) {
        items += try await track.load(.metadata)
    }
    return items
}

private func isLocation(_ item: AVMetadataItem) -> Bool {
    let locations: Set<AVMetadataIdentifier> = [
        .quickTimeMetadataLocationISO6709, .commonIdentifierLocation,
        .quickTimeUserDataLocationISO6709, .identifier3GPUserDataLocation,
    ]
    return item.identifier.map(locations.contains) ?? false
        || item.commonKey == .commonKeyLocation
}

/// One at a time: a refused export is checked by the temporary files it
/// leaves, and the other tests here make some of their own.
@Suite("Personal metadata in videos", .serialized)
struct VideoMetadataTests {

    @Test("The test video does carry a location, so the checks below mean something")
    func fixtureHasLocation() async throws {
        let url = try await videoWithLocation(as: .mov, pathExtension: "mov")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try await metadata(at: url).contains(where: isLocation))
        #expect(try Data(contentsOf: url).range(of: Data(location.utf8)) != nil)
    }

    @Test("A QuickTime video is copied without its location or author, and stays QuickTime")
    func quickTimeLosesLocation() async throws {
        let url = try await videoWithLocation(as: .mov, pathExtension: "mov")
        defer { try? FileManager.default.removeItem(at: url) }

        let output = try await MediaPreparer().removingPersonalMetadata(
            fromVideoAt: url, mimeType: "video/quicktime")
        defer { try? FileManager.default.removeItem(at: output) }

        let items = try await metadata(at: output)
        #expect(!items.contains(where: isLocation))
        #expect(!items.contains { $0.identifier == .quickTimeMetadataAuthor })
        // Not in some atom AVFoundation does not surface, either.
        let bytes = try Data(contentsOf: output)
        #expect(bytes.range(of: Data(location.utf8)) == nil)
        #expect(bytes.range(of: Data("Jane Appleseed".utf8)) == nil)

        let asset = AVURLAsset(url: output)
        #expect(try await asset.load(.tracks).count == 1)
        #expect(try await asset.load(.duration).seconds > 0.3)
        #expect(output.pathExtension == "mov")
    }

    @Test("An MP4 is copied without its location")
    func mp4LosesLocation() async throws {
        let url = try await videoWithLocation(as: .mp4, pathExtension: "mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try await metadata(at: url).contains(where: isLocation))

        let output = try await MediaPreparer().removingPersonalMetadata(
            fromVideoAt: url, mimeType: "video/mp4")
        defer { try? FileManager.default.removeItem(at: output) }

        #expect(!(try await metadata(at: output)).contains(where: isLocation))
        #expect(try await AVURLAsset(url: output).load(.tracks).count == 1)
    }

    @Test("A trimmed and re-encoded video has no location either")
    func preparedVideoLosesLocation() async throws {
        let url = try await videoWithLocation(as: .mov, pathExtension: "mov")
        defer { try? FileManager.default.removeItem(at: url) }

        let prepared = try await MediaPreparer().prepareVideo(at: url, quality: .medium)
        let output = FileManager.default.temporaryDirectory
            .appending(path: "metadata-test-\(UUID().uuidString).mp4")
        try prepared.data.write(to: output)
        defer { try? FileManager.default.removeItem(at: output) }

        #expect(prepared.mimeType == "video/mp4")
        #expect(!(try await metadata(at: output)).contains(where: isLocation))
        #expect(prepared.data.range(of: Data(location.utf8)) == nil)
    }

    @Test("A file that is not a video is refused, and nothing is left behind")
    func notAVideo() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "metadata-test-\(UUID().uuidString).mov")
        try Data("not a movie".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let before = try temporaryFiles()

        await #expect(throws: (any Error).self) {
            _ = try await MediaPreparer().removingPersonalMetadata(
                fromVideoAt: url, mimeType: "video/quicktime")
        }
        #expect(try temporaryFiles() == before)
    }

    @Test("A video type no container here can hold is refused rather than sent as it is")
    func unknownType() async throws {
        let url = try await videoWithLocation(as: .mov, pathExtension: "mov")
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: MediaPreparer.PreparationError.self) {
            _ = try await MediaPreparer().removingPersonalMetadata(
                fromVideoAt: url, mimeType: "video/webm")
        }
    }

    private func temporaryFiles() throws -> Set<String> {
        Set(
            try FileManager.default.contentsOfDirectory(
                atPath: FileManager.default.temporaryDirectory.path()
            ).filter { $0.hasPrefix("aloha-") })
    }
}

@Suite("Personal metadata in pictures")
struct ImageMetadataTests {

    /// A 40 × 20 picture turned on its side, with a location, a name and a
    /// serial number in it.
    private func picture(_ type: UTType) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.displayP3)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        let image = try #require(context.makeImage())

        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 37.3349, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.009, kCGImagePropertyGPSLongitudeRef: "W",
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifBodySerialNumber: "SN12345",
                kCGImagePropertyExifCameraOwnerName: "Jane Appleseed",
            ],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFArtist: "Jane Appleseed"],
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCity: "Cupertino"],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func properties(of data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    @Test(
        "A picture loses its location and names, and keeps its orientation",
        arguments: [UTType.jpeg, .png, .heic])
    func stripped(_ type: UTType) throws {
        let original = try picture(type)
        #expect(try properties(of: original)[kCGImagePropertyGPSDictionary] != nil)

        let prepared = try #require(
            MediaPreparer().removingPersonalMetadata(
                fromImage: original, filename: "photo", mimeType: type.preferredMIMEType!))

        let kept = try properties(of: prepared.data)
        #expect(kept[kCGImagePropertyGPSDictionary] == nil)
        #expect(kept[kCGImagePropertyIPTCDictionary] == nil)
        #expect(!MediaPreparer.carriesPersonalMetadata(prepared.data))
        #expect(prepared.data.range(of: Data("Jane".utf8)) == nil)
        #expect(prepared.data.range(of: Data("SN12345".utf8)) == nil)
        #expect(kept[kCGImagePropertyOrientation] as? Int == 6)
        #expect(kept[kCGImagePropertyPixelWidth] as? Int == 40)
        // Still the same kind of file, under the same name.
        #expect(prepared.mimeType == type.preferredMIMEType)
        #expect(prepared.filename == "photo")
    }

    @Test("A picture with nothing personal in it comes back byte for byte")
    func untouched() throws {
        let original = try #require(
            MediaPreparer().prepareImage(try picture(.png), filename: "a", format: .jpeg))
        let prepared = try #require(
            MediaPreparer().removingPersonalMetadata(
                fromImage: original.data, filename: "a.jpg", mimeType: "image/jpeg"))
        #expect(prepared.data == original.data)
    }

    @Test(
        "A converted picture has no metadata, and is still the right way up",
        arguments: [ImageFormat.heic, .jpeg])
    func convertedIsClean(_ format: ImageFormat) throws {
        let prepared = try #require(
            MediaPreparer().prepareImage(
                try picture(.tiff), filename: "photo.tiff", quality: .original, format: format))
        #expect(prepared.mimeType == format.mimeType)
        #expect(prepared.filename == "photo.\(format.fileExtension)")
        let kept = try properties(of: prepared.data)
        #expect(kept[kCGImagePropertyGPSDictionary] == nil)
        #expect(!MediaPreparer.carriesPersonalMetadata(prepared.data))
        // Orientation 6 is a quarter turn: the stored 40 × 20 is drawn 20 × 40.
        #expect(kept[kCGImagePropertyPixelWidth] as? Int == 20)
        #expect(kept[kCGImagePropertyPixelHeight] as? Int == 40)
    }

    @Test("Bytes that are not a picture are not passed through")
    func notAPicture() {
        #expect(
            MediaPreparer().removingPersonalMetadata(
                fromImage: Data("text".utf8), filename: "a.jpg", mimeType: "image/jpeg") == nil)
    }
}

/// A spatial photo as ImageIO writes one: two pictures in a HEIC, grouped as
/// a stereo pair, with the camera's model and position for each eye — and a
/// location and a serial number to be removed.
func spatialPhoto(size: Int = 64) throws -> Data {
    func eye(_ red: CGFloat) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: size, height: size * 3 / 4, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.displayP3)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Something with edges, so a recompression would change pixels.
        for x in stride(from: 0, to: size, by: 4) {
            context.setFillColor(
                red: red, green: CGFloat(x) / CGFloat(size), blue: 0.3, alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 2, height: size))
        }
        return try #require(context.makeImage())
    }
    func properties(left: Bool) -> [CFString: Any] {
        [
            kCGImagePropertyGroups: [
                kCGImagePropertyGroupIndex: 0,
                kCGImagePropertyGroupType: kCGImagePropertyGroupTypeStereoPair,
                (left
                    ? kCGImagePropertyGroupImageIsLeftImage
                    : kCGImagePropertyGroupImageIsRightImage):
                    true,
                kCGImagePropertyGroupImageDisparityAdjustment: 0,
            ],
            kCGImagePropertyHEIFDictionary: [
                kIIOMetadata_CameraModelKey: [
                    kIIOCameraModel_Intrinsics: [1000.0, 0, 32, 0, 1000.0, 24, 0, 0, 1] as CFArray,
                    kIIOCameraModel_ModelType: kIIOCameraModelType_SimplifiedPinhole,
                ],
                kIIOMetadata_CameraExtrinsicsKey: [
                    kIIOCameraExtrinsics_Position: (left ? [0.0, 0, 0] : [0.064, 0, 0]) as CFArray,
                    kIIOCameraExtrinsics_Rotation: [1.0, 0, 0, 0, 1, 0, 0, 0, 1] as CFArray,
                ],
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 37.3349, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.009, kCGImagePropertyGPSLongitudeRef: "W",
            ],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifBodySerialNumber: "SN12345"],
            kCGImagePropertyOrientation: 1,
        ]
    }
    let output = NSMutableData()
    let destination = try #require(
        CGImageDestinationCreateWithData(output, UTType.heic.identifier as CFString, 2, nil))
    CGImageDestinationAddImage(destination, try eye(1), properties(left: true) as CFDictionary)
    CGImageDestinationAddImage(destination, try eye(0), properties(left: false) as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
}

/// The decoded pixels of one picture in a file, to tell a lossless copy from
/// a recompressed one.
private func pixels(of data: Data, at index: Int) throws -> Data {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, index, nil))
    return try #require(image.dataProvider?.data as Data?)
}

@Suite("Spatial photos and lossless copies")
struct SpatialPhotoTests {

    @Test("A stereo pair in a HEIC is a spatial photo; one picture is not")
    func detection() throws {
        let spatial = try spatialPhoto()
        #expect(SpatialPhoto.isSpatial(spatial))
        let flat = try #require(
            MediaPreparer().prepareImage(spatial, filename: "a", format: .heic))
        #expect(!SpatialPhoto.isSpatial(flat.data))
        #expect(!SpatialPhoto.isSpatial(Data("not a picture".utf8)))
    }

    @Test("Losing its location keeps both eyes, the pair and every pixel")
    func spatialStaysSpatial() throws {
        let original = try spatialPhoto()
        let prepared = try #require(
            MediaPreparer().removingPersonalMetadata(
                fromImage: original, filename: "spatial.heic", mimeType: "image/heic"))

        #expect(prepared.mimeType == "image/heic")
        #expect(SpatialPhoto.isSpatial(prepared.data))
        #expect(!MediaPreparer.carriesPersonalMetadata(prepared.data))
        #expect(prepared.data.range(of: Data("SN12345".utf8)) == nil)
        let source = try #require(CGImageSourceCreateWithData(prepared.data as CFData, nil))
        #expect(CGImageSourceGetCount(source) == 2)
        for index in 0..<2 {
            let kept = try #require(
                CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])
            #expect(kept[kCGImagePropertyGPSDictionary] == nil)
            // The cameras' model and positions are what make the pair
            // viewable in depth; they are not personal and stay.
            #expect(kept[kCGImagePropertyHEIFDictionary] != nil)
            #expect(try pixels(of: prepared.data, at: index) == pixels(of: original, at: index))
        }
    }

    @Test("A HEIC loses its location without being recompressed")
    func heicIsLossless() throws {
        let context = try #require(
            CGContext(
                data: nil, width: 48, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for x in stride(from: 0, to: 48, by: 3) {
            context.setFillColor(red: CGFloat(x) / 48, green: 0.5, blue: 0.1, alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 1, height: 32))
        }
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, UTType.heic.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(
            destination, try #require(context.makeImage()),
            [
                kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 48.1],
                kCGImageDestinationLossyCompressionQuality: 0.5,
            ] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let original = output as Data

        let prepared = try #require(
            MediaPreparer().removingPersonalMetadata(
                fromImage: original, filename: "a.heic", mimeType: "image/heic"))
        #expect(!MediaPreparer.carriesPersonalMetadata(prepared.data))
        #expect(try pixels(of: prepared.data, at: 0) == pixels(of: original, at: 0))
    }
}

@Suite("Pictures made ready for a server")
struct PrepareForUploadTests {
    private func limits(_ types: [String], imageLimit: Int = 10 * 1024 * 1024) -> ServerLimits {
        ServerLimits(
            maxStatusCharacters: 500, maxMediaAttachments: 4, charactersReservedPerURL: 23,
            imageSizeLimit: imageLimit, videoSizeLimit: 40 * 1024 * 1024,
            supportedMIMETypes: types, maxPollOptions: 4, maxPollOptionCharacters: 50,
            minPollExpiration: 300, maxPollExpiration: 2_629_746, maxFeaturedTags: 10)
    }

    @Test("A spatial photo goes up spatial, without its location, on a server with HEIC")
    func spatialOnModernServer() throws {
        let result = MediaPreparer().prepareForUpload(
            image: try spatialPhoto(), filename: "s.heic", mimeType: "image/heic",
            limits: limits(["image/jpeg", "image/heic"]))
        guard case .ready(let prepared, let isSpatial) = result else {
            Issue.record("expected the photo to be sent")
            return
        }
        #expect(isSpatial)
        #expect(prepared.mimeType == "image/heic")
        #expect(SpatialPhoto.isSpatial(prepared.data))
        #expect(!MediaPreparer.carriesPersonalMetadata(prepared.data))
    }

    @Test("A HEIC becomes a JPEG only on a server without HEIC")
    func jpegFallback() throws {
        let result = MediaPreparer().prepareForUpload(
            image: try spatialPhoto(), filename: "s.heic", mimeType: "image/heic",
            limits: limits(["image/jpeg", "image/png"]))
        guard case .ready(let prepared, let isSpatial) = result else {
            Issue.record("expected the photo to be converted")
            return
        }
        #expect(!isSpatial)
        #expect(prepared.mimeType == "image/jpeg")
        #expect(prepared.filename == "s.jpg")
        #expect(!MediaPreparer.carriesPersonalMetadata(prepared.data))
    }

    @Test("A spatial photo over the limit is refused with the limit named")
    func spatialTooLarge() throws {
        let photo = try spatialPhoto()
        let result = MediaPreparer().prepareForUpload(
            image: photo, filename: "s.heic", mimeType: "image/heic",
            limits: limits(["image/heic"], imageLimit: photo.count / 2))
        guard case .refused(let message) = result else {
            Issue.record("expected a refusal")
            return
        }
        #expect(message.contains("spatial"))
    }

    @Test("A picture over the limit is shrunk to HEIC")
    func shrinksToHEIC() throws {
        let photo = try spatialPhoto(size: 1024)
        // Flat, so it may be shrunk; and as a TIFF, so it is large.
        let flat = try #require(
            MediaPreparer().prepareImage(photo, filename: "f", quality: .original, format: .heic))
        let source = try #require(CGImageSourceCreateWithData(flat.data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let png = output as Data

        let result = MediaPreparer().prepareForUpload(
            image: png, filename: "big.png", mimeType: "image/png",
            limits: limits(["image/png", "image/heic", "image/jpeg"], imageLimit: png.count - 1))
        guard case .ready(let prepared, _) = result else {
            Issue.record("expected the picture to be shrunk")
            return
        }
        #expect(prepared.mimeType == "image/heic")
        #expect(prepared.data.count < png.count)
    }
}
