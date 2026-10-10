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
    /// Notification policy (when the server supports it) — carries the count
    /// of filtered requests so we can show it at the top.
    @State private var notificationPolicy: NotificationPolicy?
    /// The "caught up" marker for the notifications timeline — the last
    /// notification ID the user had read. When present in the flat list, a
    /// divider is inserted below it.
    @State private var caughtUpNotificationID: String?

    public init(session: AccountSession, onAction: @escaping (StatusRowAction) -> Void) {
        self.session = session
        self.onAction = onAction
    }

    public var body: some View {
        List {
            if let errorMessage {
                errorStrip(errorMessage)
            }

            // The notification policy header: a link to the policy screen and,
            // when there are filtered requests, their count.
            if session.capabilities.notificationPolicy {
                Section {
                    NavigationLink(value: Route.notificationPolicy) {
                        Label {
                            Text("Notification policy", comment: "Notifications header")
                        } icon: {
                            Image(systemName: "lock.shield")
                        }
                    }
                    if let summary = notificationPolicy?.summary,
                        summary.pendingRequestsCount > 0
                    {
                        NavigationLink(value: Route.notificationRequests) {
                            HStack {
                                Image(systemName: AlohaSymbol.filter)
                                Text("Filtered notifications")
                                Spacer()
                                Text("\(summary.pendingRequestsCount)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(palette.accent)
                            }
                        }
                    }
                }
            }

            if session.capabilities.groupedNotifications {
                groupedRowsWithMarker
            } else {
                flatRowsWithMarker
            }

            if !isLoading && errorMessage == nil && groups.isEmpty && flat.isEmpty {
                emptyState
            } else if !isLoading && errorMessage == nil && visibleGroups.isEmpty
                && visibleFlat.isEmpty
            {
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
            if isLoading && groups.isEmpty && flat.isEmpty {
                SkeletonListRow(person: 4)
            }
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

    /// The flat list with an optional "caught up" divider inserted at the
    /// marker position. When the marker notification is in the visible list,
    /// a divider is inserted below it; the marker advances when the next
    /// notification appears (handled in `flatRow`).
    private var flatRowsWithMarker: some View {
        let notifications = visibleFlat
        guard let markerID = caughtUpNotificationID,
            let markerIdx = notifications.firstIndex(where: { $0.id == markerID })
        else {
            return AnyView(
                ForEach(notifications) { notification in
                    flatRow(notification)
                        .listRowBackground(palette.background)
                })
        }
        // Insert divider after the marker
        var rows: [AnyView] = []
        for (idx, notification) in notifications.enumerated() {
            rows.append(
                AnyView(
                    flatRow(notification)
                        .listRowBackground(palette.background)
                ))
            if idx == markerIdx {
                rows.append(
                    AnyView(
                        caughtUpDivider(after: markerID)
                            .listRowBackground(palette.background)
                    ))
            }
        }
        return AnyView(
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                row
            })
    }

    nonisolated static func matches(
        _ kind: NotificationKind, selected: Set<NotificationKind>
    ) -> Bool {
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
            in: Capsule()
        )
        .glassEffectID(label, in: chipIndicator)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func errorStrip(_ message: String) -> some View {
        AlohaErrorStrip(message: message) {
            Task { await load() }
        }
        .listRowBackground(palette.background)
        .listRowSeparator(.hidden)
    }

    /// A group renders as one row: "Alice, Bob and 34 others favourited your
    /// post", with a stacked avatar row.
    private func groupRow(_ group: NotificationGroup) -> some View {
        let sample = group.sampleAccountIDs.compactMap { accounts[$0] }
        let status = group.statusID.flatMap { statuses[$0] }
        // A reply is a mention: the API has no separate kind, and both are a
        // message from a person that a conversation can be muted over.
        let canMuteConversation = status != nil && group.type == .mention

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

                    Text(
                        summary(
                            for: group, sample: sample,
                            showsCounts: session.settings.showPopularityCounts
                        )
                    )
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
            .contextMenu {
                if canMuteConversation, let status {
                    Button {
                        onAction(.muteConversation(status))
                    } label: {
                        Label(
                            status.displayed.muted
                                ? "Unmute conversation"
                                : "Mute conversation",
                            systemImage: AlohaSymbol.mute)
                    }
                }
            }
            .onAppear {
                // Advance the marker past the divider's group: the marker
                // names one notification, and a group's newest is the id the
                // server reports for it. Where the group below this one has
                // been seen, the reader has passed the divider.
                if let markerID = caughtUpNotificationID,
                    let idx = visibleGroups.firstIndex(where: {
                        $0.mostRecentNotificationID == markerID
                    }),
                    idx + 1 < visibleGroups.count,
                    visibleGroups[idx + 1].mostRecentNotificationID != markerID
                {
                    advanceCaughtUpNotificationMarker(
                        to: visibleGroups[idx + 1].mostRecentNotificationID)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// The grouped list with the catch-up divider in it.
    ///
    /// A group is placed below the divider when every notification it contains
    /// is older than the marker: the group's `most_recent_notification_id` is
    /// what the server reports, and the marker names the newest notification
    /// the reader had already seen. Comparing ids directly would be a
    /// lexicographic lie — the ids are opaque — so the comparison is on the
    /// group's own timestamp, and the id only decides whether a group *is* the
    /// marker's.
    private var groupedRowsWithMarker: some View {
        let groups = visibleGroups
        guard let markerID = caughtUpNotificationID,
            let markerIndex = groups.firstIndex(where: { $0.mostRecentNotificationID == markerID })
        else {
            return AnyView(
                ForEach(groups) { group in
                    groupRow(group)
                        .listRowBackground(palette.background)
                })
        }

        var rows: [AnyView] = []
        for (index, group) in groups.enumerated() {
            rows.append(
                AnyView(
                    groupRow(group)
                        .listRowBackground(palette.background)
                ))
            if index == markerIndex {
                rows.append(
                    AnyView(
                        caughtUpDivider(after: markerID)
                            .listRowBackground(palette.background)
                    ))
            }
        }
        return AnyView(
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in row }
        )
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
            .contextMenu {
                let canMute =
                    notification.status != nil
                    && notification.type == .mention
                if canMute, let status = notification.status {
                    Button {
                        onAction(.muteConversation(status))
                    } label: {
                        Label(
                            status.displayed.muted
                                ? "Unmute conversation"
                                : "Mute conversation",
                            systemImage: AlohaSymbol.mute)
                    }
                }
            }
            .onAppear {
                // Advance the "caught up" marker when the first notification
                // below the divider appears.
                if let markerID = caughtUpNotificationID,
                    let idx = visibleFlat.firstIndex(where: { $0.id == markerID }),
                    idx + 1 < visibleFlat.count,
                    visibleFlat[idx + 1].id == notification.id
                {
                    Task { await advanceCaughtUpNotificationMarker(to: notification.id) }
                }
            }
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
            // Fetch the notification policy when the server supports it; its
            // summary carries the count of filtered requests we display at
            // the top of the list.
            if session.capabilities.notificationPolicy {
                let useV2 = session.capabilities.notificationPolicy
                let policy = try await session.client.decode(
                    NotificationPolicy.self, from: Endpoint.notifications.policy(v2: useV2))
                guard !Task.isCancelled, loadID == requestID else { return }
                notificationPolicy = policy
            }
            // Fetch the "caught up" marker for the notifications timeline.
            let markers = try await session.client.decode(
                MarkerSet.self, from: Endpoint.markers.read)
            guard !Task.isCancelled, loadID == requestID else { return }
            caughtUpNotificationID = markers.notifications?.lastReadID
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

    private func summary(
        for group: NotificationGroup, sample: [Account], showsCounts: Bool = true
    )
        -> String
    {
        let name =
            sample.first?.bestDisplayName
            ?? String(
                localized: "Someone", comment: "Unknown account in a notification")
        let others = max(0, group.notificationsCount - 1)

        let who: String
        switch (others, showsCounts) {
        case (0, _): who = name
        case (1, true):
            who = String(
                localized: "\(name) and 1 other", comment: "Grouped notification participants")
        case (_, true):
            who = String(
                localized: "\(name) and \(others) others",
                comment: "Grouped notification participants")
        case (_, false):
            // Names stay, the list still opens; only the crowd's size goes.
            who = String(
                localized: "\(name) and others", comment: "Grouped notification participants")
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

    /// Advances the notifications marker past the divider.
    ///
    /// Async because the local marker lives in an actor: this is the one write
    /// that must not be attempted from a synchronous function, and the server
    /// sync folds into the same await rather than a Task inside a Task.
    private func advanceCaughtUpNotificationMarker(to notificationID: String) async {
        guard caughtUpNotificationID != nil else { return }
        caughtUpNotificationID = notificationID

        do {
            try await session.supportStore.advanceMarker(
                accountID: session.id, timeline: "notifications", to: notificationID)
        } catch {}

        let endpoint = Endpoint.markers.write(home: nil, notifications: notificationID)
        do { _ = try await session.client.send(endpoint) } catch {}
    }

    private func caughtUpDivider(after notificationID: String) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Spacer()
            VStack(spacing: AlohaMetrics.space1) {
                Rectangle()
                    .fill(palette.separator)
                    .frame(height: 1)
                Text("You're caught up", comment: "Notifications caught up divider")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.tertiaryLabel)
            }
            Spacer()
        }
        .padding(.vertical, AlohaMetrics.space3)
        .listRowBackground(palette.background)
        .listRowSeparator(.hidden)
    }
}
