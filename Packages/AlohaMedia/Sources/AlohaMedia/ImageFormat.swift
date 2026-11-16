// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The formats this app writes a picture in, when it has to write one at
/// all — which is only when the server will not take the picture as it is,
/// or it is over the server's size limit (docs/07 §4).
///
/// The rule is to send the original. Where that cannot be, HEIC: it keeps a
/// photograph's wide colour, depth and HDR at about half the size of a JPEG
/// of the same quality. JPEG is the last resort, for a server that takes
/// neither the original's type nor HEIC — never a default.
public enum ImageFormat: String, Sendable, CaseIterable {
    case heic
    /// Only for a server that does not take HEIC (`target(for:)`).
    case jpeg

    public var mimeType: String {
        switch self {
        case .heic: "image/heic"
        case .jpeg: "image/jpeg"
        }
    }

    public var fileExtension: String {
        switch self {
        case .heic: "heic"
        case .jpeg: "jpg"
        }
    }

    var type: UTType {
        switch self {
        case .heic: .heic
        case .jpeg: .jpeg
        }
    }

    /// Whether ImageIO on this device can write the format. HEIC needs an
    /// encoder a few devices lack (the watch); JPEG is everywhere.
    var isWritable: Bool {
        let writable = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return writable.contains(type.identifier)
    }

    /// What a picture is written as for this server: HEIC where the server
    /// takes HEIC, JPEG only where it takes JPEG and not HEIC — the explicit
    /// fallback — and nil when it takes neither, which leaves nothing this
    /// app can convert to.
    public static func target(for limits: ServerLimits) -> ImageFormat? {
        target(accepting: limits.accepts(mimeType:))
    }

    static func target(
        accepting accepts: (String) -> Bool, writable: (ImageFormat) -> Bool = \.isWritable
    ) -> ImageFormat? {
        allCases.first { accepts($0.mimeType) && writable($0) }
    }

    /// The format a MIME type names, when it is one of these.
    public init?(mimeType: String) {
        switch mimeType.lowercased() {
        case "image/heic", "image/heif": self = .heic
        case "image/jpeg", "image/jpg": self = .jpeg
        default: return nil
        }
    }
}

/// A spatial photo: two pictures, one for each eye, kept together as a
/// stereo pair group in a HEIC file — what an iPhone 15 Pro or later and
/// Apple Vision Pro take.
///
/// The pair only survives as long as nothing redraws the file. Decoding it
/// and writing it again keeps the first picture and silently loses the
/// other eye, so the app copies one losslessly or not at all.
public enum SpatialPhoto {
    /// Whether `data` is a HEIC/HEIF file with a stereo pair group in it.
    public static func isSpatial(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return isSpatial(source)
    }

    /// The same, for a file on disk; only the container's index is read,
    /// not the pictures.
    public static func isSpatial(fileAt url: URL) -> Bool {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return false }
        return isSpatial(source)
    }

    static func isSpatial(_ source: CGImageSource) -> Bool {
        guard let identifier = CGImageSourceGetType(source) as String?,
            let type = UTType(identifier), type.conforms(to: .heif) || type == .heic,
            CGImageSourceGetCount(source) >= 2,
            let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
            let groups = properties[kCGImagePropertyGroups] as? [[CFString: Any]]
        else { return false }
        return groups.contains {
            ($0[kCGImagePropertyGroupType] as? String)
                == (kCGImagePropertyGroupTypeStereoPair as String)
        }
    }
}
