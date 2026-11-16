// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

#if os(macOS)
    /// What is going on around the feed, beside it: the hashtags trending on
    /// the server, people it suggests, and the reader's own lists.
    ///
    /// An option, off until asked for (`MacOptions.contextColumnKey`), with a
    /// button in the toolbar to show and hide it: a wide window has the room,
    /// and a reader who wants only their timeline should have only that.
    struct ContextColumn: View {
        @Environment(\.alohaPalette) private var palette

        let session: AccountSession
        let onOpen: (Route) -> Void

        @State private var tags: [Tag] = []
        @State private var suggestions: [Suggestion] = []
        @State private var lists: [AccountList] = []
        @State private var hasLoaded = false

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: AlohaMetrics.space4) {
                    if !tags.isEmpty {
                        section(Text("Trending", comment: "Context column section")) {
                            ForEach(tags.prefix(8)) { tag in
                                row(symbol: "number", title: tag.name) {
                                    onOpen(.hashtag(tag.name))
                                }
                            }
                        }
                    }
                    if !suggestions.isEmpty {
                        section(Text("People to follow", comment: "Context column section")) {
                            ForEach(suggestions.prefix(5)) { suggestion in
                                Button {
                                    onOpen(.profile(accountID: suggestion.account.id))
                                } label: {
                                    HStack(spacing: AlohaMetrics.space2) {
                                        AvatarView(account: suggestion.account, size: 30)
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text(verbatim: suggestion.account.bestDisplayName)
                                                .font(.subheadline.weight(.medium))
                                                .lineLimit(1)
                                            Text(verbatim: "@" + suggestion.account.acct)
                                                .font(.caption)
                                                .foregroundStyle(palette.secondaryLabel)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if !lists.isEmpty {
                        section(Text("Your lists", comment: "Context column section")) {
                            ForEach(lists.prefix(8)) { list in
                                row(symbol: AlohaSymbol.list, title: list.title) {
                                    onOpen(
                                        .timeline(
                                            TimelineKey(mode: .home, source: .list(id: list.id))))
                                }
                            }
                        }
                    }
                    if hasLoaded && tags.isEmpty && suggestions.isEmpty && lists.isEmpty {
                        Text(
                            "Nothing is trending on this server yet.",
                            comment: "Context column empty state"
                        )
                        .font(.callout)
                        .foregroundStyle(palette.secondaryLabel)
                    }
                }
                .padding(AlohaMetrics.space3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .task(id: session.id) { await load() }
        }

        private func section(_ title: Text, @ViewBuilder content: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                title
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryLabel)
                    .textCase(.uppercase)
                VStack(alignment: .leading, spacing: AlohaMetrics.space2, content: content)
                    .padding(AlohaMetrics.space3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        palette.surfaceRaised,
                        in: RoundedRectangle(
                            cornerRadius: AlohaMetrics.cornerMedium, style: .continuous))
            }
        }

        private func row(symbol: String, title: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                HStack(spacing: AlohaMetrics.space2) {
                    Image(systemName: symbol)
                        .foregroundStyle(palette.accent)
                        .frame(width: 18)
                    Text(verbatim: title)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        /// Each of the three is its own request and its own failure: a server
        /// without trends still has lists.
        private func load() async {
            async let trending = try? session.client.decode(
                LossyArray<Tag>.self, from: Endpoint.search.trendingTags(limit: 8))
            async let suggested = try? session.client.decode(
                LossyArray<Suggestion>.self, from: Endpoint.search.suggestions)
            async let own = try? session.client.decode(
                LossyArray<AccountList>.self, from: Endpoint.lists.all)
            tags = await trending?.elements ?? []
            suggestions = await suggested?.elements ?? []
            lists = await own?.elements ?? []
            hasLoaded = true
        }
    }

    /// Home, Activities and the server's local timeline, each in a column of
    /// its own that scrolls by itself — for a window wide enough that one
    /// timeline in the middle of it is mostly margin. An option
    /// (`MacOptions.deckKey`), off unless switched on.
    struct DeckView: View {
        @Environment(\.alohaPalette) private var palette

        let session: AccountSession
        let onAction: (StatusRowAction) -> Void

        var body: some View {
            HStack(alignment: .top, spacing: AlohaMetrics.space3) {
                column(Text("My Feed", comment: "Timeline source")) {
                    TimelineView(
                        key: TimelineKey(mode: .home, source: .home), session: session,
                        onAction: onAction)
                }
                column(Text("Activities", comment: "Screen title")) {
                    NotificationsView(session: session, onAction: onAction)
                }
                column(Text("Local", comment: "Timeline source")) {
                    TimelineView(
                        key: TimelineKey(mode: .home, source: .local), session: session,
                        onAction: onAction)
                }
            }
            .padding(.horizontal, AlohaMetrics.space3)
            .padding(.bottom, AlohaMetrics.space3)
            .environment(\.sharesToolbar, true)
        }

        private func column(_ title: Text, @ViewBuilder content: () -> some View) -> some View {
            let panel = RoundedRectangle(cornerRadius: 14, style: .continuous)
            return VStack(spacing: 0) {
                title
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AlohaMetrics.space3)
                    .padding(.vertical, AlohaMetrics.space2)
                Divider()
                content()
            }
            .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.background)
            .clipShape(panel)
            .overlay(panel.strokeBorder(palette.separator.opacity(0.35), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 5)
        }
    }
#endif
