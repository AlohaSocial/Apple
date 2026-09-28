// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// The hashtags shown at the top of your profile: up to ten, with how often
/// you have used each, and the ones you post with but have not featured.
public struct FeaturedTagsView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession

    @State private var featured: [FeaturedTag] = []
    @State private var suggestions: [FeaturedTagSuggestion] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    static let limit = 10

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        List {
            if let errorMessage {
                Section {
                    Label {
                        Text(errorMessage)
                    } icon: {
                        Image(systemName: AlohaSymbol.warning)
                    }
                    .font(.footnote)
                    .foregroundStyle(palette.destructive)
                }
            }

            Section {
                ForEach(featured) { tag in
                    HStack(spacing: AlohaMetrics.space3) {
                        Text(verbatim: "#\(tag.name)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.hashtag)
                            .padding(.horizontal, AlohaMetrics.space3)
                            .padding(.vertical, AlohaMetrics.space1)
                            .background(palette.hashtag.opacity(0.12), in: Capsule())
                        Text(
                            "^[\(tag.statusesCount) post](inflect: true)",
                            comment: "Featured tag use count"
                        )
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                        Spacer()
                        Button(role: .destructive) {
                            Task { await remove(tag) }
                        } label: {
                            Image(systemName: "minus.circle")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(
                            Text("Stop featuring #\(tag.name)", comment: "Featured tag action"))
                    }
                }
                if featured.isEmpty && !isLoading {
                    Text(
                        "Featured hashtags appear at the top of your profile, so people see what you post about before they scroll.",
                        comment: "Featured tags empty state"
                    )
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
                }
            } header: {
                Text("Featured", comment: "Featured tags section")
            } footer: {
                Text("Up to \(Self.limit).", comment: "Featured tags limit")
            }

            if featured.count < Self.limit {
                Section {
                    HStack(spacing: AlohaMetrics.space2) {
                        Text(verbatim: "#")
                            .foregroundStyle(palette.tertiaryLabel)
                        TextField(
                            String(localized: "hashtag", comment: "Featured tag field placeholder"),
                            text: $draft
                        )
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .onSubmit { Task { await add(draft) } }
                        Button {
                            Task { await add(draft) }
                        } label: {
                            if isSaving {
                                ProgressView()
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(!isValid(draft) || isSaving)
                        .accessibilityLabel(
                            Text("Feature this hashtag", comment: "Featured tag action"))
                    }
                    if !draft.isEmpty && !isValid(draft) {
                        Text("That isn't a hashtag.", comment: "Featured tag validation")
                            .font(.caption)
                            .foregroundStyle(palette.destructive)
                    }
                } header: {
                    Text("Add one", comment: "Featured tags section")
                }
            }

            let unused = suggestions.filter { suggestion in
                !featured.contains { $0.name.lowercased() == suggestion.name.lowercased() }
            }
            if !unused.isEmpty && featured.count < Self.limit {
                Section {
                    ForEach(unused) { suggestion in
                        Button {
                            Task { await add(suggestion.name) }
                        } label: {
                            Label {
                                Text(verbatim: "#\(suggestion.name)")
                            } icon: {
                                Image(systemName: "plus")
                            }
                        }
                        .disabled(isSaving)
                    }
                } header: {
                    Text("Hashtags you post with", comment: "Featured tags section")
                }
            }
        }
        .navigationTitle(Text("Featured hashtags", comment: "Screen title"))
        .overlay {
            if isLoading && featured.isEmpty { ProgressView() }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    /// Lowercase, no `#`, at most 127 characters, nothing that normalises to
    /// nothing — the server's own rule (docs/05 §8).
    private func normalised(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .lowercased()
    }

    private func isValid(_ raw: String) -> Bool {
        let name = normalised(raw)
        guard !name.isEmpty, name.count <= 127 else { return false }
        return name.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_"
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let tags = session.client.decode(
                LossyArray<FeaturedTag>.self, from: Endpoint.featuredTags.all)
            async let suggested = session.client.decode(
                LossyArray<FeaturedTagSuggestion>.self, from: Endpoint.featuredTags.suggestions)
            featured = try await tags.elements
            // Suggestions are a nicety; their failure is nobody's problem.
            suggestions = (try? await suggested.elements) ?? []
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func add(_ raw: String) async {
        let name = normalised(raw)
        guard isValid(name), featured.count < Self.limit else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let tag = try await session.client.decode(
                FeaturedTag.self, from: Endpoint.featuredTags.create(name: name))
            // Featuring an already-featured tag replaces it, so replace here too.
            featured.removeAll { $0.name.lowercased() == tag.name.lowercased() }
            featured.append(tag)
            draft = ""
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func remove(_ tag: FeaturedTag) async {
        let previous = featured
        featured.removeAll { $0.id == tag.id }
        do {
            _ = try await session.client.send(Endpoint.featuredTags.delete(tag.id))
            suggestions =
                (try? await session.client.decode(
                    LossyArray<FeaturedTagSuggestion>.self, from: Endpoint.featuredTags.suggestions))?
                .elements ?? suggestions
        } catch {
            featured = previous
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}
