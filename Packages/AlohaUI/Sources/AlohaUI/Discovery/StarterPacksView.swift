// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Curated bundles of accounts to follow in one go. The list route names the
/// packs without resolving anybody; opening one does the resolution.
public struct StarterPacksView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var packs: [StarterPack] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init(session: AccountSession, onAction: @escaping (StatusRowAction) -> Void) {
        self.session = session
        self.onAction = onAction
    }

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: AlohaMetrics.space3)]

    public var body: some View {
        ScrollView {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(palette.destructive)
                    .padding(AlohaMetrics.space3)
            }

            LazyVGrid(columns: columns, spacing: AlohaMetrics.space3) {
                ForEach(packs) { pack in
                    NavigationLink(value: Route.starterPack(slug: pack.slug)) {
                        card(pack)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(pack.name))
                }
            }
            .padding(AlohaMetrics.space3)

            if isLoading && packs.isEmpty {
                ProgressView().padding(.top, AlohaMetrics.space6)
            } else if packs.isEmpty {
                ContentUnavailableView {
                    Text("No starter packs", comment: "Empty starter packs")
                } description: {
                    Text(
                        "Your administrator hasn't put any together yet.",
                        comment: "Empty starter packs detail")
                }
                .padding(.top, AlohaMetrics.space6)
            }
        }
        .background(palette.background)
        .navigationTitle(Text("Starter packs", comment: "Screen title"))
        .task { await load() }
        .refreshable { await load() }
    }

    private func card(_ pack: StarterPack) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            Image(systemName: "person.3.fill")
                .font(.title2)
                .foregroundStyle(palette.accent)
            Text(pack.name)
                .font(AlohaType.name)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if !pack.description.isEmpty {
                Text(pack.description)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Text("^[\(pack.size) account](inflect: true)", comment: "Starter pack size")
                .font(AlohaType.meta)
                .foregroundStyle(palette.tertiaryLabel)
        }
        .padding(AlohaMetrics.space3)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(
            palette.surfaceRaised,
            in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous))
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            packs = try await session.client.decode(
                LossyArray<StarterPack>.self, from: Endpoint.discovery.starterPacks
            ).elements
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}
