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
    @State private var errorMessage: String?

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
                    Picker(selection: $policy) {
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
                    .disabled(isSaving)
                    .onChange(of: policy) { _, new in Task { await save(new) } }
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
                    }
                    ForEach(quotes) { quote in
                        row(quote)
                    }
                    if quotes.isEmpty && !isLoading {
                        Text("Nobody has quoted this yet.", comment: "Quote controls empty state")
                            .font(.footnote)
                            .foregroundStyle(palette.tertiaryLabel)
                    }
                } header: {
                    Text("Quotes so far", comment: "Quote controls section")
                }
            }
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
                }
            }
            .task { await load() }
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
        isLoading = true
        defer { isLoading = false }
        do {
            quotes = try await session.client.decode(
                LossyArray<Status>.self, from: Endpoint.statusExtras.quotes(status.id)
            ).elements
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func save(_ new: QuoteApprovalPolicy) async {
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await session.client.decode(
                Status.self, from: Endpoint.statusExtras.setQuotePolicy(status.id, new))
            try? await session.timelineStore.updateStatus(accountID: session.id, status: updated)
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func revoke(_ quote: Status) async {
        let before = quotes
        quotes.removeAll { $0.id == quote.id }
        do {
            _ = try await session.client.send(
                Endpoint.statusExtras.revokeQuote(status.id, quoting: quote.id))
        } catch {
            quotes = before
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}
