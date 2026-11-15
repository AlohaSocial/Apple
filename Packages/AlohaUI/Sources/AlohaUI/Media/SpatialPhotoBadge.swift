// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaMedia
import AlohaModels
import SwiftUI

/// "Spatial", on a picture with both eyes of a spatial photo in it: in the
/// composer for one about to go up, in the media viewer for one whose
/// original on the server is still spatial.
///
/// Words beside the glyph rather than the glyph alone, because a 3D box
/// means nothing in particular to somebody who has not seen one before, and
/// so the badge does not lean on colour (docs/12 §3).
struct SpatialPhotoBadge: View {
    var body: some View {
        Label {
            Text("Spatial", comment: "Badge on a spatial (3D) photo")
        } icon: {
            Image(systemName: "view.3d")
        }
        .font(.caption2.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .foregroundStyle(.white)
        .background(.black.opacity(0.55), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Finds out whether the original behind a picture is a spatial photo, and
/// keeps a copy Quick Look can open.
///
/// Only the original can say: the server's preview is one flat JPEG. So the
/// viewer asks for the picture on screen and nothing else, and only when
/// its original may be a HEIC — a `.jpg` or `.png` original cannot hold a
/// stereo pair, and is not downloaded to find that out.
enum SpatialOriginal {
    /// A file Quick Look can open, named `.heic` so it is read as one — the
    /// cache's own files have no extension — or nil when the original is
    /// not a spatial photo.
    static func previewFile(for attachment: MediaAttachment) async -> URL? {
        guard !attachment.type.isPlayable, let url = attachment.url, mayBeHEIC(url),
            let original = await ImageLoader.shared.original(for: url)
        else { return nil }
        return await copyIfSpatial(original, named: attachment.id)
    }

    static func mayBeHEIC(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "heic", "heif", "": true
        default: false
        }
    }

    @concurrent
    private static func copyIfSpatial(_ original: URL, named id: String) async -> URL? {
        guard SpatialPhoto.isSpatial(fileAt: original) else { return nil }
        let safeName = id.filter { $0.isLetter || $0.isNumber }
        let copy = FileManager.default.temporaryDirectory
            .appending(path: "spatial-\(safeName.isEmpty ? "photo" : safeName).heic")
        if !FileManager.default.fileExists(atPath: copy.path()) {
            guard (try? FileManager.default.copyItem(at: original, to: copy)) != nil else {
                return nil
            }
        }
        return copy
    }
}
