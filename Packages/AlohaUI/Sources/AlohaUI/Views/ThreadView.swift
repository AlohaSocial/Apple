// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

public struct ThreadView: View {
    @Environment(\.alohaPalette) private var palette

    private let statusID: String
    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var focused: Status?
    @State private var ancestors: [Status] = []
    @State private var descendants: [Status] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init(
        statusID: String, session: AccountSession,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.statusID = statusID
        self.session = session
        self.onAction = onAction
    }

    public var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(ancestors) { status in
                    row(status, isFocused: false)
                }

                if let focused {
                    row(focused, isFocused: true)
                        .id("focused")
                }

                ForEach(Array(descendants.enumerated()), id: \.element.id) { _, status in
                    row(status, isFocused: false)
                        .padding(.leading, indent(for: status))
                }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(palette.background)
                    .listRowSeparator(.hidden)
                }

                if let errorMessage {
                    errorStrip(errorMessage)
                }
            }
            .listStyle(.plain)
            .alohaGround(palette)
            .navigationTitle(Text("Post", comment: "Thread screen title"))
            .task {
                await load()
                // The focused status lands in a stable position with its
                // ancestors already laid out above it — no jump.
                if !ancestors.isEmpty { proxy.scrollTo("focused", anchor: .top) }
            }
            .refreshable { await load() }
        }
    }

    private func row(_ status: Status, isFocused: Bool) -> some View {
        StatusRow(
            status: status,
            policy: session.settings.sensitiveMediaPolicy,
            localHost: session.snapshot.instanceHost,
            // The thread's own shape says "this is a reply"; repeating it on
            // every row was noise.
            showsContextLine: isFocused,
            canReact: session.capabilities.emojiReactions,
            onAction: onAction
        )
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        // Raised card plus the accent rail the timeline uses for keyboard
        // focus: `surface` and `background` are the same black in the Black
        // theme, so the old pair marked nothing there.
        .listRowBackground(isFocused ? palette.surfaceRaised : palette.background)
        .font(isFocused ? .body : nil)
        .overlay(alignment: .leading) {
            if isFocused {
                Capsule()
                    .fill(palette.accent)
                    .frame(width: 3)
                    .padding(.vertical, 4)
                    .padding(.leading, -8)
            }
        }
    }

    private func errorStrip(_ message: String) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: AlohaSymbol.warning)
            Text(message).font(.caption)
            Spacer()
            Button {
                Task { await load() }
            } label: {
                Text("Retry", comment: "Error strip action")
            }
            .font(.caption.weight(.semibold))
        }
        .foregroundStyle(palette.destructive)
        .padding(.vertical, AlohaMetrics.space2)
        .listRowBackground(palette.background)
    }

    /// Indentation is capped at five levels; anything deeper reads as a flat
    /// list rather than a staircase.
    private func indent(for status: Status) -> Double {
        var depth = 0
        var current: String? = status.inReplyToID
        var seen = Set<String>()

        while let parent = current, depth < 5, seen.insert(parent).inserted {
            if parent == statusID { break }
            current = descendants.first { $0.id == parent }?.inReplyToID
            depth += 1
        }
        return Double(depth) * 12
    }

    /// The link preview of the focused post, for one the server had not built
    /// a card for when it was written.
    ///
    /// Fetched **beside** the status rather than after it, and applied before
    /// the screen is first drawn. Doing it afterwards worked and was still
    /// wrong: the post grew a card under the reader a moment after they
    /// started reading it, which is the thing this app is careful not to do
    /// anywhere else — and it left the screen changing long enough that
    /// `performAccessibilityAudit` could not finish walking it.
    ///
    /// Only here, and only for the one post being read: asking makes the
    /// server build and cache the preview, so a timeline that asked per row
    /// would be a request storm for a decoration. A post with no link answers
    /// `{}`, which decodes to a card with no URL and is not drawn (docs/05 §4).
    private static func withCard(_ status: Status, _ card: Card?) -> Status {
        guard let card, card.url != nil else { return status }
        let displayed = status.displayed
        guard displayed.card == nil, displayed.mediaAttachments.isEmpty else { return status }

        // A boosted post's card belongs to the post, not to the boost, so it
        // goes on whichever of the two is actually being read. `Box` holds its
        // value immutably, so the wrapper is rebuilt rather than mutated.
        var updated = status
        if let boosted = updated.reblog?.value {
            var inner = boosted
            inner.card = card
            updated.reblog = Box(inner)
        } else {
            updated.card = card
        }
        return updated
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let statusTask = session.client.decode(
                Status.self, from: Endpoint.statuses.status(statusID))
            async let contextTask = session.client.decode(
                StatusContext.self, from: Endpoint.statuses.context(statusID))
            // Beside the other two, not after them: the card has to be in hand
            // before the first draw or it arrives as a jump.
            async let cardTask = try? await session.client.decode(
                Card.self, from: Endpoint.statuses.card(statusID))

            let status = Self.withCard(try await statusTask, await cardTask)
            let context = try await contextTask
            focused = status
            ancestors = context.ancestors
            descendants = context.descendants
            errorMessage = nil

            try? await session.timelineStore.updateStatus(
                accountID: session.id, status: status)
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}
