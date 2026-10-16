// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// The people whose notifications always come through, whatever the policy
/// says — everybody the reader chose "Show these" for in Filtered
/// notifications (`/api/v1/social/notifications/allowed`). Without this list
/// that choice could never be taken back.
struct AllowedSendersView: View {
    @Environment(\.alohaPalette) private var palette

    let session: AccountSession

    @State private var accounts: [Account] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var pendingIDs: Set<String> = []

    var body: some View {
        List {
            if let errorMessage {
                AlohaErrorStrip(message: errorMessage) {
                    Task { await load() }
                }
            }

            ForEach(accounts) { account in
                HStack {
                    AccountRow(account: account, localHost: session.snapshot.instanceHost)
                    Spacer()
                    Button {
                        Task { await remove(account) }
                    } label: {
                        Text("Filter again", comment: "Allowed sender action")
                    }
                    .font(.caption)
                    .disabled(pendingIDs.contains(account.id))
                }
            }

            if accounts.isEmpty && !isLoading && errorMessage == nil {
                ContentUnavailableView {
                    Text("Nobody yet", comment: "Empty allowed senders")
                } description: {
                    Text(
                        "When you choose to see a filtered sender's notifications, they are listed here, and their notifications always reach you.",
                        comment: "Allowed senders explanation")
                }
            }
        }
        .alohaGround(palette)
        .overlay {
            if isLoading && accounts.isEmpty { SkeletonListRow(person: 4) }
        }
        .navigationTitle(Text("Always let through", comment: "Screen title"))
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            accounts = try await session.client.decode(
                LossyArray<Account>.self, from: .notificationInbox.allowed()
            ).elements
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Back under the policy: their next notification is filtered like a
    /// stranger's, unless the policy accepts them anyway.
    private func remove(_ account: Account) async {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        pendingIDs.insert(account.id)
        defer { pendingIDs.remove(account.id) }
        accounts.remove(at: index)
        do {
            try await session.client.send(.notificationInbox.removeAllowed(account.id))
            errorMessage = nil
        } catch {
            accounts.insert(account, at: min(index, accounts.count))
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
