// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Your lists and followed hashtags. A list row opens its timeline; its
/// settings — name, who is on it, whose replies show — are one tap further,
/// behind the info button (docs/05 §8).
public struct ListsView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession

    @State private var lists: [AccountList] = []
    @State private var followedTags: [Tag] = []
    @State private var newListTitle = ""
    @State private var isCreating = false
    @State private var editing: AccountList?
    @State private var errorMessage: String?

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(palette.destructive)
            }

            Section {
                ForEach(lists) { list in
                    NavigationLink(
                        value: Route.timeline(TimelineKey(mode: .home, source: .list(id: list.id)))
                    ) {
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(list.title)
                                    if list.exclusive {
                                        Text("Kept out of Home", comment: "Exclusive list badge")
                                            .font(AlohaType.micro)
                                            .foregroundStyle(palette.tertiaryLabel)
                                    }
                                }
                            } icon: {
                                Image(systemName: AlohaSymbol.list)
                            }
                            Spacer()
                            Button {
                                editing = list
                            } label: {
                                Image(systemName: "info.circle")
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(palette.accent)
                            .accessibilityLabel(
                                Text("Edit \(list.title)", comment: "List settings button"))
                        }
                    }
                    .contextMenu {
                        Button {
                            editing = list
                        } label: {
                            Label {
                                Text("Edit list", comment: "List action")
                            } icon: {
                                Image(systemName: AlohaSymbol.edit)
                            }
                        }
                        Button(role: .destructive) {
                            Task { await delete(list) }
                        } label: {
                            Label {
                                Text("Delete list", comment: "List action")
                            } icon: {
                                Image(systemName: AlohaSymbol.delete)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await delete(list) }
                        } label: {
                            Label {
                                Text("Delete", comment: "List action")
                            } icon: {
                                Image(systemName: AlohaSymbol.delete)
                            }
                        }
                        Button {
                            editing = list
                        } label: {
                            Label {
                                Text("Edit", comment: "List action")
                            } icon: {
                                Image(systemName: AlohaSymbol.edit)
                            }
                        }
                        .tint(palette.accent)
                    }
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
                        .disabled(newListTitle.trimmingCharacters(in: .whitespaces).isEmpty)
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
            } header: {
                Text("Lists", comment: "Lists section")
            } footer: {
                Text(
                    "A list timeline is your home timeline narrowed to its members — it never shows you something home would not.",
                    comment: "Lists explanation")
            }

            Section {
                ForEach(followedTags) { tag in
                    NavigationLink(value: Route.hashtag(tag.name)) {
                        HashtagRow(tag: tag)
                    }
                }
                .onDelete { offsets in
                    Task { await unfollowTags(at: offsets) }
                }

                if followedTags.isEmpty {
                    Text("None yet", comment: "Empty followed hashtags")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryLabel)
                }
            } header: {
                Text("Followed hashtags", comment: "Lists section")
            } footer: {
                Text(
                    "Following a hashtag puts its public posts into your home timeline.",
                    comment: "Followed hashtags explanation")
            }
        }
        .navigationTitle(Text("Your lists", comment: "Screen title"))
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $editing) { list in
            ListEditorView(list: list, session: session) { updated in
                if let index = lists.firstIndex(where: { $0.id == updated.id }) {
                    lists[index] = updated
                }
            } onDelete: { deleted in
                lists.removeAll { $0.id == deleted.id }
            }
        }
    }

    private func load() async {
        lists =
            (try? await session.client.decode(
                LossyArray<AccountList>.self, from: Endpoint.lists.all))?.elements ?? []
        followedTags =
            (try? await session.client.decode(
                LossyArray<Tag>.self, from: Endpoint.tags.followed(limit: 50)))?.elements ?? []
    }

    private func create() async {
        let title = newListTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        newListTitle = ""
        isCreating = false

        do {
            let created = try await session.client.decode(
                AccountList.self, from: Endpoint.lists.create(title: title))
            lists.append(created)
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func delete(_ list: AccountList) async {
        lists.removeAll { $0.id == list.id }
        do {
            _ = try await session.client.send(Endpoint.lists.delete(list.id))
        } catch {
            await session.handle(error)
            await load()
        }
    }

    private func unfollowTags(at offsets: IndexSet) async {
        let targets = offsets.map { followedTags[$0] }
        followedTags.remove(atOffsets: offsets)
        for tag in targets {
            _ = try? await session.client.send(Endpoint.tags.unfollow(tag.name))
        }
    }
}

// MARK: - One list's settings

/// Name, replies policy, exclusivity, and the people on the list — with a
/// search to add more and a swipe to take one off.
struct ListEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alohaPalette) private var palette

    let session: AccountSession
    let onChange: (AccountList) -> Void
    let onDelete: (AccountList) -> Void

    @State private var list: AccountList
    @State private var title: String
    @State private var repliesPolicy: ListRepliesPolicy
    @State private var exclusive: Bool
    @State private var members: [Account] = []
    @State private var query = ""
    @State private var results: [Account] = []
    @State private var isSaving = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    init(
        list: AccountList, session: AccountSession,
        onChange: @escaping (AccountList) -> Void, onDelete: @escaping (AccountList) -> Void
    ) {
        self.session = session
        self.onChange = onChange
        self.onDelete = onDelete
        _list = State(initialValue: list)
        _title = State(initialValue: list.title)
        _repliesPolicy = State(
            initialValue: ListRepliesPolicy(rawValue: list.repliesPolicy ?? "") ?? .list)
        _exclusive = State(initialValue: list.exclusive)
    }

    private var hasChanges: Bool {
        title.trimmingCharacters(in: .whitespaces) != list.title
            || repliesPolicy.rawValue != (list.repliesPolicy ?? ListRepliesPolicy.list.rawValue)
            || exclusive != list.exclusive
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(palette.destructive)
                }

                Section {
                    TextField(
                        text: $title, prompt: Text("List name", comment: "New list placeholder")
                    ) {
                        Text("Name", comment: "List field")
                    }
                    Picker(selection: $repliesPolicy) {
                        Text("Nobody's replies", comment: "List replies policy").tag(
                            ListRepliesPolicy.none)
                        Text("Replies to members", comment: "List replies policy").tag(
                            ListRepliesPolicy.list)
                        Text("Replies to anyone I follow", comment: "List replies policy")
                            .tag(ListRepliesPolicy.followed)
                    } label: {
                        Text("Show replies", comment: "List field")
                    }
                    Toggle(isOn: $exclusive) {
                        Text("Keep members out of Home", comment: "List field")
                    }
                } footer: {
                    Text(
                        "An exclusive list's members appear only here, not in your home timeline.",
                        comment: "Exclusive list explanation")
                }

                Section {
                    TextField(
                        text: $query,
                        prompt: Text("Search people to add", comment: "List member search prompt")
                    ) {
                        Text("Search", comment: "List member search label")
                    }
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()

                    ForEach(
                        results.filter { candidate in !members.contains { $0.id == candidate.id } }
                    ) {
                        account in
                        Button {
                            Task { await add(account) }
                        } label: {
                            HStack(spacing: AlohaMetrics.space3) {
                                AvatarView(account: account, size: 32)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(account.bestDisplayName)
                                        .font(.subheadline)
                                        .foregroundStyle(palette.label)
                                    Text(
                                        account.qualifiedHandle(
                                            localHost: session.snapshot.instanceHost)
                                    )
                                    .font(AlohaType.meta)
                                    .foregroundStyle(palette.tertiaryLabel)
                                }
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(palette.accent)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            Text("Add \(account.bestDisplayName)", comment: "List member action"))
                    }
                } header: {
                    Text("Add people", comment: "List section")
                }

                Section {
                    ForEach(members) { account in
                        HStack(spacing: AlohaMetrics.space3) {
                            AvatarView(account: account, size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(account.bestDisplayName).font(.subheadline)
                                Text(
                                    account.qualifiedHandle(
                                        localHost: session.snapshot.instanceHost)
                                )
                                .font(AlohaType.meta)
                                .foregroundStyle(palette.tertiaryLabel)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await remove(account) }
                            } label: {
                                Label {
                                    Text("Remove", comment: "List member action")
                                } icon: {
                                    Image(systemName: "person.badge.minus")
                                }
                            }
                        }
                    }
                    if members.isEmpty {
                        Text("Nobody on this list yet.", comment: "Empty list members")
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryLabel)
                    }
                } header: {
                    Text("Members", comment: "List section")
                }

                Section {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Text("Delete list", comment: "List action")
                    }
                }
            }
            .navigationTitle(Text(list.title))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Close", comment: "Sheet action")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save", comment: "Sheet action")
                        }
                    }
                    .disabled(
                        !hasChanges || isSaving
                            || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog(
                Text("Delete \(list.title)?", comment: "Delete list title"),
                isPresented: $isConfirmingDelete, titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    Task { await deleteList() }
                } label: {
                    Text("Delete list", comment: "List action")
                }
            } message: {
                Text("Its members are not unfollowed.", comment: "Delete list detail")
            }
            .task { await loadMembers() }
            .task(id: query) { await search() }
        }
    }

    private func loadMembers() async {
        members =
            (try? await session.client.decode(
                LossyArray<Account>.self, from: Endpoint.lists.accounts(list.id)))?.elements ?? []
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let found = try? await session.client.decode(
            SearchResults.self,
            from: Endpoint.search.search(trimmed, type: "accounts", limit: 10))
        guard !Task.isCancelled else { return }
        results = (found?.accounts ?? []).filter { $0.id != session.snapshot.serverAccountID }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await session.client.decode(
                AccountList.self,
                from: Endpoint.listsExtra.update(
                    list.id, title: title.trimmingCharacters(in: .whitespaces),
                    repliesPolicy: repliesPolicy.rawValue, exclusive: exclusive))
            list = updated
            onChange(updated)
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func add(_ account: Account) async {
        members.append(account)
        do {
            _ = try await session.client.send(
                Endpoint.listsExtra.addAccounts(list.id, accountIDs: [account.id]))
            errorMessage = nil
        } catch {
            members.removeAll { $0.id == account.id }
            await session.handle(error)
            // Mastodon refuses somebody you do not follow; say so plainly.
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "Couldn't add them. Follow them first.", comment: "List add failed")
        }
    }

    private func remove(_ account: Account) async {
        members.removeAll { $0.id == account.id }
        do {
            _ = try await session.client.send(
                Endpoint.listsExtra.removeAccounts(list.id, accountIDs: [account.id]))
        } catch {
            await session.handle(error)
            await loadMembers()
        }
    }

    private func deleteList() async {
        do {
            _ = try await session.client.send(Endpoint.lists.delete(list.id))
            onDelete(list)
            dismiss()
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}
