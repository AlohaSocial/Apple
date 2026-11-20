// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import SwiftUI

/// Who followed you, from a follow notification, with a way to follow them
/// back (docs/09 §4).
///
/// The one decision a follow asks for, and one a wrist can make: a profile,
/// a header and forty posts are the phone's, but "this is my neighbour,
/// follow back" needs none of them. What the button says comes from the
/// server's relationship, so somebody already followed is not offered again
/// and a locked account says "Requested" rather than claiming a follow.
struct WatchFollowBackView: View {
    @Environment(WatchLink.self) private var link
    let accounts: [Account]

    @State private var relationships: [String: Relationship] = [:]
    @State private var pending: Set<String> = []
    @State private var failed: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(accounts) { account in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: account.bestDisplayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                        Text(verbatim: "@\(account.acct)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        followControl(for: account)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle(Text("Followed you", comment: "Watch follow back screen title"))
        .task { await loadRelationships() }
    }

    @ViewBuilder
    private func followControl(for account: Account) -> some View {
        let relationship = relationships[account.id]
        if relationship?.following == true {
            Label {
                Text("Following", comment: "Watch, you already follow this account")
            } icon: {
                Image(systemName: "checkmark")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        } else if relationship?.requested == true {
            Label {
                Text("Requested", comment: "Watch, a follow request is waiting for approval")
            } icon: {
                Image(systemName: "clock")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        } else {
            Button {
                Task { await follow(account) }
            } label: {
                Label {
                    Text("Follow back", comment: "Watch action on a follow notification")
                } icon: {
                    Image(systemName: "person.badge.plus")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(pending.contains(account.id))
            // Double Tap follows back where there is one person to follow.
            .handGestureShortcut(.primaryAction, isEnabled: accounts.count == 1)
            if failed.contains(account.id) {
                Text("Couldn't follow. Try again.", comment: "Watch follow back failed")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    /// Unknown until the server says: a failure leaves the button offered,
    /// and the server refuses a follow that already exists harmlessly.
    private func loadRelationships() async {
        guard let client = link.client, !accounts.isEmpty else { return }
        guard
            let page = try? await client.decode(
                LossyArray<Relationship>.self,
                from: Endpoint.accounts.relationships(accounts.map(\.id)))
        else { return }
        for relationship in page.elements { relationships[relationship.id] = relationship }
    }

    private func follow(_ account: Account) async {
        guard let client = link.client else { return }
        pending.insert(account.id)
        failed.remove(account.id)
        defer { pending.remove(account.id) }
        do {
            let relationship = try await client.decode(
                Relationship.self, from: Endpoint.accounts.follow(account.id))
            relationships[account.id] = relationship
            WatchHaptics.succeeded()
        } catch {
            failed.insert(account.id)
            WatchHaptics.failed()
        }
    }
}
