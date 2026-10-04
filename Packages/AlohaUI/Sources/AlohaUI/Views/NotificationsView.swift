// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import AlohaNetwork
import SwiftUI

public struct NotificationsView: View {
    @Environment(\.alohaPalette) private var palette
    @Namespace private var chipIndicator

    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var groups: [NotificationGroup] = []
    @State private var flat: [MastodonNotification] = []
    @State private var accounts: [String: Account] = [:]
    @State private var statuses: [String: Status] = [:]
    @State private var selectedKinds: Set<NotificationKind> = []
    /// Begins in the loading state, so the first paint cannot flash "Nothing
    /// yet" before the request that would say otherwise has been sent.
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadID = UUID()

    public init(session: AccountSession, onAction: @escaping (StatusRowAction) -> Void) {
        self.session = session
        self.onAction = onAction
    }

    public var body: some View {
        List {
            if let errorMessage {
                errorStrip(errorMessage)
            }

            if session.capabilities.groupedNotifications {
                ForEach(visibleGroups) { group in
                    groupRow(group)
                        .listRowBackground(palette.background)
                }
            } else {
                ForEach(visibleFlat) { notification in
                    flatRow(notification)
                        .listRowBackground(palette.background)
                }
            }

            if !isLoading && errorMessage == nil && groups.isEmpty && flat.isEmpty {
                emptyState
            } else if !isLoading && errorMessage == nil && visibleGroups.isEmpty && visibleFlat.isEmpty {
                ContentUnavailableView {
                    Text("No matching activities")
                } description: {
                    Text("Choose another filter to see more activities.")
                } actions: {
                    Button("Show all") { selectedKinds = [] }
                        .buttonStyle(.glass)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(palette.background)
            }
        }
        .listStyle(.plain)
        .alohaGround(palette)
        .safeAreaInset(edge: .top, spacing: 0) {
            filterChips
                .padding(.horizontal, AlohaMetrics.space3)
                .padding(.vertical, AlohaMetrics.space2)
                .background(palette.background)
        }
        .overlay {
            if isLoading && groups.isEmpty && flat.isEmpty { ProgressView() }
        }
        .navigationTitle(Text("Activities", comment: "Screen title"))
        .refreshable { await load() }
        .task { await load() }
    }

    private var visibleGroups: [NotificationGroup] {
        groups.filter { Self.matches($0.type, selected: selectedKinds) }
    }

    private var visibleFlat: [MastodonNotification] {
        flat.filter { Self.matches($0.type, selected: selectedKinds) }
    }

    nonisolated static func matches(_ kind: NotificationKind, selected: Set<NotificationKind>) -> Bool {
        selected.isEmpty || selected.contains(kind)
            || (kind == .followRequest && selected.contains(.follow))
    }

    private var filterChips: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: AlohaMetrics.space2) {
                HStack(spacing: AlohaMetrics.space2) {
                    chip(nil, label: String(localized: "All", comment: "Notification filter"))
                    chip(
                        .mention,
                        label: String(localized: "Mentions", comment: "Notification filter"))
                    chip(
                        .reblog,
                        label: String(localized: "Boosts", comment: "Notification filter"))
                    chip(
                        .favourite,
                        label: String(localized: "Favourites", comment: "Notification filter"))
                    chip(
                        .follow,
                        label: String(localized: "Follows", comment: "Notification filter"))
                    chip(.poll, label: String(localized: "Polls", comment: "Notification filter"))
                }
                .padding(.vertical, AlohaMetrics.space1)
            }
        }
        .scrollIndicators(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        // Chrome, not content: the strip is pinned under the title, and the
        // hairline the plain list draws under it read as a divider between
        // the chips and the row they belong to.
        .listRowBackground(palette.background)
        .listRowSeparator(.hidden)
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
                .foregroundStyle(isSelected ? palette.onAccent : palette.label)
                .padding(.horizontal, AlohaMetrics.space3)
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular.tint(isSelected ? palette.accent : nil).interactive(),
            in: Capsule())
        .glassEffectID(label, in: chipIndicator)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func errorStrip(_ message: String) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: AlohaSymbol.warning)
            Text(message).font(.caption)
            Spacer()
            Button {
                Task { await load() }
            } label: {
                Text("Retry", comment: "Error strip action")
            }
            .font(.caption.weight(.semibold))
        }
        .foregroundStyle(palette.destructive)
        .padding(.vertical, AlohaMetrics.space2)
        .listRowBackground(palette.background)
        .listRowSeparator(.hidden)
    }

    /// A group renders as one row: "Alice, Bob and 34 others favourited your
    /// post", with a stacked avatar row.
    private func groupRow(_ group: NotificationGroup) -> some View {
        let sample = group.sampleAccountIDs.compactMap { accounts[$0] }
        let status = group.statusID.flatMap { statuses[$0] }

        return Button {
            if let status {
                onAction(.open(status))
            } else if let account = sample.first {
                onAction(.openProfile(account))
            }
        } label: {
            VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                HStack(spacing: AlohaMetrics.space2) {
                    Image(systemName: symbol(for: group.type))
                        .foregroundStyle(tint(for: group.type))
                        .font(.footnote)
                        .accessibilityHidden(true)

                    HStack(spacing: -8) {
                        ForEach(sample.prefix(4), id: \.id) { account in
                            AvatarView(account: account, size: 26)
                                .overlay(
                                    Circle().strokeBorder(palette.background, lineWidth: 1.5))
                        }
                    }

                    Text(summary(for: group, sample: sample))
                        .font(.subheadline)
                        .lineLimit(3)
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
                if let date = group.latestPageNotificationAt {
                    activityDate(date)
                }
            }
            .padding(.vertical, AlohaMetrics.space2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func flatRow(_ notification: MastodonNotification) -> some View {
        Button {
            if let status = notification.status {
                onAction(.open(status))
            } else {
                onAction(.openProfile(notification.account))
            }
        } label: {
            HStack(alignment: .top, spacing: AlohaMetrics.space3) {
                Image(systemName: symbol(for: notification.type))
                    .foregroundStyle(tint(for: notification.type))
                    .font(.footnote)
                    .frame(width: 20)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
                    HStack(spacing: AlohaMetrics.space2) {
                        AvatarView(account: notification.account, size: 26)
                        Text(summary(for: notification))
                            .font(.subheadline)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let status = notification.status {
                        Text(plainPreview(status))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryLabel)
                            .lineLimit(2)
                    }
                    activityDate(notification.createdAt)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, AlohaMetrics.space2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        EmptyStateView(
            symbol: AlohaSymbol.notifications,
            title: Text("Nothing yet", comment: "Empty notifications"),
            message: Text(
                "Replies, boosts and favourites land here.",
                comment: "Empty notifications detail")
        )
        .listRowBackground(palette.background)
        .listRowSeparator(.hidden)
    }

    private func activityDate(_ date: Date) -> some View {
        Text(date, style: .relative)
            .font(.caption)
            .foregroundStyle(palette.tertiaryLabel)
            .accessibilityLabel(Text(date, format: .dateTime.day().month().year().hour().minute()))
    }

    // MARK: - Loading

    private func load() async {
        let requestID = UUID()
        loadID = requestID
        isLoading = true
        defer { if loadID == requestID { isLoading = false } }

        do {
            if session.capabilities.groupedNotifications {
                let results = try await session.client.decode(
                    GroupedNotificationsResults.self, from: Endpoint.notifications.grouped())
                guard !Task.isCancelled, loadID == requestID else { return }
                groups = results.notificationGroups
                accounts = Dictionary(
                    results.accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                statuses = Dictionary(
                    results.statuses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            } else {
                let page = try await session.client.decode(
                    LossyArray<MastodonNotification>.self, from: Endpoint.notifications.flat())
                guard !Task.isCancelled, loadID == requestID else { return }
                flat = page.elements
            }
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, loadID == requestID else { return }
            await session.handle(error)
            guard loadID == requestID else { return }
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
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
