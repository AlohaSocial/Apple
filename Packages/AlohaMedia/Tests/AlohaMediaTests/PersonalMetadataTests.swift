// SPDX-License-Identifier: MIT

import AVFoundation
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
        let original = try #require(MediaPreparer().prepareImage(try picture(.png), filename: "a"))
        let prepared = try #require(
            MediaPreparer().removingPersonalMetadata(
                fromImage: original.data, filename: "a.jpg", mimeType: "image/jpeg"))
        #expect(prepared.data == original.data)
    }

    @Test("A converted picture has no metadata, and is still the right way up")
    func convertedIsClean() throws {
        let prepared = try #require(
            MediaPreparer().prepareImage(try picture(.heic), filename: "photo.heic", quality: .original))
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
