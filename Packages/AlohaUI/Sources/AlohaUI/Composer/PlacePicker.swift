// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Where a post was made. Search the places the server knows; failing that,
/// make one from a name and a country. No map service is involved on either
/// side — a place is a name people can search for.
struct PlacePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alohaPalette) private var palette

    let session: AccountSession
    let onPick: (ComposerModel.ComposerPlace) -> Void

    @State private var query = ""
    @State private var results: [Place] = []
    @State private var isSearching = false
    @State private var country = ""
    @State private var isNaming = false

    var body: some View {
        NavigationStack {
            List {
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section {
                        ForEach(results) { place in
                            Button {
                                onPick(.known(place))
                                dismiss()
                            } label: {
                                HStack(spacing: AlohaMetrics.space3) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundStyle(palette.accent)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(place.name).font(AlohaType.name)
                                        if let country = place.country, !country.isEmpty {
                                            Text(country)
                                                .font(AlohaType.meta)
                                                .foregroundStyle(palette.secondaryLabel)
                                        }
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        if results.isEmpty && !isSearching {
                            Text("No place by that name yet.", comment: "Place search empty")
                                .font(.footnote)
                                .foregroundStyle(palette.tertiaryLabel)
                        }
                    } header: {
                        Text("Places", comment: "Place picker section")
                    }

                    Section {
                        if isNaming {
                            TextField(
                                text: $country,
                                prompt: Text("Country", comment: "Place country placeholder")
                            ) {
                                Text("Country", comment: "Place country label")
                            }
                            Button {
                                onPick(
                                    .new(
                                        name: query.trimmingCharacters(in: .whitespaces),
                                        country: country.trimmingCharacters(in: .whitespaces)))
                                dismiss()
                            } label: {
                                Text(
                                    "Add \"\(query.trimmingCharacters(in: .whitespaces))\"",
                                    comment: "Place create action")
                            }
                        } else {
                            Button {
                                withAnimation { isNaming = true }
                            } label: {
                                Label {
                                    Text("Use this name", comment: "Place picker action")
                                } icon: {
                                    Image(systemName: "plus.circle")
                                }
                            }
                        }
                    } footer: {
                        Text(
                            "A new place is just a name and a country. Nothing is looked up on a map.",
                            comment: "Place picker footer")
                    }
                } else {
                    Text(
                        "Type the name of a town, a venue, a park.",
                        comment: "Place picker hint"
                    )
                    .font(.footnote)
                    .foregroundStyle(palette.tertiaryLabel)
                }
            }
            .searchable(text: $query, prompt: Text("Search places", comment: "Place search prompt"))
            .navigationTitle(Text("Add a place", comment: "Screen title"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel", comment: "Sheet action")
                    }
                }
            }
            .task(id: query) { await search() }
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        let found = try? await session.client.decode(
            LossyArray<Place>.self, from: Endpoint.places.search(trimmed))
        guard !Task.isCancelled else { return }
        results = found?.elements ?? []
    }
}
