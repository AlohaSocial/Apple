// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Pixelfed albums, where the server has them. A real reason Photos mode
/// exists rather than a filter (docs/06 §5).
public struct CollectionsView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession
    private let accountID: String?
    private let onAction: (StatusRowAction) -> Void

    @State private var collections: [Collection] = []
    @State private var isLoading = true
    @State private var isCreating = false
    @State private var renaming: Collection?
    @State private var draftTitle = ""
    @State private var errorMessage: String?

    /// Only your own albums can be changed; somebody else's are read.
    private var isOwn: Bool {
        accountID == nil || accountID == session.snapshot.serverAccountID
    }

    public init(
        session: AccountSession, accountID: String? = nil,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.session = session
        self.accountID = accountID
        self.onAction = onAction
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: AlohaMetrics.space3)]

    public var body: some View {
        ScrollView {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(palette.destructive)
                    .padding(.horizontal, AlohaMetrics.space3)
            }

            LazyVGrid(columns: columns, spacing: AlohaMetrics.space3) {
                ForEach(collections) { collection in
                    NavigationLink {
                        CollectionDetailView(
                            session: session, collection: collection, isOwn: isOwn,
                            onAction: onAction)
                    } label: {
                        card(collection)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if isOwn {
                            Button {
                                draftTitle = collection.title
                                renaming = collection
                            } label: {
                                Label {
                                    Text("Rename", comment: "Album action")
                                } icon: {
                                    Image(systemName: AlohaSymbol.edit)
                                }
                            }
                            Button(role: .destructive) {
                                Task { await delete(collection) }
                            } label: {
                                Label {
                                    Text("Delete album", comment: "Album action")
                                } icon: {
                                    Image(systemName: AlohaSymbol.delete)
                                }
                            }
                        }
                    }
                }
            }
            .padding(AlohaMetrics.space3)

            if collections.isEmpty && !isLoading {
                ContentUnavailableView {
                    Text("No albums", comment: "Empty collections")
                } description: {
                    Text(
                        "Albums group photos together. Create one from any post's menu.",
                        comment: "Collections explanation")
                }
                .padding(.top, AlohaMetrics.space6)
            }
        }
        .background(palette.background)
        .navigationTitle(Text("Albums", comment: "Screen title"))
        .toolbar {
            if isOwn {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        draftTitle = ""
                        isCreating = true
                    } label: {
                        Label {
                            Text("New album", comment: "Albums action")
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }
                    .accessibilityLabel(Text("New album", comment: "Albums action"))
                }
            }
        }
        .alert(
            Text("New album", comment: "Albums action"), isPresented: $isCreating
        ) {
            TextField(
                String(localized: "Album name", comment: "Album name placeholder"),
                text: $draftTitle)
            Button {
                Task { await create() }
            } label: {
                Text("Create", comment: "Album action")
            }
            Button(role: .cancel) {
            } label: {
                Text("Cancel", comment: "Album action")
            }
        }
        .alert(
            Text("Rename album", comment: "Album action"),
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
        ) {
            TextField(
                String(localized: "Album name", comment: "Album name placeholder"),
                text: $draftTitle)
            Button {
                if let renaming { Task { await rename(renaming) } }
            } label: {
                Text("Save", comment: "Album action")
            }
            Button(role: .cancel) {
                renaming = nil
            } label: {
                Text("Cancel", comment: "Album action")
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func create() async {
        let title = draftTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        do {
            let created = try await session.client.decode(
                Collection.self,
                from: Endpoint.collectionsExtra.create(CollectionDraft(title: title)))
            collections.insert(created, at: 0)
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func rename(_ collection: Collection) async {
        let title = draftTitle.trimmingCharacters(in: .whitespaces)
        renaming = nil
        guard !title.isEmpty, title != collection.title else { return }
        do {
            let updated = try await session.client.decode(
                Collection.self,
                from: Endpoint.collectionsExtra.update(
                    collection.id,
                    CollectionDraft(title: title, description: collection.description ?? "")))
            if let index = collections.firstIndex(where: { $0.id == collection.id }) {
                collections[index] = updated
            }
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func delete(_ collection: Collection) async {
        let before = collections
        collections.removeAll { $0.id == collection.id }
        do {
            _ = try await session.client.send(Endpoint.collectionsExtra.delete(collection.id))
            errorMessage = nil
        } catch {
            collections = before
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func card(_ collection: Collection) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
            RemoteImage(url: collection.thumbnail)
                .aspectRatio(1, contentMode: .fill)
                .clipShape(
                    RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous))

            Text(collection.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Text("^[\(collection.postCount) post](inflect: true)", comment: "Album post count")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard session.capabilities.collections else { return }

        let endpoint =
            accountID.map { Endpoint.collections.forAccount($0) } ?? Endpoint.collections.all
        collections =
            (try? await session.client.decode(LossyArray<Collection>.self, from: endpoint))?
            .elements
            ?? []
    }
}

public struct CollectionDetailView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession
    private let collection: Collection
    private let isOwn: Bool
    private let onAction: (StatusRowAction) -> Void

    @State private var statuses: [Status] = []

    public init(
        session: AccountSession, collection: Collection, isOwn: Bool = false,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.session = session
        self.collection = collection
        self.isOwn = isOwn
        self.onAction = onAction
    }

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 2), count: 3)

    public var body: some View {
        ScrollView {
            if let description = collection.description, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AlohaMetrics.space3)
            }

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(statuses) { status in
                    Button {
                        onAction(.openMedia(status: status.displayed, index: 0))
                    } label: {
                        RemoteImage(
                            url: status.displayed.mediaAttachments.first?.displayImageURL,
                            blurhash: status.displayed.mediaAttachments.first?.blurhash,
                            accessibilityText: status.displayed.mediaAttachments.first?.description
                        )
                        .aspectRatio(1, contentMode: .fill)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            onAction(.open(status))
                        } label: {
                            Label {
                                Text("Open post", comment: "Album item action")
                            } icon: {
                                Image(systemName: "arrow.up.right.square")
                            }
                        }
                        if isOwn {
                            Button(role: .destructive) {
                                Task { await remove(status) }
                            } label: {
                                Label {
                                    Text("Remove from album", comment: "Album item action")
                                } icon: {
                                    Image(systemName: "minus.circle")
                                }
                            }
                        }
                    }
                }
            }

            if statuses.isEmpty {
                Text("Nothing in this album yet.", comment: "Empty album")
                    .font(.footnote)
                    .foregroundStyle(palette.tertiaryLabel)
                    .padding(.top, AlohaMetrics.space6)
            }
        }
        .background(palette.background)
        .navigationTitle(collection.title)
        .task {
            statuses =
                (try? await session.client.decode(
                    LossyArray<Status>.self,
                    from: Endpoint.collections.items(collection.id)))?.elements ?? []
        }
    }

    private func remove(_ status: Status) async {
        let before = statuses
        statuses.removeAll { $0.id == status.id }
        do {
            _ = try await session.client.send(
                Endpoint.collectionsExtra.removeItem(collection.id, statusID: status.id))
        } catch {
            statuses = before
            await session.handle(error)
        }
    }
}
