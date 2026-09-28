// SPDX-License-Identifier: MIT

import AlohaDesign
import SwiftUI

/// The warnings people actually write, one tap each. Same six as the web
/// composer, so a post reads the same wherever it was written.
struct ContentWarningPresets: View {
    @Environment(\.alohaPalette) private var palette

    @Binding var spoilerText: String

    private static let presets: [(key: String, title: LocalizedStringResource)] = [
        ("Spoiler", LocalizedStringResource("Spoiler", comment: "Content warning preset")),
        ("Food", LocalizedStringResource("Food", comment: "Content warning preset")),
        ("Politics", LocalizedStringResource("Politics", comment: "Content warning preset")),
        (
            "Mental health",
            LocalizedStringResource("Mental health", comment: "Content warning preset")
        ),
        ("Eye contact", LocalizedStringResource("Eye contact", comment: "Content warning preset")),
        ("Work", LocalizedStringResource("Work", comment: "Content warning preset")),
    ]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AlohaMetrics.space2) {
                ForEach(Self.presets, id: \.key) { preset in
                    let title = String(localized: preset.title)
                    let isOn = spoilerText == title
                    Button {
                        spoilerText = isOn ? "" : title
                    } label: {
                        Text(preset.title)
                            .font(.footnote.weight(isOn ? .semibold : .regular))
                            .foregroundStyle(isOn ? palette.onAccent : palette.label)
                            .padding(.horizontal, AlohaMetrics.space3)
                            .frame(minHeight: 32)
                            .background(isOn ? palette.accent : palette.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, AlohaMetrics.space3)
            .padding(.bottom, AlohaMetrics.space2)
        }
        .scrollIndicators(.hidden)
        .background(palette.surfaceRaised)
    }
}
