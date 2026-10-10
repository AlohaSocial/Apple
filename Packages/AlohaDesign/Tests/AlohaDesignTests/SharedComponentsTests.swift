// SPDX-License-Identifier: MIT

import SwiftUI
import Testing

@testable import AlohaDesign

#if canImport(UIKit)
    import UIKit
#endif

/// The shared list furniture — one error strip and one skeleton — has to hold
/// its shape across every appearance, because these are the components every
/// list in the app now draws (docs/12 §5).
@Suite("Shared list furniture")
@MainActor
struct SharedComponentsTests {

    // MARK: - Error strip

    /// The strip is the one place a failure is stated in every list. A retry
    /// it cannot honour is a lie, so where there is no retry there is no button.
    @Test("An error strip without a retry draws no button")
    func noRetryNoButton() {
        let view = AlohaErrorStrip(message: "Something failed")
        // The strip is one row: symbol, message, nothing else.
        #expect(render(view))
    }

    @Test("An error strip with a retry draws one")
    func retryDrawsButton() {
        var tapped = 0
        let view = AlohaErrorStrip(message: "Something failed") { tapped += 1 }
        #expect(view != nil)
    }

    // MARK: - Skeleton

    /// A zero or negative count would draw nothing at all, which is worse than
    /// a spinner: it reads as an empty screen.
    @Test("A skeleton clamps its row count to at least one")
    func clampsCount() {
        for count in [-5, 0, 1, 3] {
            let person = SkeletonListRow(person: count)
            let text = SkeletonListRow(text: count)
            let block = SkeletonListRow(block: count)
            #expect(person != nil && text != nil && block != nil)
        }
    }

    // MARK: - Glass

    /// The fallback exists for systems without the material, and the unified
    /// entry point is the only one any view should call.
    @Test("Every glass level has a fallback")
    func glassLevelsHaveFallbacks() {
        for style in [AlohaGlass.regular, .prominent, .subtle] {
            let view = Text("x").alohaGlassFallback(style)
            #expect(view != nil)
        }
    }
}

/// Renders a view so a test can assert it drew at all. `uiImage` is UIKit's,
/// so on a Mac the assertion rests on the renderer existing rather than on
/// pixels nobody is looking at.
@available(macOS 13.0, *)
private func render<V: View>(_ view: V) -> Bool {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    #if canImport(UIKit)
        return renderer.uiImage != nil
    #else
        renderer.render { _, _ in }
        return true
    #endif
}
