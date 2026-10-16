// SPDX-License-Identifier: MIT

import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// Semantic colour roles. View code names a role, never a colour — which is
/// what makes light, dark and the two increased-contrast variants one change
/// rather than four (docs/05 §2).
public struct AlohaPalette: Sendable, Hashable {
    public var background: Color
    /// The same colour as numbers. `Color` cannot be read back portably, and
    /// the server-accent contrast guard has to measure against the ground it
    /// will be drawn on.
    public var backgroundComponents: ServerAccent.RGB
    public var surface: Color
    public var surfaceRaised: Color
    public var separator: Color
    public var label: Color
    public var secondaryLabel: Color
    public var tertiaryLabel: Color
    public var accent: Color
    /// What text takes when drawn *on* the accent. White is right on a dark
    /// orange and wrong on a light one, which is what the dark themes use.
    public var onAccent: Color
    public var accentMuted: Color
    public var destructive: Color
    public var boost: Color
    public var favourite: Color
    public var bookmark: Color
    public var mention: Color
    public var hashtag: Color
    /// Whether the grounds are the platform's own semantic colours. Then a
    /// `List` or `Form` keeps the system's grouped background rather than
    /// having it painted over (`alohaGround`), which is what makes Settings
    /// look like Settings.
    public var usesSystemGrounds = false

    public init(
        background: ServerAccent.RGB, surface: Color, surfaceRaised: Color, separator: Color,
        label: Color, secondaryLabel: Color, tertiaryLabel: Color, accent: Color,
        onAccent: Color = .white,
        accentMuted: Color, destructive: Color, boost: Color, favourite: Color,
        bookmark: Color, mention: Color, hashtag: Color
    ) {
        self.background = Color(
            .sRGB, red: background.red, green: background.green, blue: background.blue,
            opacity: 1)
        self.backgroundComponents = background
        self.surface = surface
        self.surfaceRaised = surfaceRaised
        self.separator = separator
        self.label = label
        self.secondaryLabel = secondaryLabel
        self.tertiaryLabel = tertiaryLabel
        self.accent = accent
        self.onAccent = onAccent
        self.accentMuted = accentMuted
        self.destructive = destructive
        self.boost = boost
        self.favourite = favourite
        self.bookmark = bookmark
        self.mention = mention
        self.hashtag = hashtag
    }
}

