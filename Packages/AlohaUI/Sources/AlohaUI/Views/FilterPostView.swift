// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Putting one post under a filter by name — for the post no keyword could
/// describe without catching others too (`/api/v2/filters/{id}/statuses`).
///
/// Every filter is listed with whether it already covers the post; a tap
/// adds or removes it, and a new filter can be made for it on the spot.
struct FilterPostView: View {
    @Environment(\.alohaPalette) private var palette

    let statusID: String
    let session: AccountSession

    @State private var filters: [Filter] = []
    @State private var isLoading = true
    @State private var busy: Set<String> = []
    @State private var errorMessage: String?
    @State private var newTitle = ""
    @State private var newAction: FilterAction = .hide

    private static let newFilterKey = "new"

    var body: some View {
        Form {
            if let errorMessage {
                AlohaErrorStrip(message: errorMessage) { Task { await load() } }
            }

            if !filters.isEmpty {
                Section {
                    ForEach(filters) { filter in
                        filterRow(filter)
                    }
                } footer: {
                    Text(
                        "A filter that covers this post hides it or warns about it wherever the filter applies, whatever its words.",
                        comment: "Filter this post explanation")
                }
            }

            Section {
                TextField(
                    String(localized: "Name of the filter", comment: "Filter this post field"),
                    text: $newTitle)
                Picker(selection: $newAction) {
                    Text("Hide it", comment: "Filter action").tag(FilterAction.hide)
                    Text("Warn me", comment: "Filter action").tag(FilterAction.warn)
                } label: {
                    Text("When it appears", comment: "Filter action picker")
                }
                Button {
                    Task { await createAndAdd() }
                } label: {
                    if busy.contains(Self.newFilterKey) {
                        ProgressView()
                    } else {
                        Text(
                            "Make the filter and add this post", comment: "Filter this post action")
                    }
                }
                .disabled(
                    newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || busy.contains(Self.newFilterKey))
            } header: {
                Text("A new filter", comment: "Filter this post section")
            }
        }
        .alohaGround(palette)
        .navigationTitle(Text("Filter this post", comment: "Screen title"))
        .overlay {
            if isLoading && filters.isEmpty { SkeletonListRow(text: 3) }
        }
        .task { await load() }
    }

    private func filterRow(_ filter: Filter) -> some View {
        let isCovered = filter.statuses.contains { $0.statusID == statusID }
        return Button {
            Task { await toggle(filter) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(filter.title)
                        .foregroundStyle(palette.label)
                    Text(
                        "^[\(filter.keywords.count) word](inflect: true), ^[\(filter.statuses.count) post](inflect: true)",
                        comment: "Filter this post row detail"
                    )
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
                }
                Spacer()
                if busy.contains(filter.id) {
                    ProgressView()
                } else if isCovered {
                    Image(systemName: "checkmark")
                        .foregroundStyle(palette.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy.contains(filter.id))
        .accessibilityAddTraits(isCovered ? [.isButton, .isSelected] : .isButton)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            filters = try await session.client.decode(
                LossyArray<Filter>.self, from: Endpoint.filters.all
            ).elements
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "Your filters could not be loaded.",
                    comment: "Filter this post load failure")
        }
    }

    private func toggle(_ filter: Filter) async {
        guard busy.insert(filter.id).inserted else { return }
        defer { busy.remove(filter.id) }
        errorMessage = nil
        do {
            if let entry = filter.statuses.first(where: { $0.statusID == statusID }) {
                _ = try await session.client.send(Endpoint.filters.removeStatus(entryID: entry.id))
                update(filter.id) { $0.statuses.removeAll { $0.id == entry.id } }
            } else {
                let entry = try await session.client.decode(
                    Filter.StatusRef.self, from: Endpoint.filters.addStatus(statusID, to: filter.id)
                )
                update(filter.id) { $0.statuses.append(entry) }
            }
            await publish()
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "The filter could not be changed. Please try again.",
                    comment: "Filter this post failure")
        }
    }

    private func createAndAdd() async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, busy.insert(Self.newFilterKey).inserted else { return }
        defer { busy.remove(Self.newFilterKey) }
        errorMessage = nil
        do {
            // Everywhere a post can be read: a filter for one post is about
            // that post, not about where it turns up.
            var created = try await session.client.decode(
                Filter.self,
                from: Endpoint.filters.create(
                    title: title, context: [.home, .public, .thread, .account, .notifications],
                    action: newAction, expiresIn: nil, keywords: []))
            let entry = try await session.client.decode(
                Filter.StatusRef.self, from: Endpoint.filters.addStatus(statusID, to: created.id))
            created.statuses.append(entry)
            filters.append(created)
            newTitle = ""
            await publish()
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "The filter could not be made. Please try again.",
                    comment: "Filter this post create failure")
        }
    }

    private func update(_ id: String, _ change: (inout Filter) -> Void) {
        guard let index = filters.firstIndex(where: { $0.id == id }) else { return }
        change(&filters[index])
    }

    /// The timelines read their filters from the store, so the decision is
    /// there by their next load.
    private func publish() async {
        try? await session.supportStore.replaceFilters(filters, accountID: session.id)
    }
}
