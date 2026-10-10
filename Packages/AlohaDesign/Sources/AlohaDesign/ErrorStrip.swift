// SPDX-License-Identifier: MIT

import SwiftUI

/// One error strip for every list in the app.
///
/// Twenty-one screens had grown their own copy — three of them differently
/// wrong: one ignored the retry, one had the message but no action, one grew
/// an unreadable caption. A message the reader can do something about is the
/// only kind worth showing, and it should look the same everywhere (docs/05
/// §4).
public struct AlohaErrorStrip: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.alohaMetrics) private var metrics

    private let message: String
    private let retryLabel: String
    /// On nil the button is hidden: a strip with nothing to press is just a
    /// line of text, and "Retry" next to a server that never comes back is a
    /// lie.
    private let retry: (() -> Void)?

    public init(
        message: String,
        retryLabel: String = String(localized: "Retry", comment: "Error strip action"),
        retry: (() -> Void)? = nil
    ) {
        self.message = message
        self.retryLabel = retryLabel
        self.retry = retry
    }

    public var body: some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: AlohaSymbol.warning)
                .accessibilityHidden(true)

            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: AlohaMetrics.space2)

            if let retry {
                Button(action: retry) {
                    Text(retryLabel)
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
        }
        .foregroundStyle(palette.destructive)
        .padding(.horizontal, AlohaMetrics.space3)
        .padding(.vertical, AlohaMetrics.space2)
        .background(
            palette.surfaceRaised,
            in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous)
        )
        // The strip states what is wrong; it does not also shout twice.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(message))
    }
}

#Preview {
    VStack(spacing: 16) {
        AlohaErrorStrip(message: "The timeline could not be loaded.") {
            print("retry")
        }
        AlohaErrorStrip(message: "This cannot be retried from here.")
    }
    .padding()
}
