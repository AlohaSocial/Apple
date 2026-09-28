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

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        List {
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
                Task { await delete(at: offsets) }
            }

            if drafts.isEmpty {
                ContentUnavailableView {
                    Text("No drafts", comment: "Empty drafts")
                } description: {
                    Text(
                        "A post you close without sending is saved here.",
                        comment: "Drafts explanation")
                }
            }
        }
        .navigationTitle(Text("Drafts", comment: "Screen title"))
        .task { await load() }
    }

    private func load() async {
        drafts = (try? await session.supportStore.drafts(accountID: session.id)) ?? []
    }

    private func delete(at offsets: IndexSet) async {
        let targets = offsets.map { drafts[$0] }
        drafts.remove(atOffsets: offsets)
        for draft in targets {
            try? await session.supportStore.deleteDraft(id: draft.id)
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

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        List {
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

            if requests.isEmpty {
                ContentUnavailableView {
                    Text("Nothing held", comment: "Empty notification requests")
                } description: {
                    Text(
                        "Notifications your policy holds back appear here, one row per sender.",
                        comment: "Notification requests explanation")
                }
            }
        }
        .navigationTitle(Text("Filtered notifications", comment: "Screen title"))
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        requests =
            (try? await session.client.decode(
                LossyArray<NotificationRequest>.self,
                from: Endpoint.notifications.requests))?.elements ?? []
    }

    private func accept(_ request: NotificationRequest) async {
        requests.removeAll { $0.id == request.id }
        _ = try? await session.client.send(Endpoint.notifications.acceptRequest(request.id))
    }

    private func dismiss(_ request: NotificationRequest) async {
        requests.removeAll { $0.id == request.id }
        _ = try? await session.client.send(Endpoint.notifications.dismissRequest(request.id))
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