public enum AlohaTheme: String, CaseIterable, Sendable, Codable, Identifiable {
    case system
    case warmLight
    case warmDark
    case highContrastLight
    case highContrastDark
    case dim
    case black

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: String(localized: "System", comment: "Theme name")
        case .warmLight: String(localized: "Warm Light", comment: "Theme name")
        case .warmDark: String(localized: "Warm Dark", comment: "Theme name")
        case .highContrastLight: String(localized: "High Contrast Light", comment: "Theme name")
        case .highContrastDark: String(localized: "High Contrast Dark", comment: "Theme name")
        case .dim: String(localized: "Dim", comment: "Theme name")
        case .black: String(localized: "Black", comment: "Theme name")
        }
    }

    public var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .warmLight, .highContrastLight: .light
        case .warmDark, .highContrastDark, .dim, .black: .dark
        }
    }

    /// The identity: warm, high-contrast, content-forward. The accent is the
    /// brand coral (`#E8604C`, the hibiscus) with only its lightness moved,
    /// far enough to reach 4.5:1 on each ground (7:1 on the high-contrast
    /// ones) — it is what a server that names no colour of its own wears. Boost is green,
    /// favourite amber, bookmark violet — kept distinct at badge size and
    /// distinguishable under the common colour-vision deficiencies.
    public func palette(for scheme: ColorScheme, increaseContrast: Bool = false) -> AlohaPalette {
        switch self {
        case .system:
            return Self.systemPalette(for: scheme, increaseContrast: increaseContrast)
        case .warmLight:
            return AlohaPalette(
                background: ServerAccent.RGB(red: 0.99, green: 0.98, blue: 0.97),
                surface: .white,
                surfaceRaised: Color(red: 0.97, green: 0.96, blue: 0.94),
                separator: Color(red: 0.87, green: 0.85, blue: 0.82),
                label: Color(red: 0.11, green: 0.10, blue: 0.09),
                secondaryLabel: Color(red: 0.40, green: 0.38, blue: 0.36),
                tertiaryLabel: Color(red: 0.46, green: 0.44, blue: 0.41),
                accent: Color(red: 0.851, green: 0.204, blue: 0.109),
                accentMuted: Color(red: 0.95, green: 0.62, blue: 0.35),
                destructive: Color(red: 0.78, green: 0.16, blue: 0.16),
                boost: Color(red: 0.16, green: 0.55, blue: 0.33),
                favourite: Color(red: 0.85, green: 0.58, blue: 0.10),
                bookmark: Color(red: 0.46, green: 0.31, blue: 0.75),
                mention: Color(red: 0.14, green: 0.42, blue: 0.72),
                hashtag: Color(red: 0.14, green: 0.42, blue: 0.72))

        case .highContrastLight:
            return AlohaPalette(
                background: .white,
                surface: .white,
                surfaceRaised: Color(white: 0.94),
                separator: Color(white: 0.45),
                label: .black,
                secondaryLabel: Color(white: 0.22),
                tertiaryLabel: Color(white: 0.34),
                accent: Color(red: 0.659, green: 0.158, blue: 0.085),
                accentMuted: Color(red: 0.60, green: 0.30, blue: 0.10),
                destructive: Color(red: 0.65, green: 0.05, blue: 0.05),
                boost: Color(red: 0.06, green: 0.40, blue: 0.20),
                favourite: Color(red: 0.60, green: 0.38, blue: 0.00),
                bookmark: Color(red: 0.32, green: 0.16, blue: 0.62),
                mention: Color(red: 0.05, green: 0.28, blue: 0.60),
                hashtag: Color(red: 0.05, green: 0.28, blue: 0.60))

        case .warmDark:
            return AlohaPalette(
                background: ServerAccent.RGB(red: 0.09, green: 0.08, blue: 0.08),
                surface: Color(red: 0.13, green: 0.12, blue: 0.11),
                surfaceRaised: Color(red: 0.18, green: 0.17, blue: 0.16),
                separator: Color(red: 0.28, green: 0.26, blue: 0.25),
                label: Color(red: 0.97, green: 0.96, blue: 0.95),
                secondaryLabel: Color(red: 0.72, green: 0.70, blue: 0.68),
                tertiaryLabel: Color(red: 0.58, green: 0.56, blue: 0.54),
                accent: Color(red: 0.914, green: 0.405, blue: 0.330),
                onAccent: Color(red: 0.12, green: 0.06, blue: 0.03),
                accentMuted: Color(red: 0.85, green: 0.60, blue: 0.40),
                destructive: Color(red: 0.95, green: 0.42, blue: 0.40),
                boost: Color(red: 0.40, green: 0.82, blue: 0.55),
                favourite: Color(red: 0.98, green: 0.76, blue: 0.32),
                bookmark: Color(red: 0.68, green: 0.55, blue: 0.95),
                mention: Color(red: 0.45, green: 0.70, blue: 0.98),
                hashtag: Color(red: 0.45, green: 0.70, blue: 0.98))

        case .highContrastDark:
            return AlohaPalette(
                background: .black,
                surface: Color(white: 0.06),
                surfaceRaised: Color(white: 0.14),
                separator: Color(white: 0.55),
                label: .white,
                secondaryLabel: Color(white: 0.86),
                tertiaryLabel: Color(white: 0.72),
                accent: Color(red: 0.919, green: 0.443, blue: 0.372),
                onAccent: .black,
                accentMuted: Color(red: 0.95, green: 0.72, blue: 0.55),
                destructive: Color(red: 1.0, green: 0.55, blue: 0.52),
                boost: Color(red: 0.55, green: 0.95, blue: 0.68),
                favourite: Color(red: 1.0, green: 0.85, blue: 0.45),
                bookmark: Color(red: 0.80, green: 0.70, blue: 1.0),
                mention: Color(red: 0.60, green: 0.82, blue: 1.0),
                hashtag: Color(red: 0.60, green: 0.82, blue: 1.0))

        case .dim:
            var palette = AlohaTheme.warmDark.palette(for: .dark)
            palette.background = Color(red: 0.13, green: 0.15, blue: 0.18)
            palette.surface = Color(red: 0.17, green: 0.19, blue: 0.23)
            palette.surfaceRaised = Color(red: 0.22, green: 0.25, blue: 0.29)
            return palette

        case .black:
            var palette = AlohaTheme.warmDark.palette(for: .dark)
            palette.background = .black
            palette.surface = .black
            palette.surfaceRaised = Color(white: 0.10)
            return palette
        }
    }

    /// The System theme: the platform's own grounds, surfaces, separators and
    /// label, so the app sits beside Settings and Mail rather than in a tint
    /// of its own. The meaning-carrying tints — accent, boost, favourite,
    /// bookmark, mention — come from the matching warm or high-contrast
    /// palette, which already reach their contrast floor on white and black.
    ///
    /// The secondary and tertiary text roles are the one deliberate departure:
    /// the system's own `secondaryLabel` is about 3.5:1 on white, and these
    /// carry handles, timestamps and counts at caption size, which docs/12 §3
    /// holds to 4.5:1. They are neutral greys in the system's grey family,
    /// moved just far enough.
    ///
    /// tvOS and watchOS have no semantic ground colours, so there System is
    /// what it always was: the warm palettes.
    static func systemPalette(for scheme: ColorScheme, increaseContrast: Bool) -> AlohaPalette {
        let isDark = scheme == .dark
        let tints: AlohaTheme =
            isDark
            ? (increaseContrast ? .highContrastDark : .warmDark)
            : (increaseContrast ? .highContrastLight : .warmLight)
        var palette = tints.palette(for: scheme)

        #if os(iOS) || os(visionOS) || os(macOS)
            palette.background = SystemColours.background
            palette.backgroundComponents = isDark ? SystemColours.darkGround : .white
            palette.surface = SystemColours.surface
            palette.surfaceRaised = SystemColours.surfaceRaised
            palette.separator = SystemColours.separator
            palette.label = SystemColours.label
            switch (isDark, increaseContrast) {
            case (false, false):
                palette.secondaryLabel = Color(red: 0.36, green: 0.36, blue: 0.38)
                palette.tertiaryLabel = Color(red: 0.42, green: 0.42, blue: 0.44)
            case (false, true):
                palette.secondaryLabel = Color(white: 0.22)
                palette.tertiaryLabel = Color(white: 0.32)
            case (true, false):
                palette.secondaryLabel = Color(red: 0.70, green: 0.70, blue: 0.73)
                palette.tertiaryLabel = Color(red: 0.60, green: 0.60, blue: 0.63)
            case (true, true):
                palette.secondaryLabel = Color(white: 0.86)
                palette.tertiaryLabel = Color(white: 0.74)
            }
            palette.usesSystemGrounds = true
        #endif
        return palette
    }
}

