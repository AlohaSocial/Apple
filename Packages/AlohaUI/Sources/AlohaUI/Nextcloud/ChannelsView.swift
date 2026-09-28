// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Your video channels: what a video belongs to on PeerTube. The server makes
/// one the first time you post a video; more can be made and any renamed.
public struct ChannelsView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession

    @State private var channels: [VideoChannel] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var editing: ChannelDraft?

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(palette.destructive)
            }

            ForEach(channels) { channel in
                Button {
                    editing = ChannelDraft(channel: channel)
                } label: {
                    HStack(spacing: AlohaMetrics.space3) {
                        Image(systemName: "tv")
                            .font(.title3)
                            .foregroundStyle(palette.accent)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(channel.name.isEmpty ? channel.handle : channel.name)
                                .font(AlohaType.name)
                                .foregroundStyle(palette.label)
                            Text(verbatim: "@\(channel.handle)")
                                .font(AlohaType.meta)
                                .foregroundStyle(palette.tertiaryLabel)
                            if !channel.description.isEmpty {
                                Text(channel.description)
                                    .font(.footnote)
                                    .foregroundStyle(palette.secondaryLabel)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        if channel.videosCount > 0 {
                            Text(
                                "^[\(channel.videosCount) video](inflect: true)",
                                comment: "Channel video count"
                            )
                            .font(AlohaType.meta)
                            .foregroundStyle(palette.tertiaryLabel)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Edits the channel", comment: "Accessibility hint"))
            }

            if channels.isEmpty && !isLoading {
                ContentUnavailableView {
                    Text("No channels yet", comment: "Empty channels")
                } description: {
                    Text(
                        "Your first video makes one. Or make one now and post into it.",
                        comment: "Empty channels detail")
                }
            }
        }
        .navigationTitle(Text("Video channels", comment: "Screen title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = ChannelDraft()
                } label: {
                    Label {
                        Text("New channel", comment: "Channels action")
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(item: $editing) { draft in
            ChannelEditor(draft: draft) { saved in
                await save(saved)
            }
        }
        .overlay {
            if isLoading && channels.isEmpty { ProgressView() }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            channels = try await session.client.decode(
                VideoChannelList.self, from: Endpoint.channels.all
            ).channels
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    /// Every write answers the full list, so the list is what we keep.
    private func save(_ draft: ChannelDraft) async -> String? {
        do {
            let endpoint =
                draft.existingID.map {
                    Endpoint.channels.update($0, name: draft.name, description: draft.description)
                }
                ?? Endpoint.channels.create(
                    handle: draft.handle, name: draft.name, description: draft.description)
            let list = try await session.client.decode(VideoChannelList.self, from: endpoint)
            if !list.channels.isEmpty { channels = list.channels } else { await load() }
            return nil
        } catch {
            await session.handle(error)
            return (error as? APIError)?.errorDescription
                ?? String(localized: "Couldn't save that.", comment: "Channel save failed")
        }
    }
}

struct ChannelDraft: Identifiable {
    var existingID: String?
    var handle = ""
    var name = ""
    var description = ""
    var id: String { existingID ?? "new" }

    init() {}

    init(channel: VideoChannel) {
        existingID = channel.id
        handle = channel.handle
        name = channel.name
        description = channel.description
    }
}

/// One sheet for making and renaming. The handle is fixed once made.
struct ChannelEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alohaPalette) private var palette

    @State var draft: ChannelDraft
    let onSave: (ChannelDraft) async -> String?

    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isNew: Bool { draft.existingID == nil }

    private var canSave: Bool {
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return false }
        return !isNew || isValidHandle(draft.handle)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isNew {
                        TextField(
                            String(localized: "handle", comment: "Channel handle placeholder"),
                            text: $draft.handle
                        )
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    } else {
                        LabeledContent {
                            Text("@\(draft.handle)")
                        } label: {
                            Text("Handle", comment: "Channel field")
                        }
                    }
                    TextField(
                        String(localized: "Name", comment: "Channel name placeholder"),
                        text: $draft.name)
                    TextField(
                        String(
                            localized: "Description", comment: "Channel description placeholder"),
                        text: $draft.description, axis: .vertical
                    )
                    .lineLimit(2...6)
                } footer: {
                    if isNew {
                        Text(
                            "The handle is the channel's address and cannot change later. Letters, numbers and underscores.",
                            comment: "Channel handle explanation")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(palette.destructive)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(
                isNew
                    ? Text("New channel", comment: "Screen title")
                    : Text("Edit channel", comment: "Screen title")
            )
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
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            isSaving = true
                            defer { isSaving = false }
                            if let failure = await onSave(draft) {
                                errorMessage = failure
                            } else {
                                dismiss()
                            }
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save", comment: "Sheet action")
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
    }

    private func isValidHandle(_ handle: String) -> Bool {
        let trimmed = handle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 64 else { return false }
        return trimmed.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_"
        }
    }
}
