// SPDX-License-Identifier: MIT

import SwiftUI

/// View ▸ Bigger, Smaller and Actual Size (⌘+, ⌘−, ⌘0).
///
/// A Mac has no Dynamic Type control of its own, and the app has no text
/// size setting besides it (`AlohaMetrics`), so on the Mac the menu is the
/// control: a step up or down the same Dynamic Type sizes an iPhone offers,
/// applied to every window's shell. Everything scales with it already,
/// because every font is a text style.
public struct MacTextSize: ViewModifier {
    @AppStorage(MacOptions.textSizeKey) private var step = 0

    public init() {}

    public func body(content: Content) -> some View {
        content.dynamicTypeSize(Self.size(forStep: step))
    }

    /// The steps the menu walks: three below the default and five above,
    /// into the first two accessibility sizes, which are where a bigger
    /// window still has room for a post.
    public static let steps = -3...5

    /// The size a step stands for; a step out of range is held at the end.
    public static func size(forStep step: Int) -> DynamicTypeSize {
        let sizes = DynamicTypeSize.allCases
        guard let base = sizes.firstIndex(of: .large) else { return .large }
        let clamped = min(max(step, steps.lowerBound), steps.upperBound)
        let index = min(max(base + clamped, sizes.startIndex), sizes.index(before: sizes.endIndex))
        return sizes[index]
    }
}
