// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// "Waiting to be looked at": your own posts a moderator has not yet reviewed.
///
/// The one thing this screen must never do is lose what somebody wrote without
/// telling them where it went — so the text is shown whole, and withdrawing
/// it is a deliberate, confirmed act.
public struct HeldPostsView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession

    @State private var held: [HeldPost] = []
    @State private var isLoading = true
    @State private var withdrawing: HeldPost?
    @State private var errorMessage: String?

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        List {
            if let errorMessage {
                errorRow(errorMessage)
            }

            ForEach(held) { post in
                row(post)
            }

            if held.isEmpty && !isLoading && errorMessage == nil {
                ContentUnavailableView {
                    Text("Nothing of yours is waiting.", comment: "Empty held posts")
                } description: {
                    Text(
                        "When a moderator has to look at a post before it goes out, it waits here until they do.",
                        comment: "Held posts explanation")
                }
                .listRowSeparator(.hidden)
                .listRowBackground(palette.background)
            }
        }
        .listStyle(.plain)
        .alohaGround(palette)
        .overlay {
            if isLoading && held.isEmpty { ProgressView() }
        }
        .navigationTitle(Text("Waiting to be looked at", comment: "Screen title"))
        .task { await load() }
        .refreshable { await load() }
        .alert(
            Text("Withdraw this post?", comment: "Withdraw confirmation title"),
            isPresented: Binding(get: { withdrawing != nil }, set: { if !$0 { withdrawing = nil } })
        ) {
            Button(role: .destructive) {
                if let post = withdrawing { Task { await withdraw(post) } }
                withdrawing = nil
            } label: {
                Text("Withdraw", comment: "Withdraw confirmation action")
            }
            Button(role: .cancel) {
                withdrawing = nil
            } label: {
                Text("Cancel", comment: "Withdraw confirmation action")
            }
        } message: {
            Text(
                "It is deleted rather than published. Nobody is told.",
                comment: "Withdraw confirmation detail")
        }
    }

    private func row(_ post: HeldPost) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            HStack(alignment: .firstTextBaseline) {
                if let date = post.createdAt {
                    Label {
                        Text(date, format: .dateTime.day().month().hour().minute())
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(AlohaType.meta)
                    .foregroundStyle(palette.tertiaryLabel)
                }
                Spacer()
                Button {
                    withdrawing = post
                } label: {
                    Text("Withdraw", comment: "Held post action")
                        .font(.footnote.weight(.medium))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.destructive)
            }

            if let reason = post.reason, !reason.isEmpty {
                Text(reason)
                    .font(.footnote.italic())
                    .foregroundStyle(palette.secondaryLabel)
            }

            if !post.spoilerText.isEmpty {
                Text(post.spoilerText)
                    .font(.subheadline.weight(.bold))
            }

            Text(post.text)
                .font(.body)
                .textSelection(.enabled)

            if post.mediaCount > 0 {
                Label {
                    Text(
                        "^[\(post.mediaCount) attachment](inflect: true)",
                        comment: "Held post media count")
                } icon: {
                    Image(systemName: AlohaSymbol.media)
                }
                .font(AlohaType.meta)
                .foregroundStyle(palette.tertiaryLabel)
            }
        }
        .padding(.vertical, AlohaMetrics.space2)
        .listRowBackground(palette.background)
        .listRowSeparator(.hidden)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: AlohaSymbol.warning)
                .accessibilityHidden(true)
            Text(message).font(.footnote)
            Spacer()
            Button {
                Task { await load() }
            } label: {
                Text("Retry", comment: "Held posts retry action")
            }
            .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(palette.destructive)
        .padding(.vertical, AlohaMetrics.space2)
        .listRowBackground(palette.background)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await session.client.decode(
                HeldPostsPage.self, from: Endpoint.review.held)
            held = page.held.sorted {
                ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func withdraw(_ post: HeldPost) async {
        let previous = held
        held.removeAll { $0.id == post.id }
        do {
            _ = try await session.client.send(Endpoint.review.withdraw(post.id))
        } catch {
            held = previous
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}