#if os(iOS) || os(visionOS) || os(macOS)
    /// The semantic colours the System theme is built from. Each resolves
    /// against the view's own appearance — a sheet in dark mode gets the
    /// elevated ground, Increase Contrast the stronger separator — which a
    /// fixed palette never could.
    enum SystemColours {
        #if os(macOS)
            static let background = Color(nsColor: .textBackgroundColor)
            static let surface = Color(nsColor: .secondarySystemFill)
            static let surfaceRaised = Color(nsColor: .tertiarySystemFill)
            static let separator = Color(nsColor: .separatorColor)
            static let label = Color(nsColor: .labelColor)
            /// `textBackgroundColor` in dark mode, as numbers, for the
            /// server-accent contrast guard.
            static let darkGround = ServerAccent.RGB(red: 0.118, green: 0.118, blue: 0.118)
        #else
            static let background = Color(uiColor: .systemBackground)
            static let surface = Color(uiColor: .secondarySystemBackground)
            static let surfaceRaised = Color(uiColor: .tertiarySystemFill)
            static let separator = Color(uiColor: .separator)
            static let label = Color(uiColor: .label)
            static let darkGround = ServerAccent.RGB.black
        #endif
    }
#endif

// MARK: - Environment

extension EnvironmentValues {
    @Entry public var alohaPalette: AlohaPalette = AlohaTheme.warmLight.palette(for: .light)
    @Entry public var alohaMetrics: AlohaMetrics = AlohaMetrics()
}

