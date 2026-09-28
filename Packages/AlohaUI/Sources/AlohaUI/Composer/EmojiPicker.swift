// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// The server's custom emoji, as `:shortcode:` the text will carry.
struct EmojiPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alohaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let session: AccountSession
    let onPick: (CustomEmoji) -> Void

    @State private var query = ""
    @State private var emoji: [CustomEmoji] = []
    @State private var isLoading = true

    private let columns = [GridItem(.adaptive(minimum: 52), spacing: AlohaMetrics.space2)]

    /// Grouped by the server's category, uncategorised last.
    private var groups: [(name: String?, emoji: [CustomEmoji])] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        let visible = emoji.filter { entry in
            entry.visibleInPicker
                && (trimmed.isEmpty || entry.shortcode.lowercased().contains(trimmed))
        }
        let grouped = Dictionary(grouping: visible) { $0.category }
        return grouped.keys
            .sorted { ($0 ?? "\u{FFFF}") < ($1 ?? "\u{FFFF}") }
            .map { (name: $0, emoji: grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading {
                    ProgressView().padding(.top, AlohaMetrics.space5)
                } else if emoji.isEmpty {
                    ContentUnavailableView {
                        Text("No custom emoji", comment: "Emoji picker empty")
                    } description: {
                        Text(
                            "This server hasn't published any.",
                            comment: "Emoji picker empty detail")
                    }
                    .padding(.top, AlohaMetrics.space5)
                } else {
                    LazyVStack(alignment: .leading, spacing: AlohaMetrics.space3) {
                        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                            if let name = group.name, !name.isEmpty {
                                Text(name)
                                    .font(AlohaType.section)
                                    .padding(.horizontal, AlohaMetrics.space3)
                            }
                            LazyVGrid(columns: columns, spacing: AlohaMetrics.space2) {
                                ForEach(group.emoji) { entry in
                                    Button {
                                        onPick(entry)
                                        dismiss()
                                    } label: {
                                        RemoteImage(
                                            url: reduceMotion ? entry.stillURL : entry.url,
                                            contentMode: .fit
                                        )
                                        .frame(width: 32, height: 32)
                                        .frame(width: 52, height: 52)
                                        .background(
                                            palette.surfaceRaised,
                                            in: RoundedRectangle(
                                                cornerRadius: AlohaMetrics.cornerSmall,
                                                style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Text(entry.shortcode))
                                }
                            }
                            .padding(.horizontal, AlohaMetrics.space3)
                        }
                    }
                    .padding(.vertical, AlohaMetrics.space3)
                }
            }
            .background(palette.background)
            .searchable(text: $query, prompt: Text("Search emoji", comment: "Emoji search prompt"))
            .navigationTitle(Text("Custom emoji", comment: "Screen title"))
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
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        emoji =
            (try? await session.client.decode(
                LossyArray<CustomEmoji>.self, from: Endpoint.instance.customEmojis))?.elements ?? []
    }
}
