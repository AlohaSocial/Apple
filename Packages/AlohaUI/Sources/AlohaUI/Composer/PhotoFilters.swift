// SPDX-License-Identifier: MIT

import Foundation
import SwiftUI

#if canImport(CoreImage) && !os(watchOS)
    import CoreImage
    import CoreImage.CIFilterBuiltins
#endif
#if canImport(ImageIO)
    import ImageIO
    import UniformTypeIdentifiers
#endif

/// The adjustments the composer offers, baked into the copy that is posted.
///
/// Nextcloud Social's `src/utils/imageFilters.js`, with the same seven and the
/// same names — a picture filtered here and a picture filtered in the web app
/// should not look like two different features.
///
/// They are deliberately mild. A filter that cannot be undone after upload
/// should not be the kind that ruins a photograph, and these are the
/// adjustments people actually reach for rather than the novelty ones.
public enum PhotoFilter: String, Sendable, Hashable, CaseIterable, Identifiable {
    case none
    case mono
    case noir
    case warm
    case cool
    case vivid
    case faded
    case sepia

    public var id: String { rawValue }

    public var changesAnything: Bool { self != .none }

    public var name: String {
        switch self {
        case .none: String(localized: "Original", comment: "Photo filter")
        case .mono: String(localized: "Mono", comment: "Photo filter")
        case .noir: String(localized: "Noir", comment: "Photo filter")
        case .warm: String(localized: "Warm", comment: "Photo filter")
        case .cool: String(localized: "Cool", comment: "Photo filter")
        case .vivid: String(localized: "Vivid", comment: "Photo filter")
        case .faded: String(localized: "Faded", comment: "Photo filter")
        case .sepia: String(localized: "Sepia", comment: "Photo filter")
        }
    }

    /// The preview, as SwiftUI modifiers.
    ///
    /// The same numbers as the web's CSS declarations, because the preview and
    /// the baked copy have to agree and the CSS is what the other client shows.
    /// Cheap enough to put on a thumbnail row: it is a shader, not a redraw.
    @ViewBuilder
    public func preview<Content: View>(_ content: Content) -> some View {
        switch self {
        case .none:
            content
        case .mono:
            content.grayscale(1)
        case .noir:
            content.grayscale(1).contrast(1.3).brightness(-0.1)
        case .warm:
            content.saturation(1.3).contrast(1.05).colorMultiply(
                Color(red: 1, green: 0.94, blue: 0.85))
        case .cool:
            content.hueRotation(.degrees(-12)).saturation(1.15).brightness(0.05)
        case .vivid:
            content.saturation(1.6).contrast(1.1)
        case .faded:
            content.saturation(0.75).contrast(0.9).brightness(0.1)
        case .sepia:
            content.grayscale(1).colorMultiply(Color(red: 1, green: 0.87, blue: 0.68))
        }
    }
}

#if canImport(CoreImage) && canImport(ImageIO) && !os(watchOS)

    /// Draws a picture through a filter and hands back new bytes.
    ///
    /// Called when the choice settles rather than on every stop along the way:
    /// the preview is a shader on the thumbnail, so flicking through eight
    /// filters costs nothing, and only the send needs pixels.
    ///
    /// JPEG in, JPEG out, at a quality chosen to be visually lossless. PNG stays
    /// PNG, so a screenshot or a picture with transparency does not gain a black
    /// background where its alpha was. An animated picture comes back untouched:
    /// it would otherwise return as its first frame, which is not what anybody
    /// meant by "apply a filter".
    ///
    /// **Never throws.** A filter is a decoration, and losing somebody's upload
    /// because Core Image would not cooperate is not a trade worth making — the
    /// original bytes come back instead.
    public enum PhotoFilterRenderer {
        private static let context = CIContext(options: [.useSoftwareRenderer: false])

        /// The types that survive a redraw. GIF and animated WebP do not.
        private static let filterable: Set<String> = [
            "image/jpeg", "image/png", "image/heic", "image/heif", "image/tiff",
        ]

        public static func apply(
            _ filter: PhotoFilter, to data: Data, mimeType: String
        ) -> (data: Data, mimeType: String, fileExtension: String)? {
            guard filter.changesAnything, filterable.contains(mimeType.lowercased()) else {
                return nil
            }
            guard
                let source = CGImageSourceCreateWithData(data as CFData, nil),
                let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return nil }

            let input = CIImage(cgImage: cgImage)
            guard let output = filter.apply(to: input) else { return nil }
            guard let rendered = context.createCGImage(output, from: input.extent) else {
                return nil
            }

            // PNG keeps its alpha; everything else — including a HEIC the
            // server would rather not have — lands as JPEG.
            let keepsPNG = mimeType.lowercased() == "image/png"
            let type = keepsPNG ? UTType.png : UTType.jpeg
            let outMime = keepsPNG ? "image/png" : "image/jpeg"
            let ext = keepsPNG ? "png" : "jpg"

            let buffer = NSMutableData()
            guard
                let destination = CGImageDestinationCreateWithData(
                    buffer, type.identifier as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(
                destination, rendered,
                [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }

            return (buffer as Data, outMime, ext)
        }
    }

    extension PhotoFilter {
        /// The Core Image equivalent of the preview's modifiers.
        fileprivate func apply(to image: CIImage) -> CIImage? {
            switch self {
            case .none:
                return image
            case .mono:
                return saturation(image, 0)
            case .noir:
                let filter = CIFilter.photoEffectNoir()
                filter.inputImage = image
                return filter.outputImage
            case .warm:
                let sepia = CIFilter.sepiaTone()
                sepia.inputImage = image
                sepia.intensity = 0.35
                guard let toned = sepia.outputImage else { return nil }
                return colourControls(toned, saturation: 1.3, contrast: 1.05, brightness: 0)
            case .cool:
                let hue = CIFilter.hueAdjust()
                hue.inputImage = image
                hue.angle = -12 * .pi / 180
                guard let turned = hue.outputImage else { return nil }
                return colourControls(turned, saturation: 1.15, contrast: 1, brightness: 0.05)
            case .vivid:
                return colourControls(image, saturation: 1.6, contrast: 1.1, brightness: 0)
            case .faded:
                return colourControls(image, saturation: 0.75, contrast: 0.9, brightness: 0.1)
            case .sepia:
                let filter = CIFilter.sepiaTone()
                filter.inputImage = image
                filter.intensity = 0.8
                return filter.outputImage
            }
        }

        private func saturation(_ image: CIImage, _ value: Float) -> CIImage? {
            colourControls(image, saturation: value, contrast: 1, brightness: 0)
        }

        private func colourControls(
            _ image: CIImage, saturation: Float, contrast: Float, brightness: Float
        ) -> CIImage? {
            let filter = CIFilter.colorControls()
            filter.inputImage = image
            filter.saturation = saturation
            filter.contrast = contrast
            filter.brightness = brightness
            return filter.outputImage
        }
    }

#endif
