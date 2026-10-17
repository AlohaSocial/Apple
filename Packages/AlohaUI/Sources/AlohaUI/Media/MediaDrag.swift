// SPDX-License-Identifier: MIT

import CoreTransferable
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// A picture in a post, dragged out of the app.
///
/// Offered as the image itself first, so it lands in Photos, Notes or a
/// Finder window as a picture, and as its link after, for anything that
/// only takes URLs. The bytes are fetched only if the drop asks for them.
struct RemoteImageDrag: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .image) { item in
            let (data, _) = try await URLSession.shared.data(from: item.url)
            return data
        }
        ProxyRepresentation(exporting: \.url)
    }
}

/// A picture dropped onto the composer from another app.
///
/// Read as image data whatever its format, then named for what ImageIO says
/// it is, so the upload carries a true MIME type rather than a guessed one.
struct DroppedImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            DroppedImage(data: data)
        }
    }

    /// The type ImageIO recognises in the bytes, or JPEG when it cannot
    /// say — the format a server is surest to accept.
    var contentType: UTType {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let identifier = CGImageSourceGetType(source) as String?,
            let type = UTType(identifier)
        else { return .jpeg }
        return type
    }

    var mimeType: String { contentType.preferredMIMEType ?? "image/jpeg" }
    var filename: String {
        "dropped-\(UUID().uuidString).\(contentType.preferredFilenameExtension ?? "jpg")"
    }
}

/// A picture or a video handed to the composer by a drop or a paste.
///
/// A video comes as a file, never as `Data`: a long one would otherwise be
/// read into memory whole before the trim sheet even opens. It is tried
/// first, so a movie is never taken for a still frame of itself.
enum DroppedMedia: Transferable {
    case image(DroppedImage)
    case movie(URL)

    /// What the composer accepts, in the order it is asked for.
    static let acceptedTypes: [UTType] = [.movie, .image]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            .movie(try copyIn(received.file))
        }
        DataRepresentation(importedContentType: .image) { data in
            .image(DroppedImage(data: data))
        }
    }

    /// The file is the sender's and may vanish once the drop is over, so the
    /// composer works on its own copy.
    private static func copyIn(_ file: URL) throws -> URL {
        let ext = file.pathExtension.isEmpty ? "mov" : file.pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "dropped-\(UUID().uuidString).\(ext)")
        try FileManager.default.copyItem(at: file, to: destination)
        return destination
    }
}

/// Makes a view drag out the picture at `url`, or nothing when there is
/// none — a covered sensitive image is not handed out before it is shown.
struct ImageDragSource: ViewModifier {
    let url: URL?

    func body(content: Content) -> some View {
        #if os(tvOS) || os(watchOS)
            content
        #else
            if let url {
                content.draggable(RemoteImageDrag(url: url))
            } else {
                content
            }
        #endif
    }
}