/// Spacing, radii and density. All multiples of a 4-point rhythm so a density
/// change is one number rather than a sweep through every view.
public struct AlohaMetrics: Sendable, Hashable {
    public var density: Density
    public var textSizeOffset: Int
    public var lineSpacing: Double
    public var useSerifBody: Bool
    public var avatarShape: AvatarShape

    public enum Density: String, CaseIterable, Sendable, Codable {
        case compact, comfortable, spacious

        public var rowSpacing: Double {
            switch self {
            case .compact: 8
            case .comfortable: 12
            case .spacious: 16
            }
        }
        public var rowPadding: Double {
            switch self {
            case .compact: 10
            case .comfortable: 14
            case .spacious: 18
            }
        }
    }

    public enum AvatarShape: String, CaseIterable, Sendable, Codable {
        case circle, roundedSquare
    }

    public init(
        density: Density = .comfortable, textSizeOffset: Int = 0, lineSpacing: Double = 2,
        useSerifBody: Bool = false, avatarShape: AvatarShape = .circle
    ) {
        self.density = density
        self.textSizeOffset = textSizeOffset
        self.lineSpacing = lineSpacing
        self.useSerifBody = useSerifBody
        self.avatarShape = avatarShape
    }

    public static let space1: Double = 4
    public static let space2: Double = 8
    public static let space3: Double = 12
    public static let space4: Double = 16
    public static let space5: Double = 24
    public static let space6: Double = 32

    public static let cornerSmall: Double = 8
    public static let cornerMedium: Double = 14
    public static let cornerLarge: Double = 22

    public var avatarSize: Double {
        switch density {
        case .compact: 40
        case .comfortable: 46
        case .spacious: 52
        }
    }
}

/// The one platform rule a full-bleed vertical surface needs.
///
/// Shorts is a phone-shaped thing: on a regular-width shell it stays a vertical
/// column in the middle of the window, the way TikTok and Reels do on an iPad,
/// rather than becoming a letterboxed sprawl across a Mac window. On a phone it
/// takes the whole screen, which it already does.
public enum PlatformBehavior {
    /// How wide a vertical full-screen surface may grow.
    public static var shortsColumnWidth: CGFloat? {
        #if os(iOS)
            return UIDevice.current.userInterfaceIdiom == .phone ? nil : 460
        #else
            return 460
        #endif
    }
}

