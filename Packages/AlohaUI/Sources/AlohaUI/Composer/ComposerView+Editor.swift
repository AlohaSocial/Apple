// SPDX-License-Identifier: MIT

import AlohaDesign
import SwiftUI

/// The text editor, the completions offered above the keyboard, and
/// putting a snippet where the cursor is.
extension ComposerView {
    /// The editor stays on a plain `String`, deliberately.
    ///
    /// A post is plain text on the wire, and an `AttributedString` editor
    /// would offer formatting and Genmoji the server cannot carry. A Genmoji
    /// is a picture with no faithful text form — its description is not what
    /// was chosen — so rather than quietly turning a picture into words at
    /// posting time, the editor does not offer one. What an attributed editor
    /// was wanted for is the selection, and a `String` editor has that too.
    var editor: some View {
        TextEditor(text: $model.text, selection: $selection)
            .focused($isEditorFocused)
            .accessibilityLabel(Text("What's happening?", comment: "Composer placeholder"))
            .scrollContentBackground(.hidden)
            #if os(iOS) || os(macOS) || os(visionOS)
                // Proofread and rewrite in place, in the system's own panel.
                .writingToolsBehavior(.complete)
            #endif
            .padding(.horizontal, AlohaMetrics.space3)
            .padding(.vertical, AlohaMetrics.space2)
            .font(.body)
            // `TextEditor` takes no prompt, so the placeholder is drawn over
            // it — and hidden from VoiceOver, which already reads it as the
            // editor's label.
            .overlay(alignment: .topLeading) {
                if model.text.isEmpty {
                    Text("What's happening?", comment: "Composer placeholder")
                        .foregroundStyle(palette.tertiaryLabel)
                        .padding(.horizontal, AlohaMetrics.space4)
                        .padding(.vertical, AlohaMetrics.space3 + 2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 140)
            #if os(iOS)
                // Above the keyboard, where a suggestion bar belongs, rather
                // than over the last lines being typed.
                .toolbar {
                    if !model.completions.isEmpty {
                        ToolbarItem(placement: .keyboard) { completionBar }
                    }
                }
            #else
                .overlay(alignment: .bottom) {
                    if !model.completions.isEmpty {
                        completionBar.background(.thinMaterial)
                    }
                }
            #endif
    }

    /// Puts a snippet where the cursor is, replacing a selection, and leaves
    /// the cursor after it.
    func insertAtCursor(_ snippet: String) {
        var range: Range<String.Index>?
        if case .selection(let selected) = selection?.indices,
            selected.upperBound <= model.text.endIndex
        {
            range = selected
        }
        let result = ComposerTextInsertion.inserting(snippet, into: model.text, replacing: range)
        model.text = result.text
        let cursor =
            model.text.index(
                model.text.startIndex, offsetBy: result.cursorOffset,
                limitedBy: model.text.endIndex) ?? model.text.endIndex
        selection = TextSelection(insertionPoint: cursor)
    }

    private var completionBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AlohaMetrics.space2) {
                ForEach(model.completions, id: \.self) { completion in
                    Button {
                        model.apply(completion: completion)
                    } label: {
                        Text(completion)
                            .font(.footnote)
                            .padding(.horizontal, AlohaMetrics.space3)
                            .padding(.vertical, AlohaMetrics.space1)
                            .background(palette.surfaceRaised, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AlohaMetrics.space3)
        }
        .scrollIndicators(.hidden)
        .frame(minHeight: 40)
    }
}
