// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

/// The seven adjustments, previewed live and baked in when the choice settles.
///
/// The preview is a shader over the picture already on screen, so flicking
/// through the row costs nothing; only Save redraws the pixels and puts a new
/// copy up. That is the same division the web makes — a CSS filter on the
/// `<img>`, and the same declaration handed to a canvas on the way out —
/// because two implementations of the same seven numbers would drift.
struct PhotoFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alohaPalette) private var palette

    let attachment: MediaAttachment
    let uploader: ComposerUploader

    @State private var choice: PhotoFilter = .none
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: AlohaMetrics.space4) {
                choice.preview(
                    RemoteImage(url: attachment.previewURL ?? attachment.url)
                        .aspectRatio(contentMode: .fit)
                )
                .clipShape(RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium))
                .padding(.horizontal, AlohaMetrics.space4)

                ScrollView(.horizontal) {
                    HStack(spacing: AlohaMetrics.space3) {
                        ForEach(PhotoFilter.allCases) { filter in
                            Button {
                                choice = filter
                            } label: {
                                VStack(spacing: AlohaMetrics.space1) {
                                    filter.preview(
                                        RemoteImage(url: attachment.previewURL ?? attachment.url)
                                    )
                                    .frame(width: 64, height: 64)
                                    .clipShape(
                                        RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall)
                                            .strokeBorder(
                                                choice == filter ? palette.accent : .clear,
                                                lineWidth: 3)
                                    }
                                    Text(filter.name)
                                        .font(AlohaType.micro)
                                        .foregroundStyle(
                                            choice == filter
                                                ? palette.accent : palette.secondaryLabel)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(choice == filter ? [.isSelected] : [])
                        }
                    }
                    .padding(.horizontal, AlohaMetrics.space4)
                }
                .scrollIndicators(.hidden)

                Text(
                    "An adjustment is baked into the copy that is posted; the original stays on your device.",
                    comment: "Photo filter explanation"
                )
                .font(AlohaType.meta)
                .foregroundStyle(palette.secondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AlohaMetrics.space4)

                Spacer(minLength: 0)
            }
            .padding(.top, AlohaMetrics.space4)
            .background(palette.background)
            .navigationTitle(Text("Adjust", comment: "Screen title"))
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
                        Task {
                            isSaving = true
                            await uploader.applyFilter(choice, to: attachment.id)
                            isSaving = false
                            dismiss()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save", comment: "Sheet action")
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .task { choice = uploader.filter(for: attachment.id) }
        }
    }
}
