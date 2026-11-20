// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaStore
import AppIntents
import SwiftUI
import WidgetKit

/// Direct messages, one widget at every size: how many are unread on the
/// Lock Screen and in the small square, and the newest conversations — who,
/// the last line, unread or not — where there is room for rows.
///
/// It was two widgets, a count and a list, that read the same snapshot and
/// opened the same screen; the family already says which one is wanted. The
/// kind is the count's, so a Lock Screen that had it keeps it.
struct DirectMessagesWidget: Widget {
    static let kind = "DirectMessages"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind, intent: NotificationsWidgetAccount.self,
            provider: SnapshotProvider()
        ) { entry in
            DirectMessagesView(entry: entry)
                .serverTint(entry.serverTheme)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(entry.url("conversations"))
        }
        .configurationDisplayName(Text("Direct messages", comment: "Widget name"))
        .description(Text("Unread messages, and who sent them.", comment: "Widget description"))
        .supportedFamilies(
            [.systemSmall, .systemMedium, .systemLarge] + SnapshotData.lockScreenCountFamilies)
    }
}

struct DirectMessagesView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        switch family {
        case .systemMedium, .systemLarge:
            ConversationsView(entry: entry)
        default:
            UnreadMessagesView(entry: entry)
        }
    }
}

/// The count: the Lock Screen's three shapes and the small square. Names
/// hide while the phone is locked.
struct UnreadMessagesView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var unread: Int { entry.snapshot?.messages?.unread ?? 0 }

    /// The senders of the unread conversations, newest first.
    private var senders: [String] {
        (entry.snapshot?.messages?.conversations ?? []).filter(\.unread).map(\.names)
    }

    var body: some View {
        switch family {
        #if os(iOS)
            case .accessoryInline:
                Label {
                    Text("^[\(unread) unread message](inflect: true)", comment: "Widget text")
                } icon: {
                    Image(systemName: AlohaSymbol.directMessageFilled)
                }
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: AlohaSymbol.directMessageFilled)
                            .font(.caption)
                            .widgetAccentable()
                        Text(unread, format: .number)
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .contentTransition(.numericText())
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    Text("^[\(unread) unread message](inflect: true)", comment: "Widget text"))
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 0) {
                    Label {
                        Text("Messages", comment: "Lock Screen widget heading")
                    } icon: {
                        Image(systemName: AlohaSymbol.directMessageFilled)
                    }
                    .font(.headline)
                    .widgetAccentable()
                    Text("\(unread) unread", comment: "Lock Screen widget count")
                        .font(.body.monospacedDigit())
                    if !senders.isEmpty {
                        Text(senders.prefix(2).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .privacySensitive()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        #endif
        default:
            if entry.snapshot?.messages == nil {
                SnapshotPlaceholder(
                    symbol: AlohaSymbol.directMessage, text: SnapshotPlaceholder.openApp)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Image(systemName: AlohaSymbol.directMessageFilled)
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .widgetAccentable()
                    Text(unread, format: .number)
                        .font(.largeTitle.weight(.bold))
                        .contentTransition(.numericText())
                    Text("unread messages", comment: "Widget label")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let first = senders.first {
                        Text(first)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .privacySensitive()
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The newest direct-message threads as rows. A row opens its thread; the
/// rest of the widget opens the list.
struct ConversationsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var visibleCount: Int { family == .systemLarge ? 6 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeading(
                symbol: AlohaSymbol.directMessageFilled,
                title: Text("Messages", comment: "Widget heading"),
                trailing: unreadLabel)
            if let messages = entry.snapshot?.messages {
                if messages.conversations.isEmpty {
                    Text("No messages yet", comment: "Empty conversations widget")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(messages.conversations.prefix(visibleCount)) { row in
                        if let url = entry.statusURL(row.lastStatusID) {
                            Link(destination: url) { conversationRow(row) }
                        } else {
                            conversationRow(row)
                        }
                    }
                }
            } else {
                SnapshotPlaceholder.openApp
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var unreadLabel: Text? {
        guard let unread = entry.snapshot?.messages?.unread, unread > 0 else { return nil }
        return Text("\(unread) unread", comment: "Lock Screen widget count")
    }

    private func conversationRow(_ row: WidgetSnapshot.ConversationRow) -> some View {
        HStack(alignment: .top, spacing: 6) {
            WidgetAvatar(image: entry.image(row.avatarFile), name: row.names, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(row.names)
                        .font(.caption.weight(row.unread ? .bold : .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(row.date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if row.unread {
                        Circle()
                            .fill(.tint)
                            .frame(width: 7, height: 7)
                            .widgetAccentable()
                            .accessibilityLabel(Text("Unread", comment: "Widget row state"))
                    }
                }
                Text(row.text)
                    .font(.caption2)
                    .foregroundStyle(row.unread ? .primary : .secondary)
                    .lineLimit(1)
                    .privacySensitive()
            }
        }
    }
}
