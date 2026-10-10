// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Who may quote one of your posts from now on, and the quotes already made,
/// each of which can be detached (docs/02 §2).
public struct QuoteControlsSheet: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let status: Status
    private let session: AccountSession

    @State private var policy: QuoteApprovalPolicy
    @State private var quotes: [Status] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var revoking: Set<String> = []
    @State private var errorMessage: String?
    @State private var retryPolicy: QuoteApprovalPolicy?
    @State private var retryQuote: Status?

    public init(status: Status, session: AccountSession) {
        self.status = status
        self.session = session
        _policy = State(
            initialValue: status.quoteApprovalPolicy.flatMap { QuoteApprovalPolicy(rawValue: $0) }
                ?? .public)
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(
                        selection: Binding(
                            get: { policy },
                            set: { new in
                                guard !isLoading, !isSaving, revoking.isEmpty, new != policy else {
                                    return
                                }
                                let previous = policy
                                policy = new
                                isSaving = true
                                Task { await save(new, revertingTo: previous) }
                            })
                    ) {
                        Text("Anybody", comment: "Quote policy").tag(QuoteApprovalPolicy.public)
                        Text("People who follow me", comment: "Quote policy")
                            .tag(QuoteApprovalPolicy.followers)
                        Text("Nobody but me", comment: "Quote policy").tag(
                            QuoteApprovalPolicy.nobody)
                    } label: {
                        Text("Who may quote this", comment: "Quote policy picker")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .disabled(isLoading || isSaving || !revoking.isEmpty)
                } header: {
                    Text("Who may quote this", comment: "Quote controls section")
                } footer: {
                    Text(
                        "This decides what happens from now on. It does not take back a quote somebody has already posted.",
                        comment: "Quote policy footer")
                }

                Section {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(palette.destructive)
                        Button("Try again") { retry() }
                            .buttonStyle(.glass)
                            .disabled(isLoading || isSaving || !revoking.isEmpty)
                    }
                    ForEach(quotes) { quote in
                        row(quote)
                    }
                    if isLoading && quotes.isEmpty { ProgressView() }
                    if quotes.isEmpty && !isLoading && errorMessage == nil {
                        Text("Nobody has quoted this yet.", comment: "Quote controls empty state")
                            .font(.footnote)
                            .foregroundStyle(palette.tertiaryLabel)
                    }
                } header: {
                    Text("Quotes so far", comment: "Quote controls section")
                }
            }
            .alohaGround(palette)
            .navigationTitle(Text("Quotes", comment: "Screen title"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", comment: "Sheet action")
                    }
                    .disabled(isSaving || !revoking.isEmpty)
                }
            }
            .task { await load() }
            .interactiveDismissDisabled(isSaving || !revoking.isEmpty)
        }
    }

    private func row(_ quote: Status) -> some View {
        HStack(alignment: .top, spacing: AlohaMetrics.space3) {
            AvatarView(account: quote.account, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(quote.account.bestDisplayName)
                    .font(AlohaType.name)
                    .lineLimit(1)
                Text(excerpt(quote))
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            Button(role: .destructive) {
                Task { await revoke(quote) }
            } label: {
                Text("Detach", comment: "Quote controls action")
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.glass)
            .disabled(isLoading || isSaving || revoking.contains(quote.id))
            .accessibilityLabel(
                Text(
                    "Detach the quote by \(quote.account.bestDisplayName)",
                    comment: "Quote controls action"))
        }
        .padding(.vertical, AlohaMetrics.space1)
    }

    private func excerpt(_ quote: Status) -> String {
        let text = StatusHTMLParser().plainText(quote.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 140 ? String(text.prefix(140)) + "…" : text
    }

    private func load() async {
        guard !isSaving, revoking.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        retryPolicy = nil
        retryQuote = nil
        defer { isLoading = false }
        do {
            let response = try await session.client.decode(
                LossyArray<Status>.self, from: Endpoint.statusExtras.quotes(status.id)
            ).elements
            guard !Task.isCancelled else { return }
            quotes = response
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "Quotes could not be loaded. Please try again.")
        }
    }

    private func save(_ new: QuoteApprovalPolicy, revertingTo previous: QuoteApprovalPolicy) async {
        isSaving = true
        errorMessage = nil
        retryPolicy = nil
        retryQuote = nil
        defer { isSaving = false }
        do {
            let updated = try await session.client.decode(
                Status.self, from: Endpoint.statusExtras.setQuotePolicy(status.id, new))
            policy =
                updated.quoteApprovalPolicy.flatMap { QuoteApprovalPolicy(rawValue: $0) } ?? new
            try? await session.timelineStore.updateStatus(accountID: session.id, status: updated)
            errorMessage = nil
        } catch {
            policy = previous
            retryPolicy = new
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "The quote setting could not be saved. Please try again.")
        }
    }

    private func revoke(_ quote: Status) async {
        guard !isLoading, !isSaving,
            let index = quotes.firstIndex(where: { $0.id == quote.id }),
            revoking.insert(quote.id).inserted
        else { return }
        defer { revoking.remove(quote.id) }
        errorMessage = nil
        retryPolicy = nil
        retryQuote = nil
        quotes.removeAll { $0.id == quote.id }
        do {
            _ = try await session.client.send(
                Endpoint.statusExtras.revokeQuote(status.id, quoting: quote.id))
        } catch {
            retryQuote = quote
            if !quotes.contains(where: { $0.id == quote.id }) {
                quotes.insert(quote, at: min(index, quotes.count))
            }
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "The quote could not be detached. Please try again.")
        }
    }

    private func retry() {
        guard !isLoading, !isSaving, revoking.isEmpty else { return }
        if let new = retryPolicy {
            let previous = policy
            policy = new
            isSaving = true
            Task { await save(new, revertingTo: previous) }
        } else if let quote = retryQuote {
            Task { await revoke(quote) }
        } else {
            Task { await load() }
        }
    }
}
