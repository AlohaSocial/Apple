// SPDX-License-Identifier: MIT
//
// Draws the Aloha Social mark — two speech bubbles, one behind the other —
// and writes every icon the app needs.
//
//   swift tools/make-icons.swift
//
// Kept as source rather than checked-in binaries alone so the mark can be
// changed in one place; the PNGs it writes are committed because Xcode needs
// them at build time.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Colourway {
    let name: String
    let top: (Double, Double, Double)
    let bottom: (Double, Double, Double)
}

let colourways = [
    Colourway(name: "Aloha", top: (0.98, 0.50, 0.27), bottom: (0.85, 0.27, 0.16)),
    Colourway(name: "Ocean", top: (0.24, 0.62, 0.90), bottom: (0.08, 0.38, 0.70)),
    Colourway(name: "Forest", top: (0.26, 0.66, 0.44), bottom: (0.09, 0.42, 0.27)),
    Colourway(name: "Grape", top: (0.60, 0.42, 0.88), bottom: (0.38, 0.22, 0.66)),
    Colourway(name: "Rose", top: (0.92, 0.38, 0.58), bottom: (0.74, 0.17, 0.38)),
    Colourway(name: "Slate", top: (0.46, 0.52, 0.60), bottom: (0.25, 0.30, 0.37)),
]

/// A speech bubble: a rounded rectangle with a tail on its lower-left.
///
/// Both shapes are filled rather than stroked. A stroked bubble needs one
/// continuous outline or the tail's base draws a line straight through the
/// body, which is exactly what the first attempt did.
///
/// Body and tail come back separately and are filled in two passes. Combined
/// into one path they wind in opposite directions, and the non-zero fill rule
/// then punches the tail straight through the bubble.
func bubblePaths(in rect: CGRect, radius: CGFloat) -> (body: CGPath, tail: CGPath) {
    let body = CGMutablePath()
    body.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)

    // The base sits well inside the body, not on its edge: a base flush with a
    // rounded corner leaves a notch where the curve pulls away.
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.minY + rect.height * 0.34))
    tail.addLine(to: CGPoint(x: rect.minX + rect.width * 0.48, y: rect.minY + rect.height * 0.04))
    tail.addLine(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY - rect.height * 0.26))
    tail.closeSubpath()

    return (body, tail)
}

func fillBubble(_ context: CGContext, in rect: CGRect, radius: CGFloat, colour: CGColor) {
    let (body, tail) = bubblePaths(in: rect, radius: radius)
    context.setFillColor(colour)
    context.addPath(tail)
    context.fillPath()
    context.addPath(body)
    context.fillPath()
}

func drawIcon(size: CGFloat, colourway: Colourway, background: Bool = true) -> CGImage? {
    let space = CGColorSpaceCreateDeviceRGB()
    guard
        let context = CGContext(
            data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
            bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    if background {
        let colours =
            [
                CGColor(
                    red: colourway.top.0, green: colourway.top.1, blue: colourway.top.2, alpha: 1),
                CGColor(
                    red: colourway.bottom.0, green: colourway.bottom.1, blue: colourway.bottom.2,
                    alpha: 1),
            ] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colours, locations: [0, 1]) {
            context.drawLinearGradient(
                gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0),
                options: [])
        }
    }

    // Back bubble: translucent, up and to the left, so the overlap reads as
    // depth rather than as two shapes touching.
    let backRect = CGRect(
        x: size * 0.15, y: size * 0.44, width: size * 0.45, height: size * 0.32)
    fillBubble(
        context, in: backRect, radius: size * 0.11,
        colour: CGColor(red: 1, green: 1, blue: 1, alpha: 0.42))

    // Front bubble: solid, down and to the right, with two lines of "text".
    let frontRect = CGRect(
        x: size * 0.38, y: size * 0.27, width: size * 0.47, height: size * 0.33)
    fillBubble(
        context, in: frontRect, radius: size * 0.11,
        colour: CGColor(red: 1, green: 1, blue: 1, alpha: 1))

    context.setFillColor(
        CGColor(
            red: colourway.bottom.0, green: colourway.bottom.1, blue: colourway.bottom.2, alpha: 1))
    for (index, width) in [0.28, 0.21].enumerated() {
        let bar = CGRect(
            x: frontRect.minX + size * 0.075,
            y: frontRect.midY + size * (index == 0 ? 0.022 : -0.052),
            width: size * width, height: size * 0.040)
        context.addPath(
            CGPath(
                roundedRect: bar, cornerWidth: size * 0.019, cornerHeight: size * 0.019,
                transform: nil))
    }
    context.fillPath()

    return context.makeImage()
}

func write(_ image: CGImage, to url: URL) {
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconSet = root.appending(path: "AlohaSocial/Assets.xcassets/AppIcon.appiconset")
let alternates = root.appending(path: "AlohaSocial/AlternateIcons")
try? FileManager.default.createDirectory(at: alternates, withIntermediateDirectories: true)

let aloha = colourways[0]

// The primary icon, in the three appearances iOS asks for, plus macOS sizes.
if let image = drawIcon(size: 1024, colourway: aloha) {
    write(image, to: iconSet.appending(path: "icon-1024.png"))
}
// Dark: the same mark on a deeper ground, which is what the dark appearance is
// for — not a different drawing.
if let image = drawIcon(
    size: 1024,
    colourway: Colourway(name: "Dark", top: (0.34, 0.14, 0.09), bottom: (0.16, 0.07, 0.05)))
{
    write(image, to: iconSet.appending(path: "icon-1024-dark.png"))
}
// Tinted: the system supplies the colour, so the mark is drawn in greys.
if let image = drawIcon(
    size: 1024,
    colourway: Colourway(name: "Tinted", top: (0.30, 0.30, 0.30), bottom: (0.12, 0.12, 0.12)))
{
    write(image, to: iconSet.appending(path: "icon-1024-tinted.png"))
}

for scale in [1, 2] {
    for size in [16, 32, 128, 256, 512] {
        let pixels = CGFloat(size * scale)
        guard let image = drawIcon(size: pixels, colourway: aloha) else { continue }
        let suffix = scale == 1 ? "" : "@2x"
        write(image, to: iconSet.appending(path: "mac-\(size)\(suffix).png"))
    }
}

// Alternates are their own icon sets in the same catalog, which is what
// `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` expects; loose PNGs at the
// bundle root are the older shape and need their own Info.plist entries.
let catalog = root.appending(path: "AlohaSocial/Assets.xcassets")
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

for colourway in colourways.dropFirst() {
    let set = catalog.appending(path: "AlohaIcon-\(colourway.name).appiconset")
    try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    try? alternateContents.write(
        to: set.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
    if let image = drawIcon(size: 1024, colourway: colourway) {
        write(image, to: set.appending(path: "icon-1024.png"))
    }
}

print("icons written")
