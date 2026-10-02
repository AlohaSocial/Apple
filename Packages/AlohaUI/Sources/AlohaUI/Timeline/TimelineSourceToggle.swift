// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

/// Which of the three timelines you are reading, as a toggle you can see.
///
/// This used to be a menu behind a filter glyph in the toolbar: two taps, and
/// nothing on screen said which of the three you were in. A segmented control
/// floating at the foot of the timeline says so without being asked, and
/// switches in one tap.
struct TimelineSourceToggle: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicator

    @Binding var source: TimelineSource

    private static let options: [(source: TimelineSource, title: LocalizedStringResource)] = [
        (.home, LocalizedStringResource("My feed", comment: "Timeline source")),
        (.local, LocalizedStringResource("Local", comment: "Timeline source")),
        (.federated, LocalizedStringResource("Global", comment: "Timeline source")),
    ]

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(Self.options, id: \.source) { option in
                    button(for: option.source, title: Text(option.title))
                }
            }
        }
        .padding(.bottom, AlohaMetrics.space2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Timeline source", comment: "Accessibility label"))
    }

    private func button(for option: TimelineSource, title: Text) -> some View {
        let isSelected = source == option
        return Button {
            if reduceMotion {
                source = option
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { source = option }
            }
        } label: {
            title
                .font(.footnote.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? palette.onAccent : palette.label)
                .padding(.horizontal, AlohaMetrics.space4)
                .padding(.vertical, AlohaMetrics.space2)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular.tint(isSelected ? palette.accent : nil).interactive(),
            in: Capsule())
        .glassEffectID(option, in: indicator)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
