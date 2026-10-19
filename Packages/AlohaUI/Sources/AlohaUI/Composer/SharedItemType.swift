// SPDX-License-Identifier: MIT

import Foundation
import UniformTypeIdentifiers

/// Which of the representations a shared item offers to upload, and what to
/// call it.
///
/// A share sheet hands over whatever the source app registered — on the Mac
/// often TIFF first, which no fediverse server takes — so the extension asks
/// for the first type a server accepts rather than for "an image" and
/// labelling whatever arrives as JPEG.
public enum SharedItemType {
    /// Image types a server stores as they are, best first.
    public static let uploadableImages: [UTType] = [.jpeg, .png, .heic, .gif, .webP]
    /// Movie types a server transcodes, best first.
    public static let uploadableMovies: [UTType] = [.mpeg4Movie, .quickTimeMovie]

    /// The first uploadable type among `registered` (the provider's
    /// `registeredTypeIdentifiers`), in the order of `preferred`; nil when the
    /// item only offers something that has to be converted first.
    public static func pick(from registered: [String], preferring preferred: [UTType]) -> UTType? {
        let offered = registered.compactMap(UTType.init)
        return preferred.first { candidate in offered.contains { $0.conforms(to: candidate) } }
    }

    /// The MIME type and file name an upload of `type` goes up with.
    public static func upload(for type: UTType) -> (mimeType: String, filename: String) {
        let mimeType = type.preferredMIMEType ?? "application/octet-stream"
        let ext = type.preferredFilenameExtension ?? "bin"
        return (mimeType, "shared-\(UUID().uuidString).\(ext)")
    }
}
