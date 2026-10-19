// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

/// The initials of an account on a colour of its own.
///
/// Stands in for an avatar that has not loaded, or that does not exist. An
/// empty grey circle on every row of every screen was the single most visible
/// flaw in the app; Nextcloud generates exactly this server-side, so a person
/// with no picture still reads as a person here.
public struct MonogramView: View {
    private let account: Account
    private let size: Double

    public init(account: Account, size: Double) {
        self.account = account
        self.size = size
    }

    public var body: some View {
        // Two stops of the same hue: flat fill at this size looks like a bug,
        // a gradient looks deliberate.
        LinearGradient(
            colors: [
                Monogram.colour(for: seed, lightness: 0.52),
                Monogram.colour(for: seed, lightness: 0.38),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .overlay {
            Text(Monogram.initials(for: account))
                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .padding(size * 0.12)
        }
    }

    /// The handle, not the display name: it is the part that does not change,
    /// so somebody's colour stays theirs when they rename themselves.
    private var seed: String { account.acct.isEmpty ? account.id : account.acct }
}

public enum Monogram {
    /// At most two letters, taken from the display name where there is one.
    public static func initials(for account: Account) -> String {
        let source = account.displayName.isEmpty ? account.username : account.displayName
        let words =
            source
            .split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "-" || $0 == "." })
            .prefix(2)
        let letters = words.compactMap { $0.first(where: \.isLetter) ?? $0.first }
        if letters.isEmpty {
            return String((account.acct.first ?? "?").uppercased())
        }
        return letters.map { String($0).uppercased() }.joined()
    }

    /// A stable hue per handle, in degrees. FNV-1a rather than `hashValue`,
    /// which is seeded per launch and would give somebody a new colour every
    /// time.
    public static func hue(for seed: String) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return Double(hash % 360)
    }

    public static func colour(for seed: String, lightness: Double) -> Color {
        let hue = hue(for: seed) / 360
        // Saturation stays in a narrow band so no avatar screams next to the
        // accent colour.
        return Color(
            hue: hue, saturation: saturation,
            brightness: legibleBrightness(hue: hue, from: lightness + 0.28))
    }

    static let saturation = 0.52

    /// WCAG's minimum for text: the white initials against their ground.
    static let minimumContrast = 4.5

    /// `start`, or as much darker as this hue needs for white initials to keep
    /// 4.5:1. One brightness does not fit every hue: at the same setting an
    /// orange or a green is far lighter than a blue, and white on it failed.
    static func legibleBrightness(hue: Double, from start: Double) -> Double {
        var brightness = start
        while brightness > 0.2,
            contrastWithWhite(hue: hue, brightness: brightness) < minimumContrast
        {
            brightness -= 0.01
        }
        return brightness
    }

    /// WCAG contrast of white against this hue at `brightness`.
    static func contrastWithWhite(hue: Double, brightness: Double) -> Double {
        1.05 / (relativeLuminance(hue: hue, brightness: brightness) + 0.05)
    }

    /// WCAG relative luminance of an HSB colour at the monogram's saturation.
    static func relativeLuminance(hue: Double, brightness: Double) -> Double {
        let chroma = brightness * saturation
        let sector = (hue * 6).truncatingRemainder(dividingBy: 6)
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) =
            switch Int(sector) {
            case 0: (chroma, second, 0)
            case 1: (second, chroma, 0)
            case 2: (0, chroma, second)
            case 3: (0, second, chroma)
            case 4: (second, 0, chroma)
            default: (chroma, 0, second)
            }
        let lift = brightness - chroma
        func linear(_ channel: Double) -> Double {
            let value = channel + lift
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