public struct AlohaThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    let theme: AlohaTheme
    let metrics: AlohaMetrics
    let accent: ServerTheme?

    /// What the server said about its colour, as hex. Nothing is chosen here:
    /// the app wears the colour of the Nextcloud it is signed in to.
    public struct ServerTheme: Sendable, Hashable {
        /// Legible on a light background.
        public var brightHex: String?
        /// Legible on a dark background.
        public var darkHex: String?
        /// What the server puts on top of its own colour.
        public var textHex: String?

        public init(brightHex: String?, darkHex: String?, textHex: String?) {
            self.brightHex = brightHex
            self.darkHex = darkHex
            self.textHex = textHex
        }
    }

    public init(theme: AlohaTheme, metrics: AlohaMetrics, accent: ServerTheme? = nil) {
        self.theme = theme
        self.metrics = metrics
        self.accent = accent
    }

    public func body(content: Content) -> some View {
        var palette = theme.palette(for: scheme, increaseContrast: contrast == .increased)
        // Only the accent moves: boost, favourite and bookmark carry meaning
        // and stay where they are whatever colour the server is wearing.
        //
        // A colour that cannot be made legible against this theme's background
        // is left out entirely rather than forced — the app's own accent is
        // known to work, and an unreadable one is worse than a colour that is
        // not quite theirs.
        if let fixed = accent?.legibleComponents(on: palette.backgroundComponents) {
            palette.accent = ServerAccent.colour(fixed)
            palette.onAccent = ServerAccent.textColour(on: fixed, preferring: accent?.textHex)
        }
        return
            content
            .environment(\.alohaPalette, palette)
            .environment(\.alohaMetrics, metrics)
            .tint(palette.accent)
            .preferredColorScheme(theme.preferredColorScheme)
    }
}

extension AlohaThemeModifier.ServerTheme {
    /// The server's colour made legible against `ground`, or `nil` where it
    /// cannot be — the one rule every process applies, so the widgets, the
    /// watch and the TV wear the same colour the app does.
    public func legibleComponents(on ground: ServerAccent.RGB) -> ServerAccent.RGB? {
        let isDark = ground.red < 0.5
        let wantedHex = isDark ? (darkHex ?? brightHex) : (brightHex ?? darkHex)
        return ServerAccent.legible(hex: wantedHex, on: ground)
    }

    /// The accent for a surface the app does not paint itself — a widget, the
    /// watch, the TV — measured against the app's own ground for that scheme,
    /// which is close enough to the system's to keep the 4.5:1 floor.
    public func accent(for scheme: ColorScheme) -> Color? {
        let ground = AlohaTheme.system.palette(for: scheme).backgroundComponents
        return legibleComponents(on: ground).map(ServerAccent.colour)
    }
}

/// Tints a surface with the server's colour, or leaves the platform's own
/// tint where there is none. For the processes that have no `AppEnvironment`
/// and so no `alohaTheme` — they still owe the person the server's colour.
public struct ServerTintModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let theme: AlohaThemeModifier.ServerTheme?

    public func body(content: Content) -> some View {
        if let colour = theme?.accent(for: scheme) {
            content.tint(colour)
        } else {
            content
        }
    }
}

extension View {
    public func serverTint(_ theme: AlohaThemeModifier.ServerTheme?) -> some View {
        modifier(ServerTintModifier(theme: theme))
    }

    public func alohaTheme(
        _ theme: AlohaTheme, metrics: AlohaMetrics = AlohaMetrics(),
        accent: AlohaThemeModifier.ServerTheme? = nil
    ) -> some View {
        modifier(AlohaThemeModifier(theme: theme, metrics: metrics, accent: accent))
    }

    /// The app's own ground beneath a scrolling container.
    ///
    /// `List` and `Form` paint the system's grouped background over whatever is
    /// behind them — a cool grey under a theme whose ground is warm cream — so
    /// every screen built on one looked like a different app from the timelines
    /// it sat next to. Hiding that and painting `palette.background` is what
    /// puts the grouped screens back in the same theme.
    ///
    /// The cards themselves are left alone: the system's grouped card colour
    /// already tracks the scheme, and the one theme where a palette surface
    /// would swallow them (`black`, where surface and ground are both black)
    /// is the one that would break.
    ///
    /// Under the System theme it does nothing: there the ground *is* the
    /// system's, and the grouped background is the look to keep.
    @ViewBuilder
    public func alohaGround(_ palette: AlohaPalette) -> some View {
        if palette.usesSystemGrounds {
            self
        } else {
            #if os(tvOS)
                // tvOS has no `scrollContentBackground`: its lists draw no
                // grouped ground of their own to hide.
                background(palette.background)
            #else
                scrollContentBackground(.hidden)
                    .background(palette.background)
            #endif
        }
    }
}

