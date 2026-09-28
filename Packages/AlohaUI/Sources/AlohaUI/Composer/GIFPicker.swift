// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// The instance's own library of animated pictures. Searching it tells
/// nobody outside the server what was typed, which is the reason it exists
/// instead of a third-party GIF service.
struct GIFPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alohaPalette) private var palette

    let session: AccountSession
    let onPick: (GIFEntry) -> Void

    @State private var query = ""
    @State private var library: GIFLibrary?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: AlohaMetrics.space2)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(palette.destructive)
                        .padding(AlohaMetrics.space3)
                }

                LazyVGrid(columns: columns, spacing: AlohaMetrics.space2) {
                    ForEach(library?.gifs ?? []) { entry in
                        Button {
                            onPick(entry)
                            dismiss()
                        } label: {
                            RemoteImage(
                                url: entry.previewURL ?? entry.url,
                                accessibilityText: entry.title
                            )
                            .aspectRatio(1, contentMode: .fill)
                            .frame(minHeight: 100)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: AlohaMetrics.cornerSmall, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(entry.title))
                    }
                }
                .padding(AlohaMetrics.space3)

                if let library {
                    if library.gifs.isEmpty && !isLoading {
                        ContentUnavailableView {
                            Text("Nothing matches", comment: "GIF picker empty")
                        }
                        .padding(.top, AlohaMetrics.space5)
                    }
                    if let attribution = library.attribution, !attribution.isEmpty {
                        Text(attribution)
                            .font(.caption2)
                            .foregroundStyle(palette.tertiaryLabel)
                            .multilineTextAlignment(.center)
                            .padding(AlohaMetrics.space3)
                    }
                } else if isLoading {
                    ProgressView().padding(.top, AlohaMetrics.space5)
                }
            }
            .background(palette.background)
            .searchable(text: $query, prompt: Text("Search pictures", comment: "GIF search prompt"))
            .navigationTitle(Text("Pictures", comment: "GIF picker title"))
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
            .task(id: query) { await load() }
        }
    }

    private func load() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await session.client.decode(
                GIFLibrary.self, from: Endpoint.gifs.library(query: trimmed, limit: 60))
            guard !Task.isCancelled else { return }
            library = page
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}
