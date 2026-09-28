// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// A hashtag's timeline, with Follow in the bar and the tags that travel with
/// it in a row above the posts.
///
/// Following is the whole reason the screen has a bar button: a hashtag is
/// something you can subscribe to, and the timeline alone did not say so.
public struct HashtagTimelineView: View {
    @Environment(\.alohaPalette) private var palette

    private let name: String
    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var tag: Tag?
    @State private var related: [Tag] = []
    @State private var isBusy = false

    public init(
        name: String, session: AccountSession, onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.name = name
        self.session = session
        self.onAction = onAction
    }

    private var isFollowing: Bool { tag?.following == true }

    public var body: some View {
        TimelineView(
            key: TimelineKey(mode: .home, source: .hashtag(name: name)), session: session,
            onAction: onAction
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            if !related.isEmpty { relatedRow }
        }
        .navigationTitle(Text(verbatim: "#\(name)"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await toggleFollow() }
                } label: {
                    if isFollowing {
                        Label {
                            Text("Following", comment: "Hashtag follow state")
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Label {
                            Text("Follow", comment: "Hashtag follow action")
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .labelStyle(.titleOnly)
                .disabled(isBusy)
                .accessibilityLabel(
                    isFollowing
                        ? Text("Unfollow #\(name)", comment: "Hashtag follow button")
                        : Text("Follow #\(name)", comment: "Hashtag follow button"))
            }
        }
        .task { await load() }
    }

    private var relatedRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AlohaMetrics.space2) {
                Text("Also", comment: "Related hashtags row lead-in")
                    .font(AlohaType.meta)
                    .foregroundStyle(palette.tertiaryLabel)
                ForEach(related) { other in
                    NavigationLink(value: Route.hashtag(other.name)) {
                        Text(verbatim: "#\(other.name)")
                            .font(.footnote)
                            .foregroundStyle(palette.hashtag)
                            .padding(.horizontal, AlohaMetrics.space3)
                            .frame(minHeight: 32)
                            .background(palette.surfaceRaised, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, AlohaMetrics.space3)
        }
        .scrollIndicators(.hidden)
        .background(palette.background)
        .accessibilityLabel(Text("Related hashtags", comment: "Related hashtags row"))
    }

    private func load() async {
        tag = try? await session.client.decode(Tag.self, from: Endpoint.tags.tag(name))
        guard session.capabilities.isNextcloudSocial else { return }
        related =
            ((try? await session.client.decode(
                LossyArray<Tag>.self, from: Endpoint.tagsExtra.related(name)))?.elements ?? [])
            .filter { $0.id != Tag.normalise(name) }
    }

    private func toggleFollow() async {
        isBusy = true
        defer { isBusy = false }
        let wasFollowing = isFollowing
        do {
            tag = try await session.client.decode(
                Tag.self,
                from: wasFollowing ? Endpoint.tags.unfollow(name) : Endpoint.tags.follow(name))
        } catch {
            await session.handle(error)
        }
    }
}
