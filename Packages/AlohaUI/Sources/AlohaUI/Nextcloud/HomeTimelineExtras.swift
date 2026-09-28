// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import AlohaNetwork
import SwiftUI

/// The cards that sit above the home timeline: unread announcements, "On this
/// day", and the weekly recap. Each draws only when it has something to say,
/// and each can be put away — announcements on the server, the other two on
/// this device for the day or the week.
///
/// Unread announcements interrupt; read ones do not.
struct HomeTimelineExtras: View {
    @Environment(\.alohaPalette) private var palette

    let session: AccountSession
    let onAction: (StatusRowAction) -> Void

    @State private var announcements: [ServerAnnouncement] = []
    @State private var isShowingRead = false
    @State private var memories: [Status] = []
    @State private var recap: WeeklyRecap?
    @State private var dismissedMemoriesDay = HomeExtrasDismissals.memoriesDay
    @State private var dismissedRecapWeek = HomeExtrasDismissals.recapWeek

    private static let reactionChoices = ["👍", "❤️", "🎉", "👀", "😢"]

    var body: some View {
        Group {
            if !announcements.isEmpty && (isShowingRead || hasUnread) {
                announcementsCard
            }
            if !memories.isEmpty && dismissedMemoriesDay != HomeExtrasDismissals.today {
                memoriesCard
            }
            if let recap, recap.enabled, dismissedRecapWeek != HomeExtrasDismissals.thisWeek {
                recapCard(recap)
            }
        }
        .task { await load() }
    }

    // MARK: - Announcements

    private var hasUnread: Bool { announcements.contains { !$0.read } }

    private var visibleAnnouncements: [ServerAnnouncement] {
        isShowingRead ? announcements : announcements.filter { !$0.read }
    }

    private var announcementsCard: some View {
        card {
            HStack {
                Label {
                    if announcements.count == 1 {
                        Text("Announcement", comment: "Announcements card title")
                    } else {
                        Text("Announcements", comment: "Announcements card title")
                    }
                } icon: {
                    Image(systemName: "megaphone")
                }
                .font(AlohaType.section)
                Spacer()
                if announcements.contains(where: \.read) {
                    Button {
                        withAnimation { isShowingRead.toggle() }
                    } label: {
                        (isShowingRead
                            ? Text("Hide read", comment: "Announcements card action")
                            : Text("Show read", comment: "Announcements card action"))
                            .font(.footnote)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.accent)
                }
            }

            ForEach(visibleAnnouncements) { announcement in
                announcementRow(announcement)
            }
        }
    }

    private func announcementRow(_ announcement: ServerAnnouncement) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            // Never rendered as HTML: an administrator's note is plain words.
            Text(
                StatusHTMLParser().plainText(announcement.content)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AlohaMetrics.space1) {
                if let date = announcement.publishedAt {
                    Text(date, format: .dateTime.day().month())
                }
                if let ends = announcement.endsAt {
                    Text(verbatim: "·")
                    Text(
                        "Until \(ends.formatted(.dateTime.day().month()))",
                        comment: "Announcement end date")
                }
                if announcement.read {
                    Text(verbatim: "·")
                    Text("Read", comment: "Announcement read state")
                }
            }
            .font(AlohaType.meta)
            .foregroundStyle(palette.tertiaryLabel)

