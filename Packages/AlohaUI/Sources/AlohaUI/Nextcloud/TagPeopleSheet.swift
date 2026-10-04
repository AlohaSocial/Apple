// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// "Who is in this photo?" — handles, separated by commas, from any server.
/// The people named are told, and the photo appears under Tagged on their
/// profile (`POST /api/v1.1/compose/tag`).
public struct TagPeopleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alohaPalette) private var palette

    private let status: Status
    private let session: AccountSession

    @State private var handles = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    public init(status: Status, session: AccountSession) {
        self.status = status
        self.session = session
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        String(
                            localized: "alice@cloud.example, bob",
                            comment: "Tag people field placeholder"),
                        text: $handles, axis: .vertical
                    )
                    .lineLimit(1...4)
                    .focused($isFocused)
                    .disabled(isLoading || isSaving || !hasLoaded)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    #endif
                    .autocorrectionDisabled()
                    .accessibilityLabel(Text("People in this photo", comment: "Tag people field"))
                } header: {
                    Text("Who is in this photo?", comment: "Tag people section")
                } footer: {
                    Text(
                        "Handles, separated by commas — for example alice@cloud.example. Everyone named is told, and the photo appears under Tagged on their profile.",
                        comment: "Tag people explanation")
                }

                if let errorMessage {
                    Section {
                        Label {
                            Text(errorMessage)
                        } icon: {
                            Image(systemName: AlohaSymbol.warning)
                        }
                        .font(.footnote)
                        .foregroundStyle(palette.destructive)
                        if !hasLoaded {
                            Button("Try again") { Task { await loadExisting() } }
                                .buttonStyle(.glass)
                                .disabled(isLoading)
                        }
                    }
                }

                if let first = status.mediaAttachments.first {
                    Section {
                        RemoteImage(
                            url: first.displayImageURL, blurhash: first.blurhash,
                            accessibilityText: first.description
                        )
                        .aspectRatio(first.displayAspectRatio, contentMode: .fit)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .alohaGround(palette)
            .overlay {
                if isLoading { ProgressView() }
            }
            .navigationTitle(Text("Tag people", comment: "Screen title"))
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
                    .disabled(isSaving)
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
                    .disabled(isSaving || isLoading || !hasLoaded)
                }
            }
            .task { await loadExisting() }
            .interactiveDismissDisabled(isSaving)
        }
    }

    /// The people already tagged fill the field, so editing is editing rather
    /// than starting over.
    private func loadExisting() async {
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            if hasLoaded && !Task.isCancelled { isFocused = true }
        }
        do {
            let existing = try await session.client.decode(
                StatusTaggedPeople.self, from: Endpoint.statuses.status(status.id))
            guard !Task.isCancelled else { return }
            let acct = existing.taggedPeople.map(\.acct).filter { !$0.isEmpty }
            handles = acct.joined(separator: ", ")
            hasLoaded = true
        } catch {
            guard !Task.isCancelled else { return }
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
                ?? String(localized: "Tagged people could not be loaded. Please try again.")
        }
    }

    private var parsed: [String] {
        handles.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.hasPrefix("@") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty }
    }

    private func save() async {
        guard hasLoaded, !isLoading, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await session.client.decode(
                TaggedPeopleResponse.self,
                from: Endpoint.profile.tagPeople(statusID: status.id, handles: parsed))
            dismiss()
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "Couldn't tag them.", comment: "Tag people failed")
        }
    }
}
