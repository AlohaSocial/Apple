// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Every version of an edited post, newest first, as the server kept them
/// (`GET /api/v1/statuses/{id}/history`).
public struct EditHistorySheet: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let status: Status
    private let session: AccountSession

    @State private var edits: [StatusEdit] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init(status: Status, session: AccountSession) {
        self.status = status
        self.session = session
    }

    public var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    errorStrip(errorMessage)
                }

                // Identity is the offset, which is always unique. The server's
                // `created_at` is only second-resolution and two rapid edits
                // can share it; duplicating a `ForEach` id crashes at runtime
                // ("identifier is not unique"), which is worse than an index
                // that shifts on reload. History is a static server-ordered
                // list, so the offset does not actually reshuffle.
                ForEach(Array(edits.enumerated()), id: \.offset) { index, edit in
                    version(edit, isCurrent: index == 0, number: edits.count - index)
                        .listRowBackground(palette.background)
                }

                if edits.isEmpty && !isLoading && errorMessage == nil {
                    ContentUnavailableView {
                        Text("No history", comment: "Empty edit history")
                    } description: {
                        Text(
                            "This server keeps no record of earlier versions.",
                            comment: "Edit history empty detail")
                    }
                    .listRowBackground(palette.background)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .alohaGround(palette)
            .overlay {
                if isLoading && edits.isEmpty {
                    SkeletonListRow(text: 3)
                }
            }
            .navigationTitle(Text("Edit history", comment: "Screen title"))
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

    private func version(_ edit: StatusEdit, isCurrent: Bool, number: Int) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            HStack(spacing: AlohaMetrics.space2) {
                if isCurrent {
                    Text("Current version", comment: "Edit history label")
                        .font(AlohaType.section)
                } else if number == 1 {
                    Text("Original", comment: "Edit history label")
                        .font(AlohaType.section)
                } else {
                    Text("Version \(number)", comment: "Edit history label")
                        .font(AlohaType.section)
                }
                Spacer()
                Text(edit.createdAt, format: .dateTime.day().month().year().hour().minute())
                    .font(AlohaType.meta)
                    .foregroundStyle(palette.tertiaryLabel)
            }

            if !edit.spoilerText.isEmpty {
                Label {
                    Text(edit.spoilerText)
                } icon: {
                    Image(systemName: AlohaSymbol.warning)
                }
                .font(.footnote.weight(.medium))
            }

            RichTextView(
                status: Status(
                    id: "\(status.id)-v\(number)", content: edit.content,
                    account: edit.account, mediaAttachments: edit.mediaAttachments),
                isSelectable: true)

            if !edit.mediaAttachments.isEmpty {
                Text(
                    "^[\(edit.mediaAttachments.count) attachment](inflect: true)",
                    comment: "Edit history media count"
                )
                .font(AlohaType.meta)
                .foregroundStyle(palette.tertiaryLabel)
            }
        }
        .padding(.vertical, AlohaMetrics.space2)
    }

    private func errorStrip(_ message: String) -> some View {
        AlohaErrorStrip(message: message) {
            Task { await load() }
        }
        .listRowBackground(palette.background)
        .listRowSeparator(.hidden)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let versions = try await session.client.decode(
                LossyArray<StatusEdit>.self, from: Endpoint.statuses.history(status.id))
            // The server lists oldest first; the newest belongs at the top.
            edits = versions.elements.sorted { $0.createdAt > $1.createdAt }
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
