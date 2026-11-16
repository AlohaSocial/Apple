// SPDX-License-Identifier: MIT

import AlohaNetwork
import SwiftUI
import WidgetKit

/// Unread direct messages on the watch face: the paper plane the phone uses
/// for messages (`AlohaSymbol.directMessage`; this extension does not link
/// AlohaDesign, so the name is written out) and how many conversations have
/// something unread.
///
/// The count is the phone's, pushed with the unread notifications
/// (`WatchBridge`), and the complication's own refresh asks the server when
/// the snapshot is stale — the same snapshot and timeline as the others.
struct DirectMessagesComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchDirectMessages", provider: ComplicationProvider()) {
            entry in
            DirectMessagesComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                // The messages themselves, now that the watch has a list of
                // them to open.
                .widgetURL(WatchComplicationLink.messages.url)
        }
        .configurationDisplayName(
            Text("Direct messages", comment: "Watch complication name")
        )
        .description(
            Text(
                "Conversations with messages you haven't read.",
                comment: "Watch complication description")
        )
        .supportedFamilies([
            .accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular,
        ])
    }
}

struct DirectMessagesComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    /// `paperplane.fill`, as `AlohaSymbol.directMessageFilled`.
    static let symbol = "paperplane.fill"

    private var count: Int? { entry.snapshot?.unreadConversations }

    /// A dash rather than a zero until a count has arrived, as the unread
    /// complication does: a false "0" says nobody wrote, which nobody said.
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
                Image(systemName: Self.symbol)
                    .font(.caption2)
                    .widgetAccentable()
                countText
                    .font(.title3.weight(.semibold))
                    .minimumScaleFactor(0.5)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        case .accessoryCorner:
            Image(systemName: Self.symbol)
                .font(.title3)
                .widgetAccentable()
                .widgetLabel { countText }
                .accessibilityLabel(accessibilityText)
        case .accessoryInline:
            Label {
                if let count {
                    Text(
                        "^[\(count) unread message](inflect: true)",
                        comment: "Watch inline complication, unread direct message conversations")
                } else {
                    Text("Messages", comment: "Watch inline complication, nothing counted yet")
                }
            } icon: {
                Image(systemName: Self.symbol)
            }
        default:
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label {
                        Text("Direct messages", comment: "Watch complication name")
                    } icon: {
                        Image(systemName: Self.symbol)
                    }
                    .font(.headline)
                    .widgetAccentable()
                    if entry.isPaired {
                        if let count {
                            Text(
                                "^[\(count) unread conversation](inflect: true)",
                                comment: "Watch complication, unread direct message conversations")
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
            .accessibilityElement(children: .combine)
        }
    }

    private var accessibilityText: Text {
        if let count {
            Text(
                "^[\(count) unread conversation](inflect: true)",
                comment: "Watch complication accessibility label, direct messages")
        } else {
            Text(
                "Direct messages not counted yet",
                comment: "Watch complication accessibility label, direct messages")
        }
    }
}
