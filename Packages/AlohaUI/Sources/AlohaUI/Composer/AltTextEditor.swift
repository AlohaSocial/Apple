// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaIntelligence
import AlohaModels
import SwiftUI

/// Editing one attachment's description, with the on-device generator alongside.
///
/// What the device writes is a suggestion, never a description: it is shown
/// apart from the field, marked as generated, and goes nowhere until the
/// person accepts it as it is, takes it into the field to edit, or discards
/// it (docs/10 §4). The generator works from what Vision recognised, not
/// from the picture, and can be confidently wrong.
public struct AltTextEditor: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    private let attachment: MediaAttachment
    private let onSave: (String) -> Void
    private let onDiscardSuggestion: () -> Void
    private let onSuggest: (String) -> Void

    @State private var text: String
    /// The suggestion waiting for a decision, if any.
    @State private var suggestion: String?
    @State private var isGenerating = false
    /// The suggestion last taken into the field to edit. While the field
    /// still says exactly that, it is marked as generated.
    @State private var takenFromSuggestion: String?
    @State private var errorMessage: String?
    @State private var detent: PresentationDetent = .large
    @FocusState private var isEditing: Bool

    /// `suggestion` is one the composer already holds for this attachment;
    /// `onSuggest` is told about one written here, so closing the editor
    /// without deciding keeps it for later rather than losing it.
    public init(
        attachment: MediaAttachment, suggestion: String? = nil,
        onSave: @escaping (String) -> Void,
        onDiscardSuggestion: @escaping () -> Void = {},
        onSuggest: @escaping (String) -> Void = { _ in }
    ) {
        self.attachment = attachment
        self.onSave = onSave
        self.onDiscardSuggestion = onDiscardSuggestion
        self.onSuggest = onSuggest
        _text = State(initialValue: attachment.description ?? "")
        let hasOwn = !(attachment.description ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        _suggestion = State(initialValue: hasOwn ? nil : suggestion)
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
                    if let suggestion {
                        suggestionCard(suggestion)
                    } else {
                        editor
                    }

                    HStack {
                        Text(
                            "\(text.count)/\(AltTextGuidance.maximumCharacters)",
                            comment: "Alt text character count"
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(
                            text.count > AltTextGuidance.maximumCharacters
                                ? palette.destructive : palette.secondaryLabel
                        )
                        .opacity(suggestion == nil ? 1 : 0)
                        .accessibilityHidden(suggestion != nil)
                        Spacer()
                        if environment.intelligence.availability.isAvailable,
                            attachment.type == .image, suggestion == nil
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
                    // A suggestion is decided on its own buttons; Save
                    // beside it would leave unclear which text it keeps.
                    .disabled(
                        suggestion != nil || text.count > AltTextGuidance.maximumCharacters)
                }
            }
        }
        // Open tall, where the picture and the keyboard both fit; half height
        // is a drag away for checking the post underneath.
        .presentationDetents([.medium, .large], selection: $detent)
        // A description takes thought to write; a changed one leaves through
        // Save or Cancel, not a stray swipe.
        .interactiveDismissDisabled(text != (attachment.description ?? ""))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            if let takenFromSuggestion, takenFromSuggestion == text {
                // Taken in from a suggestion: still marked until the person
                // changes a word or saves it as it stands (docs/10 §4).
                Label {
                    Text("Generated — please check", comment: "Alt text generated notice")
                } icon: {
                    Image(systemName: AlohaSymbol.sparkles)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.accent)
            }

            TextEditor(text: $text)
                .focused($isEditing)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .background(palette.surfaceRaised)
                .clipShape(
                    RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous)
                )
                .accessibilityLabel(Text("Description", comment: "Alt text field label"))
        }
    }

    /// The suggestion, apart from the field and marked as generated, with
    /// the three things a person can do with it.
    private func suggestionCard(_ suggestion: String) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
            Label {
                Text("Suggested by this device", comment: "Alt text suggestion heading")
            } icon: {
                Image(systemName: AlohaSymbol.sparkles)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.accent)
            .accessibilityAddTraits(.isHeader)

            Text(verbatim: suggestion)
                .font(.body)
                .foregroundStyle(palette.label)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Text(
                "Written from what this device recognised, not from looking at the photo. Check it before you use it.",
                comment: "Alt text suggestion caveat"
            )
            .font(.caption)
            .foregroundStyle(palette.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AlohaMetrics.space2) { suggestionActions(suggestion) }
                VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                    suggestionActions(suggestion)
                }
            }
        }
        .padding(AlohaMetrics.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            palette.surfaceRaised,
            in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous)
                .strokeBorder(palette.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    @ViewBuilder
    private func suggestionActions(_ suggestion: String) -> some View {
        Button {
            onSave(suggestion)
            dismiss()
        } label: {
            Text("Accept", comment: "Alt text suggestion action")
        }
        .buttonStyle(.borderedProminent)
        .tint(palette.accent)
        .disabled(suggestion.count > AltTextGuidance.maximumCharacters)

        Button {
            text = suggestion
            takenFromSuggestion = suggestion
            self.suggestion = nil
            isEditing = true
        } label: {
            Text("Edit", comment: "Alt text suggestion action")
        }
        .buttonStyle(.bordered)

        Button(role: .destructive) {
            self.suggestion = nil
            onDiscardSuggestion()
        } label: {
            Text("Discard", comment: "Alt text suggestion action")
        }
        .buttonStyle(.bordered)
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
            suggestion = generated
            onSuggest(generated)
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
