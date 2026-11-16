// SPDX-License-Identifier: MIT

import AlohaMedia
import SwiftUI

#if canImport(VisionKit) && (os(iOS) || os(macOS))
    import VisionKit

    /// Live Text and Visual Look Up over the picture on screen in the media
    /// viewer: text in a photograph or a screenshot can be selected, copied,
    /// translated and looked up, a link or a phone number in it followed,
    /// and a subject — a plant, a landmark, a pet — looked up.
    ///
    /// The analysis runs on the device (VisionKit), and only for the picture
    /// that is on screen: a page the reader swipes past is never analysed,
    /// and leaving a page cancels its analysis. It reads the original at
    /// `url` at the size the screen can show, rather than the server's
    /// preview, which is often too small for text in a screenshot to be
    /// legible to the recogniser.
    ///
    /// Sized to the picture itself, not the page, so the system's Live Text
    /// button sits on the picture's corner and a tap on the black around it
    /// still belongs to the viewer.
    struct LiveTextOverlay: View {
        let url: URL?
        /// Whether this page is the one on screen. Nothing happens otherwise.
        let isActive: Bool
        /// The viewer's controls are away; the Live Text button goes with them.
        let isChromeHidden: Bool

        @Environment(\.displayScale) private var displayScale
        @State private var analysis: ImageAnalysis?
        @State private var imageSize: CGSize?
        @State private var pageSize: CGSize = .zero

        var body: some View {
            Color.clear
                .onGeometryChange(for: CGSize.self) {
                    $0.size
                } action: {
                    pageSize = $0
                }
                .overlay {
                    if let analysis, let imageSize, isActive {
                        LiveTextInteractionView(
                            analysis: analysis, isChromeHidden: isChromeHidden
                        )
                        .aspectRatio(imageSize, contentMode: .fit)
                    }
                }
                .task(id: AnalysisKey(url: url, isActive: isActive, hasSize: pageSize != .zero)) {
                    await analyse()
                }
        }

        private struct AnalysisKey: Hashable {
            let url: URL?
            let isActive: Bool
            let hasSize: Bool
        }

        private func analyse() async {
            guard isActive, analysis == nil, let url, pageSize != .zero,
                ImageAnalyzer.isSupported
            else { return }
            // The screen's own pixels, capped where a larger decode would
            // cost memory and buy the recogniser nothing.
            let longest = min(max(pageSize.width, pageSize.height) * displayScale, 4096)
            guard
                let image = await ImageLoader.shared.image(
                    for: url, targetSize: CGSize(width: longest, height: longest), scale: 1),
                !Task.isCancelled
            else { return }
            let configuration = ImageAnalyzer.Configuration([
                .text, .machineReadableCode, .visualLookUp,
            ])
            // The loader applies the EXIF orientation when it decodes, so the
            // picture is already the right way up.
            guard
                let result = try? await LiveTextAnalyzer.shared.analyze(
                    image, orientation: .up, configuration: configuration),
                !Task.isCancelled
            else { return }
            imageSize = CGSize(width: image.width, height: image.height)
            analysis = result
        }
    }

    /// One analyser for the app: it is costly to make, and the viewer only
    /// ever analyses one picture at a time.
    enum LiveTextAnalyzer {
        static let shared = ImageAnalyzer()
    }

    #if os(iOS)
        private struct LiveTextInteractionView: UIViewRepresentable {
            let analysis: ImageAnalysis
            let isChromeHidden: Bool

            func makeUIView(context: Context) -> LiveTextHostView {
                LiveTextHostView()
            }

            func updateUIView(_ view: LiveTextHostView, context: Context) {
                if view.interaction.analysis !== analysis {
                    view.interaction.analysis = analysis
                    view.interaction.preferredInteractionTypes = .automatic
                }
                view.interaction.setSupplementaryInterfaceHidden(isChromeHidden, animated: true)
            }
        }

        /// A transparent view the size of the picture, carrying the
        /// interaction. It only claims a touch that lands on something the
        /// analysis found — text, a code, a subject — or on the system's own
        /// buttons, so a tap anywhere else still toggles the viewer's
        /// controls and a double tap still zooms.
        final class LiveTextHostView: UIView, ImageAnalysisInteractionDelegate {
            let interaction = ImageAnalysisInteraction()

            override init(frame: CGRect) {
                super.init(frame: frame)
                backgroundColor = .clear
                interaction.delegate = self
                addInteraction(interaction)
            }

            @available(*, unavailable)
            required init?(coder: NSCoder) { nil }

            override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
                let hit = super.hitTest(point, with: event)
                guard hit === self else { return hit }
                return interaction.hasInteractiveItem(at: point)
                    || interaction.hasActiveTextSelection ? self : nil
            }

            /// The whole view is the picture: it is laid out at the picture's
            /// own aspect ratio.
            func contentsRect(for interaction: ImageAnalysisInteraction) -> CGRect {
                CGRect(x: 0, y: 0, width: 1, height: 1)
            }
        }
    #elseif os(macOS)
        private struct LiveTextInteractionView: NSViewRepresentable {
            let analysis: ImageAnalysis
            let isChromeHidden: Bool

            func makeNSView(context: Context) -> LiveTextHostView {
                LiveTextHostView()
            }

            func updateNSView(_ view: LiveTextHostView, context: Context) {
                if view.overlay.analysis !== analysis {
                    view.overlay.analysis = analysis
                    view.overlay.preferredInteractionTypes = .automatic
                }
                view.overlay.setSupplementaryInterfaceHidden(isChromeHidden, animated: true)
            }
        }

        /// The Mac's overlay, the size of the picture, in a view of its own
        /// (the overlay class is final). It takes the mouse only over text,
        /// a code or a subject, so a click elsewhere still belongs to the
        /// viewer.
        final class LiveTextHostView: NSView, ImageAnalysisOverlayViewDelegate {
            let overlay = ImageAnalysisOverlayView()

            override init(frame: NSRect) {
                super.init(frame: frame)
                overlay.delegate = self
                overlay.autoresizingMask = [.width, .height]
                overlay.frame = bounds
                addSubview(overlay)
            }

            @available(*, unavailable)
            required init?(coder: NSCoder) { nil }

            override func hitTest(_ point: NSPoint) -> NSView? {
                guard let hit = super.hitTest(point) else { return nil }
                guard hit === overlay || hit === self else { return hit }
                let local = overlay.convert(point, from: superview)
                return overlay.hasInteractiveItem(at: local) || overlay.hasActiveTextSelection
                    ? hit : nil
            }

            func contentsRect(for overlayView: ImageAnalysisOverlayView) -> CGRect {
                CGRect(x: 0, y: 0, width: 1, height: 1)
            }
        }
    #endif
#endif

extension View {
    /// Live Text and Visual Look Up over a picture in the media viewer, where
    /// VisionKit has them (iPhone, iPad and the Mac); nothing elsewhere.
    @ViewBuilder
    func liveText(url: URL?, isActive: Bool, isChromeHidden: Bool) -> some View {
        #if canImport(VisionKit) && (os(iOS) || os(macOS))
            overlay {
                LiveTextOverlay(url: url, isActive: isActive, isChromeHidden: isChromeHidden)
            }
        #else
            self
        #endif
    }
}