            HStack(spacing: AlohaMetrics.space2) {
                ScrollView(.horizontal) {
                    HStack(spacing: AlohaMetrics.space1) {
                        ForEach(reactionRow(for: announcement)) { reaction in
                            reactionButton(reaction, on: announcement)
                        }
                    }
                }
                .scrollIndicators(.hidden)

                if !announcement.read {
                    Button {
                        Task { await dismiss(announcement) }
                    } label: {
                        Text("Got it", comment: "Announcement dismiss action")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, AlohaMetrics.space3)
                            .frame(minHeight: 36)
                            .background(palette.accent, in: Capsule())
                            .foregroundStyle(palette.onAccent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, AlohaMetrics.space2)
    }

    /// The reactions people left, then the choices left untouched, so there
    /// is always something to tap.
    private func reactionRow(for announcement: ServerAnnouncement) -> [ServerAnnouncement.Reaction]
    {
        let present = Set(announcement.reactions.map(\.name))
        return announcement.reactions
            + Self.reactionChoices.filter { !present.contains($0) }.map {
                ServerAnnouncement.Reaction(name: $0)
            }
    }

    private func reactionButton(
        _ reaction: ServerAnnouncement.Reaction, on announcement: ServerAnnouncement
    ) -> some View {
        Button {
            Task { await toggle(reaction, on: announcement) }
        } label: {
            HStack(spacing: 3) {
                Text(reaction.name)
                if reaction.count > 0 {
                    Text(reaction.count, format: .number)
                        .font(AlohaType.micro.monospacedDigit())
                }
            }
            .padding(.horizontal, AlohaMetrics.space2)
            .frame(minWidth: 36, minHeight: 36)
            .background(reaction.me ? palette.accentMuted : palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(palette.separator.opacity(0.6), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            reaction.me
                ? Text(
                    "Remove your \(reaction.name) reaction", comment: "Announcement reaction action"
                )
                : Text("React with \(reaction.name)", comment: "Announcement reaction action"))
    }

    // MARK: - On this day

    private var memoriesCard: some View {
        card {
            HStack {
                Label {
                    Text("On this day", comment: "Memories card title")
                } icon: {
                    Image(systemName: "calendar.badge.clock")
                }
                .font(AlohaType.section)
                Spacer()
                closeButton(label: Text("Hide for today", comment: "Memories card action")) {
                    HomeExtrasDismissals.memoriesDay = HomeExtrasDismissals.today
                    withAnimation { dismissedMemoriesDay = HomeExtrasDismissals.today }
                }
            }
            ForEach(memories.prefix(3)) { status in
                MemoryRow(status: status) { onAction(.open(status)) }
            }
        }
    }

    // MARK: - Weekly recap

    private func recapCard(_ recap: WeeklyRecap) -> some View {
        card {
            HStack(alignment: .top) {
                WeeklyRecapSummary(recap: recap)
                Spacer()
                closeButton(label: Text("Hide for this week", comment: "Recap card action")) {
                    HomeExtrasDismissals.recapWeek = HomeExtrasDismissals.thisWeek
                    withAnimation { dismissedRecapWeek = HomeExtrasDismissals.thisWeek }
                }
            }
        }
    }

    // MARK: - Pieces

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2, content: content)
            .padding(AlohaMetrics.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                palette.surfaceRaised,
                in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
            )
            .padding(.vertical, AlohaMetrics.space1)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(palette.background)
            .listRowSeparator(.hidden)
    }

    private func closeButton(label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(palette.secondaryLabel)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Loading

    private func load() async {
        // Announcements exist everywhere; the other two are Nextcloud's.
        async let announcementsTask = session.client.decode(
            LossyArray<ServerAnnouncement>.self, from: Endpoint.announcementsExtra.all)
        announcements = (try? await announcementsTask)?.elements ?? []

        guard session.capabilities.isNextcloudSocial else { return }
        async let memoriesTask = session.client.decode(
            LossyArray<Status>.self, from: Endpoint.memories.onThisDay)
        async let recapTask = session.client.decode(WeeklyRecap.self, from: Endpoint.memories.recap)
        memories = ((try? await memoriesTask)?.elements ?? []).sorted {
            $0.createdAt > $1.createdAt
        }
        recap = try? await recapTask
    }

    private func dismiss(_ announcement: ServerAnnouncement) async {
        guard let index = announcements.firstIndex(where: { $0.id == announcement.id }) else {
            return
        }
        withAnimation { announcements[index].read = true }
        _ = try? await session.client.send(Endpoint.announcementsExtra.dismiss(announcement.id))
    }

    private func toggle(
        _ reaction: ServerAnnouncement.Reaction, on announcement: ServerAnnouncement
    ) async {
        guard let index = announcements.firstIndex(where: { $0.id == announcement.id }) else {
            return
        }
        var reactions = announcements[index].reactions
        if let existing = reactions.firstIndex(where: { $0.name == reaction.name }) {
            reactions[existing].me = !reaction.me
            reactions[existing].count = max(0, reactions[existing].count + (reaction.me ? -1 : 1))
            if reactions[existing].count == 0 { reactions.remove(at: existing) }
        } else {
            reactions.append(ServerAnnouncement.Reaction(name: reaction.name, count: 1, me: true))
        }
        announcements[index].reactions = reactions
        _ = try? await session.client.send(
            reaction.me
                ? Endpoint.announcementsExtra.unreact(announcement.id, emoji: reaction.name)
                : Endpoint.announcementsExtra.react(announcement.id, emoji: reaction.name))
    }
}

/// Where "put this away for today / this week" is remembered. Device-local:
/// a dismissal is a reading habit, not account state.
enum HomeExtrasDismissals {
    private static let memoriesKey = "aloha.home.memoriesDismissedDay"
    private static let recapKey = "aloha.home.recapDismissedWeek"

    static var today: String {
        Date().formatted(.iso8601.year().month().day())
    }

    static var thisWeek: String {
        let components = Calendar.current.dateComponents(
            [.yearForWeekOfYear, .weekOfYear], from: Date())
        return "\(components.yearForWeekOfYear ?? 0)-W\(components.weekOfYear ?? 0)"
    }

    static var memoriesDay: String {
        get { UserDefaults.standard.string(forKey: memoriesKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: memoriesKey) }
    }

    static var recapWeek: String {
        get { UserDefaults.standard.string(forKey: recapKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: recapKey) }
    }
}
