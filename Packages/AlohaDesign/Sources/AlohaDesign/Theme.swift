// SPDX-License-Identifier: MIT

import SwiftUI

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

    /// The identity: warm, high-contrast, content-forward. Boost is green,
    /// favourite amber, bookmark violet — kept distinct at badge size and
    /// distinguishable under the common colour-vision deficiencies.
    public func palette(for scheme: ColorScheme, increaseContrast: Bool = false) -> AlohaPalette {
        let resolved: AlohaTheme
        switch self {
        case .system:
            resolved =
                scheme == .dark
                ? (increaseContrast ? .highContrastDark : .warmDark)
                : (increaseContrast ? .highContrastLight : .warmLight)
        default:
            resolved = self
        }

        switch resolved {
        case .warmLight, .system:
            return AlohaPalette(
                background: ServerAccent.RGB(red: 0.99, green: 0.98, blue: 0.97),
                surface: .white,
                surfaceRaised: Color(red: 0.97, green: 0.96, blue: 0.94),
                separator: Color(red: 0.87, green: 0.85, blue: 0.82),
                label: Color(red: 0.11, green: 0.10, blue: 0.09),
                secondaryLabel: Color(red: 0.40, green: 0.38, blue: 0.36),
                tertiaryLabel: Color(red: 0.46, green: 0.44, blue: 0.41),
                accent: Color(red: 0.78, green: 0.26, blue: 0.14),
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
                accent: Color(red: 0.72, green: 0.20, blue: 0.08),
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
                accent: Color(red: 0.98, green: 0.52, blue: 0.36),
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
                accent: Color(red: 1.0, green: 0.62, blue: 0.45),
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
}

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
        let isDark = palette.backgroundComponents.red < 0.5
        let wantedHex =
            isDark ? (accent?.darkHex ?? accent?.brightHex) : (accent?.brightHex ?? accent?.darkHex)
        if let fixed = ServerAccent.legible(hex: wantedHex, on: palette.backgroundComponents) {
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

extension View {
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
    public func alohaGround(_ palette: AlohaPalette) -> some View {
        scrollContentBackground(.hidden)
            .background(palette.background)
    }
}

/// Platform-adaptive behavior for native-feeling UI across all Apple platforms.
public enum PlatformBehavior {
    /// iPhone uses tab bar, others use sidebar
    public static var usesSidebar: Bool {
        #if os(iOS)
        return false // Determined at runtime by size class
        #else
        return true
        #endif
    }

    /// Default navigation style per platform
    public static var defaultNavigation: NavigationStyle {
        #if os(iOS)
        return .tabBar
        #elseif os(macOS) || os(visionOS) || os(tvOS)
        return .splitView
        #elseif os(watchOS)
        return .stack
        #else
        return .stack
        #endif
    }

    public enum NavigationStyle: Sendable {
        case tabBar
        case splitView
        case stack
    }

    /// Glass material preference per platform
    public static var preferredGlass: AlohaGlass {
        #if os(visionOS)
        return .subtle
        #elseif os(tvOS)
        return .regular
        #elseif os(watchOS)
        return .subtle
        #else
        return .regular
        #endif
    }

    /// Default density per platform
    public static var defaultDensity: AlohaMetrics.Density {
        #if os(iOS) || os(visionOS)
        return .comfortable
        #elseif os(macOS)
        return .spacious
        #elseif os(tvOS)
        return .spacious
        #elseif os(watchOS)
        return .compact
        #else
        return .comfortable
        #endif
    }

    /// Touch target minimum size
    public static var touchTarget: CGFloat {
        #if os(watchOS)
        return 32
        #elseif os(tvOS)
        return 60
        #else
        return 44
        #endif
    }

    /// Keyboard shortcut modifier
    public static var commandModifier: EventModifiers {
        #if os(macOS) || os(visionOS) || os(iOS)
        return .command
        #else
        return .command
        #endif
    }
}

/// Platform-adaptive view modifier for native behavior
public struct PlatformAdaptive: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let compact: (() -> some View)?
    let regular: (() -> some View)?

    public init(compact: (() -> some View)? = nil, regular: (() -> some View)? = nil) {
        self.compact = compact
        self.regular = regular
    }

    public func body(content: Content) -> some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            content
        } else if let regular {
            regular()
        } else {
            content
        }
        #else
        if let regular {
            regular()
        } else {
            content
        }
        #endif
    }
}

extension View {
    /// Applies platform-adaptive behavior
    public func platformAdaptive(
        compact: (() -> some View)? = nil,
        regular: (() -> some View)? = nil
    ) -> some View {
        modifier(PlatformAdaptive(compact: compact, regular: regular))
    }

    /// Applies native glass effects based on platform
    public func nativeGlass(_ style: AlohaGlass = PlatformBehavior.preferredGlass) -> some View {
        self.unifiedGlass(style)
    }

    /// Platform-aware touch target sizing
    public func nativeTouchTarget() -> some View {
        self.frame(minWidth: PlatformBehavior.touchTarget, minHeight: PlatformBehavior.touchTarget)
    }

    /// Platform-aware navigation style
    @ViewBuilder
    public func nativeNavigation<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            TabView { content() }
        } else {
            NavigationSplitView { content() }
        }
        #else
        NavigationSplitView { content() }
        #endif
    }
}

/// SafeAreaInsets awareness for native feel
extension View {
    public func respectSafeArea(edges: Edge.Set = .all) -> some View {
        self.safeAreaInset(edge: .top) { Color.clear.frame(height: 0) }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 0) }
    }

    /// Native scroll behavior
    public func nativeScrollBehavior() -> some View {
        self.scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
    }
}

/// Native accessibility helpers
extension View {
    public func nativeAccessibilityLabel(_ label: String) -> some View {
        self.accessibilityLabel(Text(label))
    }

    public func nativeAccessibilityHint(_ hint: String) -> some View {
        self.accessibilityHint(Text(hint))
    }

    public func nativeAccessibilityAction(
        _ name: String,
        action: @escaping () -> Void
    ) -> some View {
        self.accessibilityAction(named: Text(name), action)
    }
}

/// Dynamic island / live activity ready content
extension View {
    public func liveActivityReady() -> some View {
        self
    }
}

/// Native share sheet integration
extension View {
    public func nativeShareSheet(
        items: [Any],
        isPresented: Binding<Bool>
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            ShareSheet(activityItems: items)
        }
    }
}

/// ShareSheet wrapper for native share
private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
