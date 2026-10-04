// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Who watched one of your stories. Told to the poster and to nobody else.
struct StoryViewersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alohaPalette) private var palette

    let story: Story
    let session: AccountSession

    @State private var viewers: [Account] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(palette.destructive)
                        .listRowBackground(palette.background)
                }
                ForEach(viewers) { account in
                    accountRow(account)
                }
                if viewers.isEmpty && !isLoading && errorMessage == nil {
                    Text("Nobody has watched this yet.", comment: "Empty story viewers")
                        .font(.footnote)
                        .foregroundStyle(palette.tertiaryLabel)
                        .listRowBackground(palette.background)
                }
            }
            .listStyle(.plain)
            .alohaGround(palette)
            .navigationTitle(Text("Seen by", comment: "Story viewers title"))
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
        #if os(macOS)
            .frame(minWidth: 360, minHeight: 420)
        #endif
    }

    private func accountRow(_ account: Account) -> some View {
        HStack(spacing: AlohaMetrics.space3) {
            AvatarView(account: account, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(account.bestDisplayName)
                    .font(AlohaType.name)
                    .lineLimit(1)
                Text(account.qualifiedHandle(localHost: session.snapshot.instanceHost))
                    .font(AlohaType.meta)
                    .foregroundStyle(palette.tertiaryLabel)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .listRowBackground(palette.background)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            viewers = try await session.client.decode(
                LossyArray<Account>.self, from: Endpoint.storyExtras.viewers(story.id)
            ).elements
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}

/// Reactions and replies to one of your stories.
struct StoryReactionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alohaPalette) private var palette

    let story: Story
    let session: AccountSession

    @State private var reactions: [StoryReaction] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(palette.destructive)
                        .listRowBackground(palette.background)
                }
                ForEach(reactions) { reaction in
                    row(reaction)
                }
                if reactions.isEmpty && !isLoading && errorMessage == nil {
                    Text("No reactions yet.", comment: "Empty story reactions")
                        .font(.footnote)
                        .foregroundStyle(palette.tertiaryLabel)
                        .listRowBackground(palette.background)
                }
            }
            .listStyle(.plain)
            .alohaGround(palette)
            .navigationTitle(Text("Reactions", comment: "Story reactions title"))
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
        #if os(macOS)
            .frame(minWidth: 360, minHeight: 420)
        #endif
    }

    private func row(_ reaction: StoryReaction) -> some View {
        HStack(alignment: .top, spacing: AlohaMetrics.space3) {
            AvatarView(account: reaction.account, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AlohaMetrics.space2) {
                    Text(reaction.account.bestDisplayName)
                        .font(AlohaType.name)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let date = reaction.createdAt {
                        Text(PostAge.short(date))
                            .font(AlohaType.meta)
                            .foregroundStyle(palette.tertiaryLabel)
                    }
                }
                if let comment = reaction.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.subheadline)
                }
            }
            if let emoji = reaction.reaction, !emoji.isEmpty {
                Text(emoji)
                    .font(.title2)
                    .accessibilityLabel(Text("Reacted \(emoji)", comment: "Story reaction label"))
            }
        }
        .accessibilityElement(children: .combine)
        .listRowBackground(palette.background)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            reactions = try await session.client.decode(
                StoryReactionList.self, from: Endpoint.storyExtras.reactions(story.id)
            ).reactions
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}
