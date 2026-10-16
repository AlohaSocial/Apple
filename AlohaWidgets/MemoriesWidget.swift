// SPDX-License-Identifier: MIT

import AlohaStore
import CoreGraphics
import ImageIO
import SwiftUI
import WidgetKit

/// "On this day": what you posted on this date in earlier years.
///
/// Built from the snapshot the app writes into the app group
/// (`MemoriesWidgetWriter`) — a widget never downloads (docs/09 §8).
struct MemoriesProvider: TimelineProvider {
    func placeholder(in context: Context) -> MemoriesEntry {
        MemoriesEntry(date: Date(), accountID: nil, memories: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (MemoriesEntry) -> Void) {
        completion(Self.entry())
    }

    /// Reloaded by the app whenever it writes a new day; the policy only has
    /// to turn yesterday's memories over at midnight, when they stop being
    /// today's.
    func getTimeline(in context: Context, completion: @escaping (Timeline<MemoriesEntry>) -> Void) {
        let midnight =
            Calendar.current.nextDate(
                after: Date(), matching: DateComponents(hour: 0, minute: 0),
                matchingPolicy: .nextTime)
            ?? Date().addingTimeInterval(3600 * 6)
        completion(Timeline(entries: [Self.entry()], policy: .after(midnight)))
    }

    private static func entry() -> MemoriesEntry {
        guard let found = WidgetData.memories() else {
            return MemoriesEntry(date: Date(), accountID: nil, memories: [])
        }
        let (snapshot, store) = found
        return MemoriesEntry(
            date: Date(), accountID: snapshot.accountID,
            memories: snapshot.memories.map { memory in
                MemoriesEntry.Row(
                    memory: memory, image: store.imageURL(for: memory).flatMap(image(at:)))
            })
    }

    /// The pictures are small JPEGs the app already shrank; decoding them
    /// here keeps the view free of file access.
    private static func image(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

struct MemoriesEntry: WidgetKit.TimelineEntry {
    struct Row: Identifiable {
        let memory: MemoriesSnapshot.Memory
        let image: CGImage?
        var id: String { memory.id }
    }

    let date: Date
    let accountID: UUID?
    let memories: [Row]
}

struct MemoriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MemoriesSnapshotStore.widgetKind, provider: MemoriesProvider()) {
            entry in
            MemoriesView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "alohasocial://memories"))
        }
        .configurationDisplayName(Text("On this day", comment: "Widget name"))
        .description(
            Text("What you posted on this day in earlier years.", comment: "Widget description")
        )
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct MemoriesView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MemoriesEntry

    private var visibleCount: Int {
        switch family {
        case .systemSmall: 1
        case .systemMedium: 2
        default: 4
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("On this day", comment: "Memories widget heading")
            } icon: {
                Image(systemName: "calendar.badge.clock")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
            .widgetAccentable()

            if entry.memories.isEmpty {
                Text("Nothing from this day yet.", comment: "Empty memories widget")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if family == .systemSmall, let first = entry.memories.first {
                smallMemory(first)
            } else {
                ForEach(entry.memories.prefix(visibleCount)) { row in
                    link(for: row) { memoryRow(row) }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func link<Content: View>(
        for row: MemoriesEntry.Row, @ViewBuilder _ content: () -> Content
    )
        -> some View
    {
        if let accountID = entry.accountID,
            let url = WidgetData.statusURL(accountID: accountID, statusID: row.memory.id)
        {
            Link(destination: url) { content() }
        } else {
            content()
        }
    }

    /// One memory, filling the small widget: its picture when it has one.
    private func smallMemory(_ row: MemoriesEntry.Row) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let image = row.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Text(row.memory.text)
                    .font(.caption)
                    .lineLimit(4)
            }
            yearsAgo(row.memory)
        }
    }

    private func memoryRow(_ row: MemoriesEntry.Row) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let image = row.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                yearsAgo(row.memory)
                Text(row.memory.text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "2 years ago" in the reader's language, from the system's own
    /// relative formatter rather than a string of ours.
    private func yearsAgo(_ memory: MemoriesSnapshot.Memory) -> some View {
        Text(memory.createdAt, format: .relative(presentation: .named, unitsStyle: .wide))
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
    }
}
