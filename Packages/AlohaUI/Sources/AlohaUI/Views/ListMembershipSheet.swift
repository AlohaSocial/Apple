// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Which of your lists an account is on: every list with a checkmark, and a
/// tap that adds or removes. A new list can be made without leaving.
public struct ListMembershipSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alohaPalette) private var palette

    private let account: Account
    private let session: AccountSession

    @State private var lists: [AccountList] = []
    @State private var memberOf: Set<String> = []
    @State private var busy: Set<String> = []
    @State private var isLoading = true
    @State private var newListTitle = ""
    @State private var isCreating = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    public init(account: Account, session: AccountSession) {
        self.account = account
        self.session = session
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: AlohaMetrics.space3) {
                        AvatarView(account: account, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.bestDisplayName)
                                .font(AlohaType.name)
                            Text(account.qualifiedHandle(localHost: session.snapshot.instanceHost))
                                .font(AlohaType.meta)
                                .foregroundStyle(palette.tertiaryLabel)
                        }
                    }
                }

                if let errorMessage {
                    errorStrip(errorMessage)
                }

                Section {
                    ForEach(lists) { list in
                        Button {
                            Task { await toggle(list) }
                        } label: {
                            HStack {
                                Label {
                                    Text(list.title)
                                        .foregroundStyle(palette.label)
                                } icon: {
                                    Image(systemName: AlohaSymbol.list)
                                }
                                Spacer()
                                if busy.contains(list.id) {
                                    ProgressView()
                                } else if memberOf.contains(list.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(palette.accent)
                                        .fontWeight(.semibold)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(busy.contains(list.id))
                        .accessibilityLabel(Text(list.title))
                        .accessibilityAddTraits(
                            memberOf.contains(list.id) ? [.isButton, .isSelected] : .isButton)
                    }

                    if isCreating {
                        HStack {
                            TextField(
                                text: $newListTitle,
                                prompt: Text("List name", comment: "New list placeholder")
                            ) {
                                Text("List name", comment: "New list label")
                            }
                            .onSubmit { Task { await create() } }
                            Button {
                                Task { await create() }
                            } label: {
                                Text("Add", comment: "New list action")
                            }
                            .buttonStyle(.glass)
                            .disabled(
                                isSaving
                                    || newListTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                        .isEmpty
                            )
                        }
                    } else {
                        Button {
                            isCreating = true
                        } label: {
                            Label {
                                Text("New list", comment: "Lists action")
                            } icon: {
                                Image(systemName: "plus")
                            }
                        }
                    }

                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if lists.isEmpty && errorMessage == nil {
                        Text(
                            "You have no lists yet. Make one to put \(account.bestDisplayName) on it.",
                            comment: "Empty lists in membership sheet"
                        )
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryLabel)
                    }
                } header: {
                    Text("Lists", comment: "List membership section")
                } footer: {
                    Text(
                        "A list shows only its members' posts. Somebody can be on a list without being followed on a server that allows it; on most, follow them first.",
                        comment: "List membership explanation")
                }
            }
            .alohaGround(palette)
            .navigationTitle(Text("Add to list", comment: "Screen title"))
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
            async let allTask = session.client.decode(
                LossyArray<AccountList>.self, from: Endpoint.lists.all)
            async let containingTask = session.client.decode(
                LossyArray<AccountList>.self,
                from: Endpoint.profile.listsContaining(account.id))
            let all = try await allTask
            let containing = try await containingTask
            lists = all.elements
            memberOf = Set(containing.elements.map(\.id))
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// The checkmark moves at once and comes back if the server refuses.
    private func toggle(_ list: AccountList) async {
        guard !busy.contains(list.id) else { return }
        let wasMember = memberOf.contains(list.id)
        busy.insert(list.id)
        defer { busy.remove(list.id) }
        if wasMember { memberOf.remove(list.id) } else { memberOf.insert(list.id) }
        do {
            _ = try await session.client.send(
                wasMember
                    ? Endpoint.listsExtra.removeAccounts(list.id, accountIDs: [account.id])
                    : Endpoint.listsExtra.addAccounts(list.id, accountIDs: [account.id]))
            errorMessage = nil
        } catch {
            if wasMember { memberOf.insert(list.id) } else { memberOf.remove(list.id) }
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "List membership could not be updated. Please try again.")
        }
    }

    private func create() async {
        let submittedTitle = newListTitle
        let title = submittedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let created = try await session.client.decode(
                AccountList.self, from: Endpoint.lists.create(title: title))
            lists.append(created)
            if newListTitle == submittedTitle {
                newListTitle = ""
                isCreating = false
            }
            await toggle(created)
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized:
                        "The list could not be created. Your text has been kept; please try again.")
        }
    }
}
