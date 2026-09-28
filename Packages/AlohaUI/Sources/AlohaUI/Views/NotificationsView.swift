// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import AlohaNetwork
import SwiftUI

public struct NotificationsView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var groups: [NotificationGroup] = []
    @State private var flat: [MastodonNotification] = []
    @State private var accounts: [String: Account] = [:]
    @State private var statuses: [String: Status] = [:]
    @State private var selectedKinds: Set<NotificationKind> = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    public init(session: AccountSession, onAction: @escaping (StatusRowAction) -> Void) {
        self.session = session
        self.onAction = onAction
    }

    public var body: some View {
        List {
            filterChips

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(palette.destructive)
            }

            if session.capabilities.groupedNotifications {
                ForEach(visibleGroups) { group in
                    groupRow(group)
                }
            } else {
                ForEach(visibleFlat) { notification in
                    flatRow(notification)
                }
            }

            if !isLoading && groups.isEmpty && flat.isEmpty {
                emptyState
            }
        }
        .listStyle(.plain)
        .navigationTitle(Text("Activities", comment: "Screen title"))
        .refreshable { await load() }
        .task { await load() }
    }

    private var visibleGroups: [NotificationGroup] {
        selectedKinds.isEmpty ? groups : groups.filter { selectedKinds.contains($0.type) }
    }

    private var visibleFlat: [MastodonNotification] {
        selectedKinds.isEmpty ? flat : flat.filter { selectedKinds.contains($0.type) }
    }

    private var filterChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AlohaMetrics.space2) {
                chip(nil, label: String(localized: "All", comment: "Notification filter"))
                chip(.mention, label: String(localized: "Mentions", comment: "Notification filter"))
                chip(.reblog, label: String(localized: "Boosts", comment: "Notification filter"))
                chip(
                    .favourite,
                    label: String(localized: "Favourites", comment: "Notification filter"))
                chip(.follow, label: String(localized: "Follows", comment: "Notification filter"))
                chip(.poll, label: String(localized: "Polls", comment: "Notification filter"))
            }
            .padding(.vertical, AlohaMetrics.space1)
        }
        .scrollIndicators(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    private func chip(_ kind: NotificationKind?, label: String) -> some View {
        let isSelected = kind.map { selectedKinds.contains($0) } ?? selectedKinds.isEmpty
        return Button {
            guard let kind else {
                selectedKinds = []
                return
            }
            if selectedKinds.contains(kind) {
                selectedKinds.remove(kind)
            } else {
                selectedKinds.insert(kind)
            }
        } label: {
            Text(label)
                .font(.footnote.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, AlohaMetrics.space3)
                .padding(.vertical, AlohaMetrics.space1)
                .background(
                    isSelected ? palette.accentMuted.opacity(0.35) : palette.surfaceRaised,
                    in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// A group renders as one row: "Alice, Bob and 34 others favourited your
    /// post", with a stacked avatar row.
    private func groupRow(_ group: NotificationGroup) -> some View {
        let sample = group.sampleAccountIDs.compactMap { accounts[$0] }
        let status = group.statusID.flatMap { statuses[$0] }

        return VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            HStack(spacing: AlohaMetrics.space2) {
                Image(systemName: symbol(for: group.type))
                    .foregroundStyle(tint(for: group.type))
                    .font(.footnote)

                HStack(spacing: -8) {
                    ForEach(sample.prefix(4), id: \.id) { account in
                        AvatarView(account: account, size: 26)
                    }
                }

                Text(summary(for: group, sample: sample))
                    .font(.footnote)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }

            if let status {
                Text(
                    status.displayed.spoilerText.isEmpty
                        ? plainPreview(status) : status.displayed.spoilerText
                )
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
                .lineLimit(2)
            }
        }
        .padding(.vertical, AlohaMetrics.space2)
        .contentShape(Rectangle())
        .onTapGesture {
            if let status {
                onAction(.open(status))
            } else if let account = sample.first {
                onAction(.openProfile(account))
            }
        }
    }

    private func flatRow(_ notification: MastodonNotification) -> some View {
        HStack(alignment: .top, spacing: AlohaMetrics.space3) {
            Image(systemName: symbol(for: notification.type))
                .foregroundStyle(tint(for: notification.type))
                .font(.footnote)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
                HStack(spacing: AlohaMetrics.space2) {
                    AvatarView(account: notification.account, size: 26)
                    Text(summary(for: notification))
                        .font(.footnote)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let status = notification.status {
                    Text(plainPreview(status))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, AlohaMetrics.space2)
        .contentShape(Rectangle())
        .onTapGesture {
            if let status = notification.status {
                onAction(.open(status))
            } else {
                onAction(.openProfile(notification.account))
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            symbol: AlohaSymbol.notifications,
            title: Text("Nothing yet", comment: "Empty notifications"),
            message: Text(
                "Replies, boosts and favourites land here.",
                comment: "Empty notifications detail")
        )
        .listRowSeparator(.hidden)
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if session.capabilities.groupedNotifications {
                let results = try await session.client.decode(
                    GroupedNotificationsResults.self, from: Endpoint.notifications.grouped())
                groups = results.notificationGroups
                accounts = Dictionary(
                    results.accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                statuses = Dictionary(
                    results.statuses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            } else {
                let page = try await session.client.decode(
                    LossyArray<MastodonNotification>.self, from: Endpoint.notifications.flat())
                flat = page.elements
            }
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    // MARK: - Presentation

    private func symbol(for kind: NotificationKind) -> String {
        switch kind {
        case .mention: AlohaSymbol.reply
        case .reblog: AlohaSymbol.boost
        case .favourite: AlohaSymbol.favouriteFilled
        case .follow, .followRequest: "person.badge.plus"
        case .poll: AlohaSymbol.poll
        case .status: AlohaSymbol.notificationsFilled
        case .update: AlohaSymbol.edit
        case .moderationWarning, .severedRelationships: AlohaSymbol.warning
        default: AlohaSymbol.notifications
        }
    }

    private func tint(for kind: NotificationKind) -> Color {
        switch kind {
        case .reblog: palette.boost
        case .favourite: palette.favourite
        case .moderationWarning, .severedRelationships: palette.destructive
        default: palette.secondaryLabel
        }
    }

    private func summary(for group: NotificationGroup, sample: [Account]) -> String {
        let name =
            sample.first?.bestDisplayName
            ?? String(
                localized: "Someone", comment: "Unknown account in a notification")
        let others = max(0, group.notificationsCount - 1)

        let who: String
        switch others {
        case 0: who = name
        case 1:
            who = String(
                localized: "\(name) and 1 other", comment: "Grouped notification participants")
        default:
            who = String(
                localized: "\(name) and \(others) others",
                comment: "Grouped notification participants")
        }

        switch group.type {
        case .favourite:
            return String(localized: "\(who) favourited your post", comment: "Notification summary")
        case .reblog:
            return String(localized: "\(who) boosted your post", comment: "Notification summary")
        case .follow:
            return String(localized: "\(who) followed you", comment: "Notification summary")
        case .mention:
            return String(localized: "\(who) mentioned you", comment: "Notification summary")
        case .poll:
            return String(localized: "A poll has ended", comment: "Notification summary")
        case .update:
            return String(localized: "\(who) edited a post", comment: "Notification summary")
        case .status:
            return String(localized: "\(who) posted", comment: "Notification summary")
        default:
            return who
        }
    }

    private func summary(for notification: MastodonNotification) -> String {
        summary(
            for: NotificationGroup(
                groupKey: notification.id, notificationsCount: 1, type: notification.type,
                mostRecentNotificationID: notification.id),
            sample: [notification.account])
    }

    private func plainPreview(_ status: Status) -> String {
        StatusHTMLParser().plainText(status.displayed.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
