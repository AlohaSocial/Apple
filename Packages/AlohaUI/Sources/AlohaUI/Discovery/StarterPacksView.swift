// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Curated bundles of accounts to follow in one go. The list route names the
/// packs without resolving anybody; opening one does the resolution.
public struct StarterPacksView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                errorStrip(errorMessage)
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
            // The last row should not end where the bar at the foot begins.
            .padding(.bottom, AlohaMetrics.space4)

            if isLoading && packs.isEmpty {
                // The shape of the grid arriving: six cards, rather than a
                // spinner in the middle of nothing.
                SkeletonListRow(block: 4)
                    .padding(AlohaMetrics.space3)
            } else if packs.isEmpty && errorMessage == nil {
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

    private func errorStrip(_ message: String) -> some View {
        AlohaErrorStrip(message: message) {
            Task { await load() }
        }
        .padding(AlohaMetrics.space3)
    }

    private func card(_ pack: StarterPack) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            // The first three accounts, as faces: a pack is a set of people,
            // and a card that shows them is more inviting than an icon.
            HStack(spacing: -AlohaMetrics.space2) {
                ForEach(pack.accounts.prefix(3)) { account in
                    AvatarView(account: account, size: 32)
                        .overlay(
                            Circle().strokeBorder(palette.background, lineWidth: 2)
                        )
                }
                Spacer(minLength: 0)
            }

            Text(pack.name)
                .font(AlohaType.name)
                // A name the reader asked to be bigger is not a name to cut
                // in half.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
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
        // A card is a layer, with a hairline so its edge reads as an edge.
        .unifiedGlass(
            .regular,
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
