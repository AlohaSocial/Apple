// SPDX-License-Identifier: MIT

import AlohaHTML
import AlohaNetwork
import SwiftUI
import WidgetKit

/// The watch face's complications (docs/09 §4): the unread count and the
/// newest mentions of the account the phone paired.
@main
struct AlohaWatchWidgets: WidgetBundle {
    var body: some Widget {
        UnreadComplication()
        MentionsComplication()
    }
}

// MARK: - Timeline

struct ComplicationEntry: TimelineEntry {
    let date: Date
    /// `nil` when the watch is not paired yet.
    let snapshot: WatchComplicationSnapshot?
    let isPaired: Bool

    static let placeholder = ComplicationEntry(
        date: Date(),
        snapshot: WatchComplicationSnapshot(
            accountID: UUID(), unreadCount: 3,
            mentions: [
                .init(
                    id: "0", author: "Aloha", text: "Hello from the fediverse",
                    statusID: nil, createdAt: Date())
            ],
            updatedAt: Date()),
        isPaired: true)
}

/// Draws from the snapshot in the app group. When that is stale, and the
/// pairing's token is readable from the shared Keychain group, it asks the
/// server itself — the watch app may not run for hours, and the phone only
/// pushes the count.
struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task { completion(await Self.entry(refreshing: false)) }
    }

    func getTimeline(
        in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void
    ) {
        Task {
            let entry = await Self.entry(refreshing: true)
            completion(
                Timeline(
                    entries: [entry],
                    policy: .after(
                        Date().addingTimeInterval(WatchComplicationSnapshot.refreshInterval))))
        }
    }

    private static func entry(refreshing: Bool) async -> ComplicationEntry {
        guard let pairing = WatchPairingStore().load() else {
            return ComplicationEntry(date: Date(), snapshot: nil, isPaired: false)
        }
        let stored = WatchComplicationSnapshot.load(for: pairing.accountID)
        guard refreshing, stored?.isStale() ?? true else {
            return ComplicationEntry(date: Date(), snapshot: stored, isPaired: true)
        }
        let client = APIClient(
            accountID: pairing.accountID, apiBase: pairing.apiBase, accessToken: pairing.token)
        let parser = StatusHTMLParser()
        // A failed refresh keeps what the face already showed: an old count
        // is better than a blank, and the next timeline tries again.
        guard
            let fresh = try? await WatchComplicationRefresher.fetch(
                client: client, accountID: pairing.accountID,
                plainText: { parser.plainText($0) })
        else {
            return ComplicationEntry(date: Date(), snapshot: stored, isPaired: true)
        }
        fresh.save()
        return ComplicationEntry(date: Date(), snapshot: fresh, isPaired: true)
    }
}

// MARK: - Unread

struct UnreadComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchUnread", provider: ComplicationProvider()) { entry in
            UnreadComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(WatchComplicationLink.mentions.url)
        }
        .configurationDisplayName(Text("Unread", comment: "Watch complication name"))
        .description(
            Text("Notifications you haven't read yet.", comment: "Watch complication description")
        )
        .supportedFamilies([
            .accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular,
        ])
    }
}

struct UnreadComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    private var count: Int? { entry.snapshot?.unreadCount }

    /// A dash rather than a zero when nothing has been counted yet: a false
    /// "0" reads as "nothing new", which is a claim nobody made.
    private var countText: Text {
        if let count {
            Text(count, format: .number)
        } else {
            Text(verbatim: "–")
        }
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "bell.fill")
                    .font(.caption2)
                    .widgetAccentable()
                countText
                    .font(.title3.weight(.semibold))
                    .minimumScaleFactor(0.5)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        case .accessoryCorner:
            Image(systemName: "bell.fill")
                .font(.title3)
                .widgetAccentable()
                .widgetLabel { countText }
                .accessibilityLabel(accessibilityText)
        case .accessoryInline:
            if let count {
                Label {
                    Text("\(count) unread", comment: "Watch inline complication, unread count")
                } icon: {
                    Image(systemName: "bell.fill")
                }
            } else {
                Label {
                    Text("Aloha Social", comment: "Watch inline complication, nothing counted yet")
                } icon: {
                    Image(systemName: "bell")
                }
            }
        default:
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label {
                        Text("Notifications", comment: "Watch rectangular complication title")
                    } icon: {
                        Image(systemName: "bell.fill")
                    }
                    .font(.headline)
                    .widgetAccentable()
                    if entry.isPaired {
                        if let count {
                            Text(
                                "\(count) unread",
                                comment: "Watch inline complication, unread count")
                        } else {
                            Text("Not counted yet", comment: "Watch complication, no count yet")
                        }
                    } else {
                        Text(
                            "Open Aloha Social on your iPhone",
                            comment: "Watch complication, not paired")
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var accessibilityText: Text {
        if let count {
            Text(
                "^[\(count) unread notification](inflect: true)",
                comment: "Watch complication accessibility label")
        } else {
            Text("Notifications not counted yet", comment: "Watch complication accessibility label")
        }
    }
}

// MARK: - Mentions

struct MentionsComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchMentions", provider: ComplicationProvider()) { entry in
            MentionsComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                // The newest mention opens as itself; without one, the list.
                .widgetURL(
                    (entry.snapshot?.mentions.first?.statusID).map {
                        WatchComplicationLink.status($0).url
                    } ?? WatchComplicationLink.mentions.url)
        }
        .configurationDisplayName(Text("Mentions", comment: "Watch complication name"))
        .description(
            Text("The newest thing said to you.", comment: "Watch complication description")
        )
        .supportedFamilies([.accessoryRectangular])
    }
}

struct MentionsComplicationView: View {
    let entry: ComplicationEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let mention = entry.snapshot?.mentions.first {
                HStack(spacing: 4) {
                    Image(systemName: "at")
                        .widgetAccentable()
                    Text(mention.author)
                        .font(.headline)
                        .lineLimit(1)
                }
                Text(mention.text)
                    .font(.caption2)
                    .lineLimit(2)
                    .privacySensitive()
            } else {
                Label {
                    Text("Mentions", comment: "Watch complication name")
                } icon: {
                    Image(systemName: "at")
                }
                .font(.headline)
                .widgetAccentable()
                if entry.isPaired {
                    Text("Nothing said lately", comment: "Watch mentions complication, empty")
                        .font(.caption2)
                } else {
                    Text(
                        "Open Aloha Social on your iPhone",
                        comment: "Watch complication, not paired"
                    )
                    .font(.caption2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
