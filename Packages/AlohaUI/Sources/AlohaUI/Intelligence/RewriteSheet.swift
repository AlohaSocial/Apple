// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaIntelligence
import SwiftUI

/// A rewrite is proposed, never applied in place: original above, proposal
/// below, with Replace / Copy / Cancel (docs/10 §3).
public struct RewriteSheet: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let original: String
    private let style: RewriteStyle
    private let maximumCharacters: Int
    private let intelligence: any IntelligenceProviding
    private let onReplace: (String) -> Void

    @State private var proposal = ""
    @State private var isWorking = true
    @State private var errorMessage: String?

    public init(
        original: String, style: RewriteStyle, maximumCharacters: Int,
        intelligence: any IntelligenceProviding, onReplace: @escaping (String) -> Void
    ) {
        self.original = original
        self.style = style
        self.maximumCharacters = maximumCharacters
        self.intelligence = intelligence
        self.onReplace = onReplace
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AlohaMetrics.space4) {
                    block(
                        title: String(
                            localized: "What you wrote", comment: "Rewrite sheet section"),
                        text: original, isProposal: false)

                    if isWorking {
                        HStack(spacing: AlohaMetrics.space2) {
                            ProgressView()
                            Text("Working on it…", comment: "Rewrite in progress")
                                .font(.footnote)
                                .foregroundStyle(palette.secondaryLabel)
                        }
                    } else if let errorMessage {
                        Label {
                            Text(errorMessage)
                        } icon: {
                            Image(systemName: AlohaSymbol.warning)
                        }
                        .font(.footnote)
                        .foregroundStyle(palette.destructive)
                    } else {
                        block(
                            title: String(localized: "Proposal", comment: "Rewrite sheet section"),
                            text: proposal, isProposal: true)
                    }
                }
                .padding(AlohaMetrics.space4)
            }
            .background(palette.background)
            .navigationTitle(Text(style.displayName))
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
                        onReplace(proposal)
                        dismiss()
                    } label: {
                        Text("Replace", comment: "Rewrite action")
                    }
                    .disabled(isWorking || proposal.isEmpty || errorMessage != nil)
                }
            }
            .task { await run() }
        }
    }

    private func block(title: String, text: String, isProposal: Bool) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.secondaryLabel)
            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AlohaMetrics.space3)
                .background(
                    isProposal ? palette.accentMuted.opacity(0.18) : palette.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous)
                )
                .textSelection(.enabled)
        }
    }

    private func run() async {
        isWorking = true
        defer { isWorking = false }
        do {
            proposal = try await intelligence.rewrite(
                original, style: style, maximumCharacters: maximumCharacters)
        } catch {
            switch IntelligenceError.classify(error) {
            case .cancelled:
                // The sheet closed; there is nobody to tell.
                return
            case .refused:
                // Shown plainly. No retry loop, no prompt gymnastics.
                errorMessage = String(
                    localized: "Apple Intelligence didn't want to rewrite that.",
                    comment: "Rewrite refused")
            case .tooLong:
                errorMessage = String(
                    localized: "That didn't fit in your server's character limit.",
                    comment: "Rewrite too long")
            case .unavailable:
                errorMessage = String(
                    localized: "Writing help isn't available on this device.",
                    comment: "Rewrite unavailable")
            case .contextExceeded:
                errorMessage = String(
                    localized: "That's too long to rewrite on this device.",
                    comment: "Rewrite input exceeded the on-device model's context")
            case let other:
                errorMessage =
                    IntelligenceMessages.transient(other)
                    ?? String(localized: "Couldn't rewrite that.", comment: "Rewrite failed")
            }
        }
    }
}

/// Thread and long-status summaries. Never cached, never shared, never inline.
public struct SummarySheet: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let passages: [String]
    private let intelligence: any IntelligenceProviding

    @State private var summary = ""
    @State private var isWorking = true
    @State private var errorMessage: String?

    public init(passages: [String], intelligence: any IntelligenceProviding) {
        self.passages = passages
        self.intelligence = intelligence
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
                    Label {
                        Text("Generated summary", comment: "Summary label")
                    } icon: {
                        Image(systemName: AlohaSymbol.sparkles)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.accent)

                    if isWorking {
                        ProgressView()
                    } else if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(palette.destructive)
                    } else {
                        Text(summary).font(.body)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AlohaMetrics.space4)
            }
            .navigationTitle(Text("Summary", comment: "Summary sheet title"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Read the full thread", comment: "Summary action")
                    }
                }
            }
            .task { await run() }
        }
        .presentationDetents([.medium, .large])
    }

    private func run() async {
        isWorking = true
        defer { isWorking = false }
        do {
            summary = try await intelligence.summarise(passages)
        } catch {
            switch IntelligenceError.classify(error) {
            case .cancelled:
                // The sheet closed before the summary was ready.
                return
            case .refused:
                errorMessage = String(
                    localized: "Apple Intelligence didn't want to summarise this.",
                    comment: "Summary refused by the on-device model's guardrails")
            case .contextExceeded:
                errorMessage = String(
                    localized: "This is too long to summarise on this device.",
                    comment: "Summary input exceeded the on-device model's context")
            case .unavailable:
                errorMessage = String(
                    localized: "Summaries aren't available on this device.",
                    comment: "Summary unavailable")
            case let other:
                errorMessage =
                    IntelligenceMessages.transient(other)
                    ?? String(localized: "Couldn't summarise that.", comment: "Summary failed")
            }
        }
    }
}

/// The failures that are about the moment rather than the text, worded the
/// same for every feature that meets them.
enum IntelligenceMessages {
    static func transient(_ error: IntelligenceError) -> String? {
        switch error {
        case .modelUnavailable:
            String(
                localized: "The on-device model isn't ready yet. Try again once it has downloaded.",
                comment: "On-device model assets missing or still downloading")
        case .busy:
            String(
                localized: "Apple Intelligence is busy. Try again in a moment.",
                comment: "On-device model rate-limited or handling another request")
        default:
            nil
        }
    }
}
