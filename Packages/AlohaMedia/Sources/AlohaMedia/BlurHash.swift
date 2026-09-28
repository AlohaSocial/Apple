// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation

/// Decodes the `blurhash` field into a tiny placeholder image.
///
/// Painted immediately so a row never shifts when the real image arrives
/// (docs/05 §3). Pure Swift — the algorithm is short and a dependency for it
/// would not survive the zero-third-party rule.
public enum BlurHash {

    public static func decode(_ hash: String, size: CGSize, punch: Float = 1) -> CGImage? {
        let characters = Array(hash)
        guard characters.count >= 6 else { return nil }

        guard let sizeFlag = decode83(String(characters[0])) else { return nil }
        let componentsY = (sizeFlag / 9) + 1
        let componentsX = (sizeFlag % 9) + 1
        guard characters.count == 4 + 2 * componentsX * componentsY else { return nil }

        guard let quantisedMaximum = decode83(String(characters[1])) else { return nil }
        let maximumValue = Float(quantisedMaximum + 1) / 166

        var colours = [(Float, Float, Float)](
            repeating: (0, 0, 0), count: componentsX * componentsY)
        for index in colours.indices {
            if index == 0 {
                guard let value = decode83(String(characters[2..<6])) else { return nil }
                colours[index] = decodeDC(value)
            } else {
                let start = 4 + index * 2
                guard let value = decode83(String(characters[start..<start + 2])) else {
                    return nil
                }
                colours[index] = decodeAC(value, maximumValue: maximumValue * punch)
            }
        }

        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        for y in 0..<height {
            for x in 0..<width {
                var red: Float = 0
                var green: Float = 0
                var blue: Float = 0

                for componentY in 0..<componentsY {
                    for componentX in 0..<componentsX {
                        let basis =
                            cos(Float.pi * Float(x) * Float(componentX) / Float(width))
                            * cos(Float.pi * Float(y) * Float(componentY) / Float(height))
                        let colour = colours[componentX + componentY * componentsX]
                        red += colour.0 * basis
                        green += colour.1 * basis
                        blue += colour.2 * basis
                    }
                }

                let offset = 4 * x + y * bytesPerRow
                pixels[offset] = UInt8(linearTosRGB(red))
                pixels[offset + 1] = UInt8(linearTosRGB(green))
                pixels[offset + 2] = UInt8(linearTosRGB(blue))
                pixels[offset + 3] = 255
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// The average colour, taken straight from the DC term.
    ///
    /// The first component of a blurhash *is* the mean colour of the image, so
    /// this needs no decoding pass — which is what makes it cheap enough to
    /// tint a row behind every photo in a timeline.
    public static func averageColour(_ hash: String) -> (red: Double, green: Double, blue: Double)?
    {
        let characters = Array(hash)
        guard characters.count >= 6, let value = decode83(String(characters[2..<6])) else {
            return nil
        }
        return (
            Double((value >> 16) & 255) / 255,
            Double((value >> 8) & 255) / 255,
            Double(value & 255) / 255
        )
    }

    private static let alphabet = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~")

    private static func decode83<S: StringProtocol>(_ text: S) -> Int? {
        var value = 0
        for character in text {
            guard let digit = alphabet.firstIndex(of: character) else { return nil }
            value = value * 83 + digit
        }
        return value
    }

    private static func decodeDC(_ value: Int) -> (Float, Float, Float) {
        (
            sRGBToLinear((value >> 16) & 255),
            sRGBToLinear((value >> 8) & 255),
            sRGBToLinear(value & 255)
        )
    }

    private static func decodeAC(_ value: Int, maximumValue: Float) -> (Float, Float, Float) {
        func signPow(_ component: Int) -> Float {
            let normalised = (Float(component) - 9) / 9
            return copysign(pow(abs(normalised), 2), normalised) * maximumValue
        }
        return (signPow(value / (19 * 19)), signPow((value / 19) % 19), signPow(value % 19))
    }

    private static func sRGBToLinear(_ value: Int) -> Float {
        let normalised = Float(value) / 255
        return normalised <= 0.04045
            ? normalised / 12.92
            : pow((normalised + 0.055) / 1.055, 2.4)
    }

    private static func linearTosRGB(_ value: Float) -> Int {
        let clamped = max(0, min(1, value))
        return clamped <= 0.0031308
            ? Int(clamped * 12.92 * 255 + 0.5)
            : Int((1.055 * pow(clamped, 1 / 2.4) - 0.055) * 255 + 0.5)
    }
}

extension String {
    fileprivate subscript(range: Range<Int>) -> String {
        let characters = Array(self)
        guard range.lowerBound >= 0, range.upperBound <= characters.count else { return "" }
        return String(characters[range])
    }
}
