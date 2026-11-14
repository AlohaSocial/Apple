// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import AlohaStore
import AlohaUI
import SwiftData
import SwiftUI

/// The menu bar extra: the unread count in the menu bar, and a small panel
/// with the newest notifications and New Post (docs/09 §2).
///
/// Optional and off by default, as docs/09 has it: a menu bar is shared
/// with every other app, and a place in it is the person's to give. The
/// switch is in the Mac's Settings window (`MacMenuBarSettings`).
enum MacMenuBarExtra {
    static let isShownKey = "aloha.mac.menuBarExtra"
}

/// What the menu bar shows: the app's mark, and the count beside it once
/// there is anything unread. The count is the one the Dock badge shows —
/// the sync engine's total, which it writes to the app group.
struct MacMenuBarLabel: View {
    let unread: Int

    var body: some View {
        if unread > 0 {
            Label {
                Text(unread, format: .number)
            } icon: {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
            }
            .labelStyle(.titleAndIcon)
            .accessibilityLabel(
                Text("Aloha Social, \(unread) unread", comment: "Menu bar extra with unread count"))
        } else {
            Label {
                Text("Aloha Social", comment: "App name")
            } icon: {
                Image(systemName: "bubble.left.and.text.bubble.right")
            }
            .labelStyle(.iconOnly)
        }
    }
}

/// The panel the menu bar extra opens.
struct MacMenuBarPanel: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            HStack {
                Text("Activities", comment: "Menu bar panel title")
                    .font(.headline)
                Spacer()
                Button {
                    MacWindows.compose()
                } label: {
                    Label {
                        Text("New Post", comment: "Menu item")
                    } icon: {
                        Image(systemName: "square.and.pencil")
                    }
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
            }

            Divider()

            if let session = environment.activeSession {
                MacRecentNotifications(accountID: session.id)
            } else {
                Text("Sign in to see your activities.", comment: "Menu bar panel, signed out")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // The sidebar's order and names (`ShellPlace.sidebarOrder`).
            HStack {
                Button {
                    MacWindows.open(.notifications)
                } label: {
                    Text("All Activities", comment: "Menu bar panel action")
                }
                Button {
                    MacWindows.open(.conversations)
                } label: {
                    Text("Direct messages", comment: "Menu item")
                }
                Button {
                    MacWindows.open(.explore)
                } label: {
                    Text("Discover", comment: "Menu item")
                }
            }
            .buttonStyle(.link)
            .font(.callout)
        }
        .padding(AlohaMetrics.space3)
        .frame(width: 340)
        .alohaTheme(
            environment.theme, metrics: environment.metrics, accent: environment.serverAccent
        )
        .providesWindowOpener()
    }
}

/// The newest few notifications the sync engine has stored for the active
/// account — read from the cache, never fetched for the panel, so opening it
/// costs nothing and works offline.
private struct MacRecentNotifications: View {
    @Query private var records: [NotificationRecord]

    init(accountID: UUID) {
        var descriptor = FetchDescriptor<NotificationRecord>(
            predicate: #Predicate { $0.accountID == accountID && !$0.dismissed },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 6
        _records = Query(descriptor)
    }

    var body: some View {
        if records.isEmpty {
            Text("Nothing new.", comment: "Menu bar panel, no notifications")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
                ForEach(records) { record in
                    MacNotificationRow(record: record)
                }
            }
        }
    }
}

private struct MacNotificationRow: View {
    let record: NotificationRecord

    var body: some View {
        let payload = NotificationPayload.decode(record.payload)
        Button {
            // A notification about a post opens the post; the rest open the
            // whole list, where a follow or a poll result is read.
            if let statusID = record.statusServerID ?? payload?.statusID {
                MacWindows.open(.thread(statusID: statusID))
            } else {
                MacWindows.open(.notifications)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(
                        verbatim: Self.summary(kind: record.kind, payload: payload, record: record)
                    )
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(record.createdAt, format: .relative(presentation: .numeric))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let body = payload?.body, !body.isEmpty {
                    // The payload already holds the content warning in place
                    // of the post, where there is one.
                    Text(verbatim: body)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    /// The sentence a notification banner uses, shortened to the kinds that
    /// reach a menu bar.
    static func summary(
        kind: NotificationKind, payload: NotificationPayload?, record: NotificationRecord
    ) -> String {
        let name =
            payload?.title.isEmpty == false
            ? payload?.title ?? ""
            : String(localized: "Someone", comment: "Unknown account")
        let others = max(0, record.groupCount - 1)
        let who =
            others == 0
            ? name
            : String(localized: "\(name) and \(others) others", comment: "Grouped notification")
        switch kind {
        case .mention:
            return String(localized: "\(who) mentioned you", comment: "Notification title")
        case .favourite:
            return String(localized: "\(who) favourited your post", comment: "Notification title")
        case .reblog:
            return String(localized: "\(who) boosted your post", comment: "Notification title")
        case .follow:
            return String(localized: "\(who) followed you", comment: "Notification title")
        case .followRequest:
            return String(localized: "\(who) asked to follow you", comment: "Notification title")
        case .poll:
            return String(localized: "A poll has ended", comment: "Notification title")
        case .update:
            return String(localized: "\(who) edited a post", comment: "Notification title")
        case .status:
            return String(localized: "\(who) posted", comment: "Notification title")
        default:
            return who
        }
    }
}

/// The Mac-only settings, as their own tab in the Settings window beside the
/// app's shared settings form.
struct MacMenuBarSettings: View {
    @AppStorage(MacMenuBarExtra.isShownKey) private var isShown = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $isShown) {
                    Text("Show in menu bar", comment: "Mac setting")
                    Text(
                        "The unread count, your newest activities and New Post, from anywhere.",
                        comment: "Mac setting detail")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
