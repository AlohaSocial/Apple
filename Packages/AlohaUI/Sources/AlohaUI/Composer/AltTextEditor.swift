// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaIntelligence
import AlohaModels
import SwiftUI

/// Editing one attachment's description, with the on-device generator alongside.
public struct AltTextEditor: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    private let attachment: MediaAttachment
    private let onSave: (String) -> Void

    @State private var text: String
    @State private var isGenerating = false
    @State private var wasGenerated = false
    @State private var errorMessage: String?

    public init(attachment: MediaAttachment, onSave: @escaping (String) -> Void) {
        self.attachment = attachment
        self.onSave = onSave
        _text = State(initialValue: attachment.description ?? "")
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RemoteImage(
                    url: attachment.displayImageURL,
                    blurhash: attachment.blurhash, contentMode: .fit
                )
                .frame(maxHeight: 220)
                .background(palette.surfaceRaised)

                VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                    if wasGenerated {
                        // Marked as generated until the person edits or
                        // confirms it (docs/10 §4).
                        Label {
                            Text("Generated — please check", comment: "Alt text generated notice")
                        } icon: {
                            Image(systemName: AlohaSymbol.sparkles)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.accent)
                    }

                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .background(palette.surfaceRaised)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: AlohaMetrics.cornerSmall, style: .continuous)
                        )
                        .onChange(of: text) { _, _ in wasGenerated = false }

                    HStack {
                        Text(
                            "\(text.count)/\(AltTextGuidance.maximumCharacters)",
                            comment: "Alt text character count"
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(
                            text.count > AltTextGuidance.maximumCharacters
                                ? palette.destructive : palette.secondaryLabel)
                        Spacer()
                        if environment.intelligence.availability.isAvailable,
                            attachment.type == .image
                        {
                            Button {
                                Task { await generate() }
                            } label: {
                                if isGenerating {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label {
                                        Text("Describe this", comment: "Alt text generate action")
                                    } icon: {
                                        Image(systemName: AlohaSymbol.sparkles)
                                    }
                                }
                            }
                            .font(.footnote)
                            .disabled(isGenerating)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(palette.destructive)
                    }

                    Text(
                        "Describe what's in the image and what it's for. People using a screen reader rely on this.",
                        comment: "Alt text guidance"
                    )
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                }
                .padding(AlohaMetrics.space4)

                Spacer()
            }
            .background(palette.background)
            .navigationTitle(Text("Description", comment: "Alt text editor title"))
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
                        onSave(text)
                        dismiss()
                    } label: {
                        Text("Save", comment: "Sheet action")
                    }
                    .disabled(text.count > AltTextGuidance.maximumCharacters)
                }
            }
        }
    }

    private func generate() async {
        isGenerating = true
        defer { isGenerating = false }

        guard let url = attachment.displayImageURL,
            let (data, _) = try? await URLSession.shared.data(from: url)
        else {
            errorMessage = String(
                localized: "Couldn't read that image.", comment: "Alt text generation failure")
            return
        }

        do {
            let generated = try await environment.intelligence.describeImage(data)
            guard AltTextGuidance.looksAcceptable(generated) else {
                errorMessage = String(
                    localized: "That description didn't come out usable.",
                    comment: "Alt text generation rejected")
                return
            }
            text = generated
            wasGenerated = true
            errorMessage = nil
        } catch IntelligenceError.unavailable {
            errorMessage = String(
                localized: "Describing images isn't available on this device yet.",
                comment: "Alt text generation unavailable")
        } catch {
            errorMessage = String(
                localized: "Couldn't describe that image.", comment: "Alt text generation failure")
        }
    }
}
