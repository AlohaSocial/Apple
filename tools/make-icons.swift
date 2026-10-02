// SPDX-License-Identifier: MIT
//
// Writes every icon the app needs from the artwork in `tools/logo/`.
//
//   swift tools/make-icons.swift
//
// The three 1024 PNGs there are the official Aloha Social mark, rasterised
// from the SVGs in github.com/AlohaSocial/Logos: the everyday icon on sand,
// the dark-appearance icon on deep sea, and the tinted mark alone on
// transparency. Everything below is derived from those three, so the mark
// itself is never redrawn here — the SVGs upstream are the single source.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The alternate app icons: the same flower in the accent each one is named
/// for, so picking an icon still picks a colour the settings screen shows.
struct Alternate {
    let name: String
    let red: Double
    let green: Double
    let blue: Double
}

let alternates = [
    Alternate(name: "Ocean", red: 0.11, green: 0.47, blue: 0.78),
    Alternate(name: "Forest", red: 0.13, green: 0.50, blue: 0.33),
    Alternate(name: "Grape", red: 0.47, green: 0.29, blue: 0.75),
    Alternate(name: "Rose", red: 0.82, green: 0.24, blue: 0.45),
    Alternate(name: "Slate", red: 0.33, green: 0.38, blue: 0.45),
]

func read(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func write(_ image: CGImage, to url: URL) {
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

/// The image drawn at `size`, whatever size it was authored at.
func scaled(_ image: CGImage, to size: Int) -> CGImage? {
    if image.width == size && image.height == size { return image }
    guard
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return context.makeImage()
}

/// The flower in another colour, with the sand ground and the white glyph
/// left exactly as they are: only pixels saturated enough to be the coral
/// are touched, which is what keeps the `@` and its halo clean.
func recoloured(_ image: CGImage, to red: Double, green: Double, blue: Double) -> CGImage? {
    guard
        let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let data = context.data else { return nil }
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    let count = image.width * image.height

    for index in 0..<count {
        let offset = index * 4
        let r = Double(bytes[offset]) / 255
        let g = Double(bytes[offset + 1]) / 255
        let b = Double(bytes[offset + 2]) / 255
        let high = max(r, g, b)
        let low = min(r, g, b)
        let chroma = high - low
        guard high > 0, chroma / high >= 0.45 else { continue }
        bytes[offset] = UInt8(max(0, min(255, red * 255)))
        bytes[offset + 1] = UInt8(max(0, min(255, green * 255)))
        bytes[offset + 2] = UInt8(max(0, min(255, blue * 255)))
    }
    return context.makeImage()
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let logo = root.appending(path: "tools/logo")
let iconSet = root.appending(path: "AlohaSocial/Assets.xcassets/AppIcon.appiconset")
let catalog = root.appending(path: "AlohaSocial/Assets.xcassets")

guard
    let everyday = read(logo.appending(path: "icon-default-1024.png")),
    let dark = read(logo.appending(path: "icon-dark-1024.png")),
    let tinted = read(logo.appending(path: "icon-tinted-1024.png"))
else {
    FileHandle.standardError.write(
        Data("tools/logo: the three 1024 PNGs are missing\n".utf8))
    exit(1)
}

// The primary icon, in the three appearances iOS asks for.
write(everyday, to: iconSet.appending(path: "icon-1024.png"))
write(dark, to: iconSet.appending(path: "icon-1024-dark.png"))
write(tinted, to: iconSet.appending(path: "icon-1024-tinted.png"))

for scale in [1, 2] {
    for size in [16, 32, 128, 256, 512] {
        let pixels = size * scale
        guard let image = scaled(everyday, to: pixels) else { continue }
        let suffix = scale == 1 ? "" : "@2x"
        write(image, to: iconSet.appending(path: "mac-\(size)\(suffix).png"))
    }
}

/// Every alternate is its own icon set in the same catalog, which is what
/// `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` expects.
let alternateContents = """
    {
      "images" : [
        {
          "filename" : "icon-1024.png",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """

/// Previews for the picker in Settings. An alternate icon lives in the
/// catalog as an icon, which `UIImage(named:)` will not hand back, so the
/// same artwork is also written as an ordinary image the picker can show.
func writePreview(_ image: CGImage?, named name: String) {
    guard let image, let small = scaled(image, to: 180) else { return }
    let folder = catalog.appending(path: "AppIconPreviews")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try? """
        { "info" : { "author" : "xcode", "version" : 1 } }
        """.write(
        to: folder.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
    let set = folder.appending(path: "\(name).imageset")
    try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    let contents = """
        {
          "images" : [
            { "filename" : "\(name).png", "idiom" : "universal", "scale" : "1x" },
            { "filename" : "\(name).png", "idiom" : "universal", "scale" : "2x" },
            { "filename" : "\(name).png", "idiom" : "universal", "scale" : "3x" }
          ],
          "info" : { "author" : "xcode", "version" : 1 }
        }
        """
    try? contents.write(
        to: set.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
    write(small, to: set.appending(path: "\(name).png"))
}

writePreview(everyday, named: "Aloha")

for alternate in alternates {
    let set = catalog.appending(path: "AlohaIcon-\(alternate.name).appiconset")
    try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    try? alternateContents.write(
        to: set.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
    let recolouredImage = recoloured(
        everyday, to: alternate.red, green: alternate.green, blue: alternate.blue)
    if let recolouredImage {
        write(recolouredImage, to: set.appending(path: "icon-1024.png"))
    }
    writePreview(recolouredImage, named: "AlohaIcon-\(alternate.name)")
}

print("icons written")
