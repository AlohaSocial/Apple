// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// `GET /api/v1/scheduled_statuses` sends **no `Link` header** — a
/// `ScheduledStatus` carries no status nid for one to point at — so it is
/// fetched whole rather than paged (docs/02 §5).
public struct ScheduledPostsView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession
    @State private var scheduled: [ScheduledStatus] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        List {
            ForEach(scheduled) { post in
                VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                    HStack(spacing: AlohaMetrics.space2) {
                        Image(systemName: "clock")
                            .foregroundStyle(palette.accent)
                        Text(
                            post.scheduledAt,
                            format: .dateTime.weekday().day().month().hour().minute()
                        )
                        .font(.footnote.weight(.medium))
                        Spacer()
                        Text(post.scheduledAt, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryLabel)
                    }

                    if let text = post.params.text, !text.isEmpty {
                        Text(text).font(.subheadline).lineLimit(4)
                    }

                    if !post.mediaAttachments.isEmpty {
                        Label {
                            Text(
                                "^[\(post.mediaAttachments.count) attachment](inflect: true)",
                                comment: "Scheduled post attachment count")
                        } icon: {
                            Image(systemName: AlohaSymbol.media)
                        }
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                    }
                }
                .padding(.vertical, AlohaMetrics.space1)
            }
            .onDelete { offsets in
                Task { await cancel(at: offsets) }
            }

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(palette.destructive)
            }

            if scheduled.isEmpty && !isLoading {
                ContentUnavailableView {
                    Text("Nothing scheduled", comment: "Empty scheduled posts")
                } description: {
                    Text(
                        "Posts you schedule from the composer wait here until they go out.",
                        comment: "Scheduled posts explanation")
                }
            }
        }
        .navigationTitle(Text("Scheduled", comment: "Screen title"))
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            scheduled = try await session.client.decode(
                LossyArray<ScheduledStatus>.self, from: Endpoint.composing.scheduled
            ).elements
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func cancel(at offsets: IndexSet) async {
        let targets = offsets.map { scheduled[$0] }
        scheduled.remove(atOffsets: offsets)
        for post in targets {
            _ = try? await session.client.send(Endpoint.composing.deleteScheduled(post.id))
        }
    }
}

/// The date picker the composer uses. A scheduled post has to be at least five
/// minutes out, which is Mastodon's own floor.
public struct SchedulePicker: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @Binding private var scheduledAt: Date?
    @State private var date: Date

    public init(scheduledAt: Binding<Date?>) {
        _scheduledAt = scheduledAt
        _date = State(
            initialValue: scheduledAt.wrappedValue ?? Date().addingTimeInterval(3600))
    }

    private var earliest: Date { Date().addingTimeInterval(300) }

    public var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    selection: $date, in: earliest...,
                    displayedComponents: [.date, .hourAndMinute]
                ) {
                    Text("Send at", comment: "Schedule picker label")
                }
                #if os(iOS)
                    .datePickerStyle(.graphical)
                #endif

                if scheduledAt != nil {
                    Button(role: .destructive) {
                        scheduledAt = nil
                        dismiss()
                    } label: {
                        Text("Post immediately instead", comment: "Schedule action")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Schedule", comment: "Schedule picker title"))
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
                        scheduledAt = max(date, earliest)
                        dismiss()
                    } label: {
                        Text("Schedule", comment: "Schedule action")
                    }
                }
            }
        }
    }
}
