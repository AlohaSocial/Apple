// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaStore
import CoreGraphics
import SwiftUI
import WidgetKit

/// One to four people: each one's latest post, with a ring when they have a
/// story you have not seen.
struct PeopleProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PeopleEntry {
        PeopleEntry(date: Date(), accountID: nil, people: [], serverTheme: nil)
    }

    func snapshot(
        for configuration: PeopleWidgetConfiguration, in context: Context
    ) async -> PeopleEntry {
        await entry(for: configuration)
    }

    func timeline(
        for configuration: PeopleWidgetConfiguration, in context: Context
    ) async -> Timeline<PeopleEntry> {
        Timeline(
            entries: [await entry(for: configuration)],
            policy: .after(Date().addingTimeInterval(900)))
    }

    @MainActor
    private func entry(for configuration: PeopleWidgetConfiguration) async -> PeopleEntry {
        guard let account = await WidgetData.account(id: configuration.account?.id) else {
            return placeholderEntry
        }
        let ids = configuration.personIDs(for: account.id)
        guard let loaded = await SnapshotData.load(accountID: account.id, people: ids) else {
            return placeholderEntry
        }
        let known = Dictionary(
            (loaded.snapshot?.people ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first })
        let picked = configuration.people ?? []
        let people = ids.map { id in
            let person = known[id]
            return PeopleEntry.Row(
                id: id,
                // The name picked in the settings until the app has fetched
                // the person.
                name: person?.name ?? picked.first { $0.personID == id }?.name ?? "",
                person: person,
                avatar: SnapshotData.image(person?.avatarFile, in: loaded.store, maxPixels: 132))
        }
        return PeopleEntry(
            date: Date(), accountID: account.id, people: people,
            serverTheme: loaded.serverTheme)
    }

    private var placeholderEntry: PeopleEntry {
        PeopleEntry(date: Date(), accountID: nil, people: [], serverTheme: nil)
    }
}

struct PeopleEntry: WidgetKit.TimelineEntry {
    struct Row: Identifiable {
        let id: String
        let name: String
        let person: WidgetSnapshot.Person?
        let avatar: CGImage?
    }

    let date: Date
    let accountID: UUID?
    let people: [Row]
    let serverTheme: AlohaThemeModifier.ServerTheme?

    func url(_ row: Row) -> URL? {
        accountID.flatMap { SnapshotData.profileURL(accountID: $0, personID: row.id) }
    }
}

struct PeopleWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "People", intent: PeopleWidgetConfiguration.self, provider: PeopleProvider()
        ) { entry in
            PeopleView(entry: entry)
                .serverTint(entry.serverTheme)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text("People", comment: "Widget name"))
        .description(
            Text(
                "The latest from up to four people you pick.", comment: "Widget description")
        )
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PeopleView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PeopleEntry

    var body: some View {
        if entry.people.isEmpty {
            SnapshotPlaceholder(
                symbol: "person.2",
                text: Text(
                    "Choose people in the widget's settings.",
                    comment: "People widget with nobody picked"))
        } else if family == .systemSmall, let first = entry.people.first {
            link(first) { single(first) }
        } else {
            HStack(alignment: .top, spacing: 8) {
                ForEach(entry.people.prefix(4)) { row in
                    link(row) { column(row) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private func link<Content: View>(
        _ row: PeopleEntry.Row, @ViewBuilder _ content: () -> Content
    )
        -> some View
    {
        if let url = entry.url(row) {
            Link(destination: url) { content() }
        } else {
            content()
        }
    }

    /// One person, filling the small widget.
    private func single(_ row: PeopleEntry.Row) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                avatar(row, size: 36)
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    if let date = row.person?.latestDate {
                        Text(date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            latest(row, lines: 4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// One of up to four, side by side.
    private func column(_ row: PeopleEntry.Row) -> some View {
        VStack(spacing: 4) {
            avatar(row, size: 44)
            Text(row.name)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            latest(row, lines: 3)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func latest(_ row: PeopleEntry.Row, lines: Int) -> some View {
        if let text = row.person?.latestText, !text.isEmpty {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(lines)
        } else if row.person == nil {
            SnapshotPlaceholder.openApp
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(lines)
        } else {
            Text("No posts yet", comment: "People widget, person without posts")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// The picture, ringed in the tint when there is a story not seen yet —
    /// the shape the app's own story row uses.
    private func avatar(_ row: PeopleEntry.Row, size: CGFloat) -> some View {
        let ringed = row.person?.hasNewStory == true
        return WidgetAvatar(image: row.avatar, name: row.name, size: size)
            .padding(ringed ? 3 : 0)
            .overlay {
                if ringed {
                    Circle()
                        .strokeBorder(.tint, lineWidth: 2)
                        .widgetAccentable()
                }
            }
            .accessibilityElement()
            .accessibilityLabel(
                ringed
                    ? Text("\(row.name), new story", comment: "People widget, VoiceOver")
                    : Text(row.name))
    }
}