/// Modern glass material intensities for native UI layering.
///
/// A card over content, a sheet over the screen, a toolbar over the list —
/// the three levels a blur can sit at. Naming them keeps the same level in
/// every place instead of a material chosen by whichever view got there
/// first.
public enum AlohaGlass: Sendable {
    /// A card, a row, a control sitting on content.
    case regular
    /// A sheet or a toolbar over the screen: the strongest layer.
    case prominent
    /// A hairline of separation rather than a wall.
    case subtle

    @available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
    public var material: Material {
        switch self {
        case .regular: .regularMaterial
        case .prominent: .thickMaterial
        case .subtle: .ultraThinMaterial
        }
    }
}

/// Glass effect modifiers for modern native UI layering.
///
/// `unifiedGlass` is the one every view uses: on iOS 17 and macOS 14 it is a
/// real `Material` blur, and on anything older it degrades to a gradient over
/// `ultraThinMaterial` — which is not the same one, but a caller should not
/// have to compile two versions of a card for that.
extension View {
    /// A filled glass panel: the material, plus a hairline border that reads
    /// as the edge of a real layer of glass.
    @available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
    public func alohaGlass(
        _ style: AlohaGlass = AlohaGlass.regular,
        in shape: some InsettableShape = RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium)
    ) -> some View {
        self
            .background(style.material, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
    }

    /// The material alone, for when something else draws the edge.
    @available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)

    /// A fallback for older systems: a gradient over ultra-thin material rather
    /// than a plain colour, so a card still reads as a layer.
    public func alohaGlassFallback(
        _ style: AlohaGlass = AlohaGlass.regular,
        in shape: some InsettableShape = RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium)
    ) -> some View {
        let colors: [Color] = {
            switch style {
            case .regular: return [Color.white.opacity(0.15), Color.white.opacity(0.05)]
            case .prominent: return [Color.white.opacity(0.25), Color.white.opacity(0.1)]
            case .subtle: return [Color.white.opacity(0.08), Color.white.opacity(0.02)]
            }
        }()
        return
            self
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .background(.ultraThinMaterial)
                    .clipShape(shape)
            )
            .overlay(shape.strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
    }

    /// The one glass effect every view uses: real material everywhere it is
    /// available, the gradient fallback everywhere else.
    public func unifiedGlass(
        _ style: AlohaGlass = AlohaGlass.regular,
        in shape: some InsettableShape = RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium)
    ) -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) {
            return self.alohaGlass(style, in: shape)
        } else {
            return self.alohaGlassFallback(style, in: shape)
        }
    }
}

/// `hoverEffect(.highlight)` on the platforms that have it, nothing
/// everywhere else.
///
/// Two platforms hover: visionOS, where a look at a row lights it up, and the
/// iPad, where the pointer does — a trackpad, a mouse, a Magic Keyboard. This
/// was visionOS-only, which left every row on an iPad with a pointer inert
/// under it. An iPhone has no pointer, so there it costs nothing; the Mac has
/// its own selection highlight and no `hoverEffect`. The call sites never
/// need their own `#if`.
extension View {
    @ViewBuilder
    public func alohaRowHighlight() -> some View {
        #if os(visionOS) || os(iOS)
            hoverEffect(.highlight)
        #else
            self
        #endif
    }

    /// The same highlight for a custom control — a plain-style button or a
    /// tappable card — drawn in the shape the control actually has rather
    /// than its glyph's bounding box, which is all a plain button would
    /// otherwise light up.
    @ViewBuilder
    public func alohaHoverTarget(_ shape: some Shape) -> some View {
        #if os(visionOS) || os(iOS)
            contentShape(.hoverEffect, shape).hoverEffect(.highlight)
        #else
            self
        #endif
    }
}
