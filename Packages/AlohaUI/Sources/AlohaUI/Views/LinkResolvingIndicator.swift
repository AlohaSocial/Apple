// SPDX-License-Identifier: MIT

import AlohaDesign
import SwiftUI

/// Says that a tapped link is being looked up on the reader's server, for
/// the few seconds `FediverseLinkResolver` may take, with the browser one
/// tap away for anyone who would rather not wait. It floats at the top,
/// over the navigation bar, because the bottom is the tab bar's on a phone.
struct LinkResolvingIndicator: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let resolver: FediverseLinkResolver
    let openInBrowser: (URL) -> Void

    var body: some View {
        ZStack {
            if let url = resolver.pending {
                capsule(url)
                    .transition(
                        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(
            reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.25),
            value: resolver.pending
        )
        .onChange(of: resolver.pending) { _, url in
            guard url != nil else { return }
            AccessibilityNotification.Announcement(
                String(localized: "Opening link", comment: "Link lookup announcement")
            ).post()
        }
    }

    private func capsule(_ url: URL) -> some View {
        HStack(spacing: AlohaMetrics.space3) {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
            Text("Opening in Aloha Social…", comment: "Link lookup progress")
                .font(.footnote.weight(.medium))
                .foregroundStyle(palette.label)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                resolver.cancel()
                openInBrowser(url)
            } label: {
                Text("Open in browser", comment: "Link lookup action")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AlohaMetrics.space4)
        .padding(.vertical, AlohaMetrics.space3)
        .background(palette.surfaceRaised, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.horizontal, AlohaMetrics.space4)
        .padding(.top, AlohaMetrics.space2)
        .accessibilityElement(children: .contain)
    }
}
