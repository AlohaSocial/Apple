// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Put a post into one of your albums, take it out again, or start a new
/// album with it (docs/06 §5).
///
/// The server does not say which albums already hold a post, so membership is
/// read once from each album's items — a handful of small requests, and
/// only when the sheet opens.
public struct CollectionPickerSheet: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let status: Status
    private let session: AccountSession

    @State private var collections: [Collection] = []
    @State private var containing: Set<String> = []
    @State private var busy: Set<String> = []
    @State private var newTitle = ""
    @State private var isCreating = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init(status: Status, session: AccountSession) {
        self.status = status
        self.session = session
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: AlohaMetrics.space2) {
                        TextField(
                            String(
                                localized: "New album", comment: "Collection picker placeholder"),
                            text: $newTitle
                        )
                        .textFieldStyle(.plain)
                        .onSubmit { Task { await create() } }
                        Button {
                            Task { await create() }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(canCreate ? palette.accent : palette.tertiaryLabel)
                        .disabled(!canCreate)
                        .accessibilityLabel(
                            Text("Create album", comment: "Collection picker action"))
                    }
                } header: {
                    Text("Start a new album with this post", comment: "Collection picker section")
                }

                Section {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(palette.destructive)
                    }
                    ForEach(collections) { collection in
                        row(collection)
                    }
                    if collections.isEmpty && !isLoading {
                        Text("No albums yet.", comment: "Collection picker empty state")
                            .font(.footnote)
                            .foregroundStyle(palette.tertiaryLabel)
                    }
                } header: {
                    Text("Your albums", comment: "Collection picker section")
                }
            }
            .navigationTitle(Text("Add to album", comment: "Screen title"))
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

    private var canCreate: Bool {
        !isCreating && !newTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func row(_ collection: Collection) -> some View {
        let isIn = containing.contains(collection.id)
        return Button {
            Task { await toggle(collection) }
        } label: {
            HStack(spacing: AlohaMetrics.space3) {
                RemoteImage(url: collection.thumbnail) {
                    Image(systemName: "rectangle.stack")
                        .foregroundStyle(palette.tertiaryLabel)
                }
                .frame(width: 44, height: 44)
                .clipShape(
                    RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(
                        "^[\(collection.postCount) post](inflect: true)",
                        comment: "Album post count"
                    )
                    .font(AlohaType.meta)
                    .foregroundStyle(palette.secondaryLabel)
                }
                Spacer()
                if busy.contains(collection.id) {
                    ProgressView()
                } else {
                    Image(systemName: isIn ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isIn ? palette.accent : palette.tertiaryLabel)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy.contains(collection.id))
        .accessibilityLabel(Text(collection.title))
        .accessibilityAddTraits(isIn ? [.isButton, .isSelected] : .isButton)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            collections = try await session.client.decode(
                LossyArray<Collection>.self, from: Endpoint.collections.all
            ).elements
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
            return
        }
        // Which albums already hold this post.
        await withTaskGroup(of: (String, Bool).self) { group in
            for collection in collections {
                group.addTask {
                    let items = try? await session.client.decode(
                        LossyArray<Status>.self, from: Endpoint.collections.items(collection.id))
                    return (collection.id, items?.elements.contains { $0.id == status.id } ?? false)
                }
            }
            for await (id, holds) in group where holds {
                containing.insert(id)
            }
        }
    }

    private func toggle(_ collection: Collection) async {
        busy.insert(collection.id)
        defer { busy.remove(collection.id) }
        let isIn = containing.contains(collection.id)
        let endpoint =
            isIn
            ? Endpoint.collectionsExtra.removeItem(collection.id, statusID: status.id)
            : Endpoint.collectionsExtra.addItem(collection.id, statusID: status.id)
        do {
            _ = try await session.client.send(endpoint)
            if isIn { containing.remove(collection.id) } else { containing.insert(collection.id) }
            if let index = collections.firstIndex(where: { $0.id == collection.id }) {
                collections[index].postCount = max(
                    0, collections[index].postCount + (isIn ? -1 : 1))
            }
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func create() async {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            var created = try await session.client.decode(
                Collection.self,
                from: Endpoint.collectionsExtra.create(CollectionDraft(title: title)))
            _ = try await session.client.send(
                Endpoint.collectionsExtra.addItem(created.id, statusID: status.id))
            created.postCount += 1
            collections.insert(created, at: 0)
            containing.insert(created.id)
            newTitle = ""
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}
