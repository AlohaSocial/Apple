// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

/// Which part of a picture a cropped preview keeps in frame. Drag the
/// crosshair onto the subject; the point is stored as Mastodon's `x,y` in
/// −1…1 with the origin at the centre.
struct FocalPointEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alohaPalette) private var palette

    let attachment: MediaAttachment
    let initial: CGPoint?
    let onSave: (CGPoint) -> Void

    /// In −1…1, as the server wants it.
    @State private var point: CGPoint

    init(attachment: MediaAttachment, initial: CGPoint?, onSave: @escaping (CGPoint) -> Void) {
        self.attachment = attachment
        self.initial = initial
        self.onSave = onSave
        _point = State(
            initialValue: initial
                ?? attachment.meta?.focus.map { CGPoint(x: $0.x, y: $0.y) }
                ?? .zero)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: AlohaMetrics.space3) {
                GeometryReader { proxy in
                    ZStack {
                        RemoteImage(
                            url: attachment.displayImageURL,
                            blurhash: attachment.blurhash,
                            contentMode: .fit,
                            accessibilityText: attachment.description)

                        crosshair
                            .position(position(in: proxy.size))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0).onChanged { value in
                            point = normalised(value.location, in: proxy.size)
                        }
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Focal point", comment: "Focal point editor"))
                    .accessibilityValue(
                        Text(
                            "\(Int((point.x + 1) * 50)) percent across, \(Int((1 - point.y) * 50)) percent down",
                            comment: "Focal point position")
                    )
                    .accessibilityAdjustableAction { direction in
                        // Keyboard and switch users nudge it along one axis.
                        switch direction {
                        case .increment: point.x = min(1, point.x + 0.1)
                        case .decrement: point.x = max(-1, point.x - 0.1)
                        @unknown default: break
                        }
                    }
                }
                .background(Color.black)
                .clipShape(
                    RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
                )
                .padding(.horizontal, AlohaMetrics.space3)

                Text(
                    "Drag the crosshair onto what matters. Cropped previews keep that part in frame.",
                    comment: "Focal point hint"
                )
                .font(.footnote)
                .foregroundStyle(palette.secondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AlohaMetrics.space4)

                Button {
                    withAnimation { point = .zero }
                } label: {
                    Text("Centre", comment: "Focal point reset")
                }
                .disabled(point == .zero)
            }
            .padding(.vertical, AlohaMetrics.space3)
            .background(palette.background)
            .navigationTitle(Text("Focal point", comment: "Screen title"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel", comment: "Sheet action")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(point)
                        dismiss()
                    } label: {
                        Text("Save", comment: "Sheet action")
                    }
                }
            }
        }
    }

    private var crosshair: some View {
        ZStack {
            Circle()
                .strokeBorder(.white, lineWidth: 2)
                .frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.5), radius: 3)
            Circle()
                .fill(palette.accent)
                .frame(width: 8, height: 8)
        }
        .allowsHitTesting(false)
    }

    /// The image is drawn to fit, so the crosshair is placed within the
    /// letterboxed rectangle, not the whole frame.
    private func imageRect(in size: CGSize) -> CGRect {
        let aspect = attachment.displayAspectRatio
        var drawn = CGSize(width: size.width, height: size.width / aspect)
        if drawn.height > size.height {
            drawn = CGSize(width: size.height * aspect, height: size.height)
        }
        return CGRect(
            x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
            width: drawn.width, height: drawn.height)
    }

    private func position(in size: CGSize) -> CGPoint {
        let rect = imageRect(in: size)
        return CGPoint(
            x: rect.midX + point.x * rect.width / 2,
            y: rect.midY - point.y * rect.height / 2)
    }

    private func normalised(_ location: CGPoint, in size: CGSize) -> CGPoint {
        let rect = imageRect(in: size)
        guard rect.width > 0, rect.height > 0 else { return .zero }
        let x = (location.x - rect.midX) / (rect.width / 2)
        let y = -(location.y - rect.midY) / (rect.height / 2)
        return CGPoint(x: min(max(x, -1), 1), y: min(max(y, -1), 1))
    }
}
