// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import AlohaStore
import SwiftUI

public struct DraftsView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession
    @State private var drafts: [DraftSnapshot] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        List {
            if let errorMessage {
                errorStrip(errorMessage)
            }

            ForEach(drafts) { draft in
                VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
                    Text(
                        draft.text.isEmpty
                            ? String(localized: "Empty draft", comment: "Draft with no text")
                            : draft.text
                    )
                    .font(.subheadline)
                    .lineLimit(3)

                    HStack(spacing: AlohaMetrics.space2) {
                        Text(draft.updatedAt, format: .relative(presentation: .named))
                        if draft.queuedForSend {
                            Label {
                                Text("Will post when you're online", comment: "Queued draft state")
                            } icon: {
                                Image(systemName: AlohaSymbol.offline)
                            }
                        }
                        if !draft.uploadedMediaIDs.isEmpty {
                            Label {
                                Text(
                                    "^[\(draft.uploadedMediaIDs.count) attachment](inflect: true)",
                                    comment: "Draft attachment count")
                            } icon: {
                                Image(systemName: AlohaSymbol.media)
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                }
            }
            .onDelete { offsets in
                let targets = offsets.compactMap { drafts.indices.contains($0) ? drafts[$0] : nil }
                Task { await delete(targets) }
            }

            if drafts.isEmpty && !isLoading && errorMessage == nil {
                ContentUnavailableView {
                    Text("No drafts", comment: "Empty drafts")
                } description: {
                    Text(
                        "A post you close without sending is saved here.",
                        comment: "Drafts explanation")
                }
            }
        }
        .alohaGround(palette)
        .overlay {
            if isLoading && drafts.isEmpty {
                SkeletonListRow(text: 4)
            }
        }
        .navigationTitle(Text("Drafts", comment: "Screen title"))
        .task { await load() }
    }

    private func errorStrip(_ message: String) -> some View {
        AlohaErrorStrip(message: message) {
            Task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            drafts = try await session.supportStore.drafts(accountID: session.id)
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func delete(_ targets: [DraftSnapshot]) async {
        for draft in targets {
            do {
                try await session.supportStore.deleteDraft(id: draft.id)
                drafts.removeAll { $0.id == draft.id }
            } catch {
                errorMessage = String(
                    localized: "The draft could not be deleted. Please try again.")
            }
        }
    }
}

/// One row per held sender, with their count and latest post — being asked
/// about each notification in turn is what makes a filtered inbox worse than an
/// unfiltered one (docs/05 §6).
public struct NotificationRequestsView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession
    @State private var requests: [NotificationRequest] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        List {
            if let errorMessage {
                errorStrip(errorMessage)
            }

            ForEach(requests) { request in
                VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                    AccountRow(
                        account: request.account, localHost: session.snapshot.instanceHost)

                    Text(
                        "^[\(request.notificationsCount) notification](inflect: true) held",
                        comment: "Notification request count"
                    )
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)

                    HStack(spacing: AlohaMetrics.space3) {
                        Button {
                            Task { await accept(request) }
                        } label: {
                            Text("Show these", comment: "Notification request action")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button {
                            Task { await dismiss(request) }
                        } label: {
                            Text("Stop asking", comment: "Notification request action")
                        }
                        .controlSize(.small)
                    }
                }
            }

            if requests.isEmpty && !isLoading && errorMessage == nil {
                ContentUnavailableView {
                    Text("Nothing held", comment: "Empty notification requests")
                } description: {
                    Text(
                        "Notifications your policy holds back appear here, one row per sender.",
                        comment: "Notification requests explanation")
                }
            }
        }
        .alohaGround(palette)
        .overlay {
            if isLoading && requests.isEmpty {
                SkeletonListRow(person: 4)
            }
        }
        .navigationTitle(Text("Filtered notifications", comment: "Screen title"))
        .task { await load() }
        .refreshable { await load() }
    }

    private func errorStrip(_ message: String) -> some View {
        AlohaErrorStrip(message: message) {
            Task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            requests = try await session.client.decode(
                LossyArray<NotificationRequest>.self,
                from: Endpoint.notifications.requests
            ).elements
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func accept(_ request: NotificationRequest) async {
        await decide(request) {
            _ = try await session.client.send(Endpoint.notifications.acceptRequest(request.id))
        }
    }

    private func dismiss(_ request: NotificationRequest) async {
        await decide(request) {
            _ = try await session.client.send(Endpoint.notifications.dismissRequest(request.id))
        }
    }

    /// The row leaves at once and comes back if the server refuses: a request
    /// that vanished on a failed answer was a request nobody ever saw again.
    private func decide(
        _ request: NotificationRequest, send: () async throws -> Void
    ) async {
        guard let index = requests.firstIndex(where: { $0.id == request.id }) else { return }
        requests.remove(at: index)
        do {
            try await send()
            errorMessage = nil
        } catch {
            if !requests.contains(where: { $0.id == request.id }) {
                requests.insert(request, at: min(index, requests.count))
            }
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Resolves `@alice@example.social` through the reading account's own server,
/// so the profile opens with that reader's relationship state.
public struct ResolvingProfileView: View {
    private let handle: String
    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var accountID: String?
    @State private var failed = false

    public init(
        handle: String, session: AccountSession,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.handle = handle
        self.session = session
        self.onAction = onAction
    }

    public var body: some View {
        Group {
            if let accountID {
                ProfileView(accountID: accountID, session: session, onAction: onAction)
            } else if failed {
                ContentUnavailableView {
                    Text("Couldn't find them", comment: "Profile resolution failure")
                } description: {
                    Text(
                        "Your server couldn't look up @\(handle).",
                        comment: "Profile resolution failure detail")
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await resolve() }
    }

    private func resolve() async {
        if let account = try? await session.client.decode(
            Account.self, from: Endpoint.accounts.lookup(acct: handle))
        {
            accountID = account.id
            return
        }
        // Falls through to a resolving search, which is what reaches an account
        // this server has not cached yet.
        if let results = try? await session.client.decode(
            SearchResults.self,
            from: Endpoint.search.search(handle, type: "accounts", resolve: true, limit: 1)),
            let account = results.accounts.first
        {
            accountID = account.id
            return
        }
        failed = true
    }
}
