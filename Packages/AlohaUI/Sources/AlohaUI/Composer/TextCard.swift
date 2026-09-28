// SPDX-License-Identifier: MIT

import AlohaDesign
import Foundation
import SwiftUI

#if canImport(ImageIO)
    import ImageIO
    import UniformTypeIdentifiers
#endif

/// Words on colour, drawn to a picture.
///
/// Nextcloud Social's `src/utils/textCard.js` and `ShortComposerDialog.vue`:
/// anything short enough, with nothing attached, can go out drawn big on a
/// coloured card. Six backgrounds, the first in the writer's own colour.
///
/// Drawn and uploaded as an ordinary picture rather than invented as a new kind
/// of post, so it federates as what it looks like. A Mastodon reader sees a
/// picture with the words on it; the words themselves travel as the picture's
/// description **and** as the post, so they are still searchable and still read
/// aloud (docs/07 §2).
public enum TextCard {
    /// How long a post may be and still go out as a card. The web's limit, and
    /// the point past which the words stop being big enough to be the picture.
    public static let characterLimit = 120

    /// The side of the square that is drawn and uploaded.
    public static let side: CGFloat = 1080

    /// A background, as two colour stops and the ink that reads on them.
    public struct Background: Sendable, Hashable, Identifiable {
        public var id: String
        public var from: Color
        public var to: Color
        public var ink: Color
        public var name: String
    }

    /// Every background, with the writer's own colour resolved into the first.
    ///
    /// `accountHue` is the hue the account is drawn with elsewhere in the app,
    /// so "your colour" is the same colour somewhere else on the screen.
    public static func backgrounds(accountHue: Double = 210) -> [Background] {
        [
            Background(
                id: "account",
                from: Color(hue: accountHue / 360, saturation: 0.72, brightness: 0.58),
                to: Color(
                    hue: (accountHue + 40).truncatingRemainder(dividingBy: 360) / 360,
                    saturation: 0.65, brightness: 0.32),
                ink: .white,
                name: String(localized: "Your colour", comment: "Card background")),
            Background(
                id: "sunset", from: Color(hex: 0xFF7A59), to: Color(hex: 0xE8367F), ink: .white,
                name: String(localized: "Sunset", comment: "Card background")),
            Background(
                id: "ocean", from: Color(hex: 0x1C92D2), to: Color(hex: 0x0B3C8C), ink: .white,
                name: String(localized: "Ocean", comment: "Card background")),
            Background(
                id: "forest", from: Color(hex: 0x2BB673), to: Color(hex: 0x0D5C46), ink: .white,
                name: String(localized: "Forest", comment: "Card background")),
            Background(
                id: "night", from: Color(hex: 0x3B3F7A), to: Color(hex: 0x111228), ink: .white,
                name: String(localized: "Night", comment: "Card background")),
            Background(
                id: "lemon", from: Color(hex: 0xFFE36E), to: Color(hex: 0xFFA24C),
                ink: Color(hex: 0x3A2600),
                name: String(localized: "Lemon", comment: "Card background")),
        ]
    }

    /// Whether these words can go out as a card at all.
    public static func fits(_ text: String, attachments: Int, hasPoll: Bool) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= characterLimit && attachments == 0 && !hasPoll
    }

    /// The card, as a view. The same view is what gets drawn to pixels, so the
    /// preview and the upload cannot drift apart.
    public struct CardView: View {
        public let text: String
        public let background: Background
        /// 1 at full size; the preview passes the fraction of `side` it is drawn at.
        public let scale: CGFloat

        public init(text: String, background: Background, scale: CGFloat = 1) {
            self.text = text
            self.background = background
            self.scale = scale
        }

        /// Shorter words get to be bigger, which is the whole point of a card.
        private var fontSize: CGFloat {
            let length = max(1, text.count)
            let size: CGFloat =
                switch length {
                case ..<25: 116
                case ..<50: 92
                case ..<85: 72
                default: 58
                }
            return size * scale
        }

        public var body: some View {
            ZStack {
                LinearGradient(
                    colors: [background.from, background.to],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(text)
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(background.ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.4)
                    .padding(TextCard.side * 0.11 * scale)
            }
            .frame(width: TextCard.side * scale, height: TextCard.side * scale)
        }
    }

    #if canImport(ImageIO)
        /// Draws the card and hands back PNG bytes ready to upload.
        ///
        /// `nil` rather than a throw where the platform will not draw: the post
        /// then goes out as ordinary text rather than not going out at all.
        @MainActor
        public static func render(text: String, background: Background) -> Data? {
            let renderer = ImageRenderer(content: CardView(text: text, background: background))
            renderer.scale = 1
            guard let cgImage = renderer.cgImage else { return nil }

            let buffer = NSMutableData()
            guard
                let destination = CGImageDestinationCreateWithData(
                    buffer, UTType.png.identifier as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(destination, cgImage, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return buffer as Data
        }
    #endif
}

extension Color {
    /// `0xRRGGBB`, for the card's fixed palette. The design system's own
    /// colours are named rather than numeric; these six are the web app's and
    /// are copied verbatim so the two draw the same card.
    fileprivate init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1)
    }
}
