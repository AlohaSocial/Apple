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
    @State private var rescheduling: ScheduledStatus?
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        List {
            ForEach(scheduled) { post in
                Button {
                    rescheduling = post
                } label: {
                    row(post)
                }
                .buttonStyle(.plain)
                .accessibilityHint(
                    Text("Choose another time to send it", comment: "Scheduled post row hint"))
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
        .sheet(item: $rescheduling) { post in
            RescheduleSheet(current: post.scheduledAt) { date in
                Task { await reschedule(post, to: date) }
            }
        }
    }

    private func row(_ post: ScheduledStatus) -> some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Replaced with what the server answers, so the row shows the time it
    /// will really go out. A refusal — too soon, most likely — leaves the row
    /// as it was and says why.
    private func reschedule(_ post: ScheduledStatus, to date: Date) async {
        do {
            let updated = try await session.client.decode(
                ScheduledStatus.self, from: Endpoint.composing.reschedule(post.id, to: date))
            if let index = scheduled.firstIndex(where: { $0.id == post.id }) {
                scheduled[index] = updated
            }
            scheduled.sort { $0.scheduledAt < $1.scheduledAt }
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "Couldn't move that post.", comment: "Reschedule failure")
        }
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

    /// The rows go at once, and any the server refused come back: a scheduled
    /// post that vanished from this list but still publishes is the one
    /// outcome that must never happen.
    private func cancel(at offsets: IndexSet) async {
        let targets = offsets.map { scheduled[$0] }
        scheduled.remove(atOffsets: offsets)
        var refused: [ScheduledStatus] = []
        var lastError: (any Error)?
        for post in targets {
            do {
                _ = try await session.client.send(Endpoint.composing.deleteScheduled(post.id))
            } catch {
                refused.append(post)
                lastError = error
            }
        }
        guard let lastError else {
            errorMessage = nil
            return
        }
        await session.handle(lastError)
        scheduled = Self.restoring(refused, into: scheduled)
        errorMessage = StatusActions.failureMessage(
            lastError,
            fallback: String(
                localized: "That post could not be cancelled. It will still go out.",
                comment: "Scheduled post cancel failure"))
    }

    /// Puts refused rows back where they belong — the list is in the order
    /// the posts go out — without doubling any that is still there.
    static func restoring(
        _ refused: [ScheduledStatus], into list: [ScheduledStatus]
    ) -> [ScheduledStatus] {
        let present = Set(list.map(\.id))
        return (list + refused.filter { !present.contains($0.id) })
            .sorted { $0.scheduledAt < $1.scheduledAt }
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

/// Another time for a post already waiting. Not `SchedulePicker`: that one
/// can also clear the schedule, and for a post the server is holding there is
/// no "post immediately instead" to fall back to.
struct RescheduleSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let onChoose: (Date) -> Void
    @State private var date: Date

    init(current: Date, onChoose: @escaping (Date) -> Void) {
        self.onChoose = onChoose
        _date = State(initialValue: max(current, Date().addingTimeInterval(300)))
    }

    /// The server's own floor, five minutes out (`ScheduledStatusService`).
    private var earliest: Date { Date().addingTimeInterval(300) }

    var body: some View {
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
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Reschedule", comment: "Reschedule sheet title"))
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
                        onChoose(max(date, earliest))
                        dismiss()
                    } label: {
                        Text("Save", comment: "Reschedule action")
                    }
                }
            }
        }
    }
}
