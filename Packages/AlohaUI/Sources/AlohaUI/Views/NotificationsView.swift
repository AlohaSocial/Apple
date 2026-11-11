// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import AlohaNetwork
import AlohaStore
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
    /// The marker the divider is drawn at, captured when the list loads.
    /// `caughtUpNotificationID` advances as rows are seen, but moving the
    /// line at the same time made it slide under the reader's thumb and
    /// re-layout the list on every appearance.
    @State private var caughtUpDisplayID: String?
    /// The reader's filters, in the notifications context: an activity
    /// about a post a hide filter matched is left out, and one a warn filter
    /// matched names the filter instead of quoting the post.
    @State private var verdicts = FilterVerdicts(context: .notifications)

    public init(session: AccountSession, onAction: @escaping (StatusRowAction) -> Void) {
        self.session = session
        self.onAction = onAction
    }

    public var body: some View {
        List {
            if let errorMessage {
                errorStrip(errorMessage)
            }

            AlohaHint(
                id: "activities-hold",
                symbol: "hand.tap",
                title: Text("Hold an activity", comment: "Activities hint title"),
                message: Text(
                    "Touch and hold a mention to mute the conversation it belongs to.",
                    comment: "Activities hint")
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

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
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                Text(
                                    "Filtered notifications",
                                    comment: "Filtered notifications section")
                                Spacer()
                                Text(verbatim: "\(summary.pendingRequestsCount)")
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
                    Text("No matching activities", comment: "Notification filter empty state")
                } description: {
                    Text(
                        "Choose another filter to see more activities.",
                        comment: "Notification filter empty state guidance")
                } actions: {
                    Button("Show all") { selectedKinds = [] }
                        .buttonStyle(.bordered)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .alohaGround(palette)
        // A bar, not an opaque inset: the system's scroll-edge effect keeps
        // the chips legible over the rows passing under them, the way a
        // toolbar does, instead of a slab of ground colour cutting the list.
        .safeAreaBar(edge: .top, spacing: 0) {
            filterChips
                .padding(.horizontal, AlohaMetrics.space3)
                .padding(.vertical, AlohaMetrics.space2)
        }
        .overlay {
            if isLoading && groups.isEmpty && flat.isEmpty {
                SkeletonListRow(person: 4)
            }
        }
        .navigationTitle(Text("Activities", comment: "Screen title"))
        .refreshable { await load() }
        .task { await load() }
        .onStatusesRemoved(for: session) { removal in
            withAnimation {
                flat.removeAll { Self.isRemoved($0, by: removal) }
                groups.removeAll { Self.isRemoved($0, statuses: statuses, by: removal) }
            }
        }
    }

    /// An activity goes with its post, and with the person a block or mute
    /// was for: "Bob mentioned you" from somebody just blocked is them still
    /// reaching the reader.
    nonisolated static func isRemoved(
        _ notification: MastodonNotification, by removal: TimelineStatusRemoval
    ) -> Bool {
        if let status = notification.status, removal.removes(status) { return true }
        return removal.authorID == notification.account.id
    }

    /// A group goes with its post, or when everybody it names is the person
    /// blocked; a group with others in it stays, since they still did it.
    nonisolated static func isRemoved(
        _ group: NotificationGroup, statuses: [String: Status],
        by removal: TimelineStatusRemoval
    ) -> Bool {
        if let id = group.statusID {
            if removal.statusIDs.contains(id) { return true }
            if let status = statuses[id], removal.removes(status) { return true }
        }
        guard let authorID = removal.authorID, !group.sampleAccountIDs.isEmpty else {
            return false
        }
        return group.sampleAccountIDs.allSatisfy { $0 == authorID }
    }

    private var visibleGroups: [NotificationGroup] {
        groups.filter { group in
            Self.matches(group.type, selected: selectedKinds)
                && group.statusID.flatMap { statuses[$0] }.map { verdicts.isHidden($0) } != true
        }
    }

    private var visibleFlat: [MastodonNotification] {
        flat.filter { notification in
            Self.matches(notification.type, selected: selectedKinds)
                && notification.status.map { verdicts.isHidden($0) } != true
        }
    }

    /// What a notification quotes of its post: the words, or only the
    /// content warning where the post has one — the flat row used to print
    /// the words regardless — or only the filter's name where a warn filter
    /// matched it.
    private func statusPreview(_ status: Status) -> some View {
        Group {
            if let warning = verdicts.warning(for: status) {
                Text("Filtered: \(warning)", comment: "Row hidden by a keyword filter")
                    .lineLimit(1)
            } else if status.displayed.spoilerText.isEmpty {
                StatusPlainPreview(status: status)
            } else {
                Text(status.displayed.spoilerText).lineLimit(2)
            }
        }
        .font(.caption)
        .foregroundStyle(palette.secondaryLabel)
    }

    /// The flat list — which is what a Nextcloud server serves — with the same
    /// day headings as the grouped one and the optional "caught up" divider.
    /// When the marker notification is in the visible list, a divider is
    /// inserted below it; the marker advances when the next notification
    /// appears (handled in `flatRow`).
    private var flatRowsWithMarker: some View {
        ForEach(flatActivityRows) { row in
            switch row {
            case .day(let date):
                activityDayHeader(date)
            case .item(let notification):
                flatRow(notification)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(
                        EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            case .caughtUp(let after):
                caughtUpDivider(after: after)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(
                        EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }
        }
    }

    private var flatActivityRows: [FlatActivityDisplayRow] {
        let notifications = visibleFlat
        let markerID = caughtUpDisplayID
        let markerIndex = markerID.flatMap { id in notifications.firstIndex { $0.id == id } }
        var rows: [FlatActivityDisplayRow] = []
        var day: Date?
        for row in ActivityListRow.rows(
            notifications, dividerAfter: markerIndex, markerID: markerID)
        {
            switch row {
            case .item(let notification):
                let start = Calendar.current.startOfDay(for: notification.createdAt)
                if start != day {
                    rows.append(.day(start))
                    day = start
                }
                rows.append(.item(notification))
            case .caughtUp(let after):
                rows.append(.caughtUp(after))
            }
        }
        return rows
    }

    nonisolated static func matches(
        _ kind: NotificationKind, selected: Set<NotificationKind>
    ) -> Bool {
        selected.isEmpty || selected.contains(kind)
            || (kind == .followRequest && selected.contains(.follow))
    }

    private var filterChips: some View {
        ScrollView(.horizontal) {
            AlohaGlassContainer(spacing: AlohaMetrics.space2) {
                HStack(spacing: AlohaMetrics.space2) {
                    chip(nil, label: String(localized: "All", comment: "Notification filter"))
                    chip(
                        .mention,
                        label: String(localized: "Mentions", comment: "Notification filter"))
                    // Nextcloud Social's own filters, in its order.
                    chip(
                        .favourite,
                        label: String(localized: "Favourites", comment: "Notification filter"))
                    chip(
                        .reblog,
                        label: String(localized: "Boosts", comment: "Notification filter"))
                    chip(
                        .follow,
                        label: String(localized: "Follows", comment: "Notification filter"))
                    chip(.poll, label: String(localized: "Polls", comment: "Notification filter"))
                    chip(.update, label: String(localized: "Edits", comment: "Notification filter"))
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
        .alohaGlassEffect(
            .regular.tint(isSelected ? palette.accent : nil).interactive(),
            in: Capsule()
        )
        .alohaGlassEffectID(label, in: chipIndicator)
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
            activityCard(
                kind: group.type,
                accounts: sample,
                summary: summary(
                    for: group, sample: sample,
                    showsCounts: session.settings.showPopularityCounts),
                status: status,
                date: group.latestPageNotificationAt
            )
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
                if let markerID = caughtUpDisplayID,
                    let idx = visibleGroups.firstIndex(where: {
                        $0.mostRecentNotificationID == markerID
                    }),
                    idx + 1 < visibleGroups.count,
                    visibleGroups[idx + 1].mostRecentNotificationID != markerID
                {
                    Task {
                        await advanceCaughtUpNotificationMarker(
                            to: visibleGroups[idx + 1].mostRecentNotificationID)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// The grouped list with day headings in it, so a long list reads as
    /// days rather than one undifferentiated column, and the catch-up
    /// divider below the one the reader had already seen.
    ///
    /// A group is placed below the divider when every notification it contains
    /// is older than the marker: the group's `most_recent_notification_id` is
    /// what the server reports, and the marker names the newest notification
    /// the reader had already seen. Comparing ids directly would be a
    /// lexicographic lie — the ids are opaque — so the comparison is on the
    /// group's own timestamp, and the id only decides whether a group *is* the
    /// marker's.
    private var groupedRowsWithMarker: some View {
        ForEach(activityRows) { row in
            switch row {
            case .day(let date):
                activityDayHeader(date)
            case .item(let group):
                groupRow(group)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(
                        EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            case .caughtUp(let after):
                caughtUpDivider(after: after)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(
                        EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }
        }
    }

    /// Groups in server order, with a heading wherever the day changes.
    private var activityRows: [ActivityDisplayRow] {
        let groups = visibleGroups
        let markerID = caughtUpDisplayID
        let markerIndex = markerID.flatMap { id in
            groups.firstIndex { $0.mostRecentNotificationID == id }
        }
        var rows: [ActivityDisplayRow] = []
        var day: Date?
        for row in ActivityListRow.rows(groups, dividerAfter: markerIndex, markerID: markerID) {
            switch row {
            case .item(let group):
                if let date = group.latestPageNotificationAt {
                    let start = Calendar.current.startOfDay(for: date)
                    if start != day {
                        rows.append(.day(start))
                        day = start
                    }
                }
                rows.append(.item(group))
            case .caughtUp(let after):
                rows.append(.caughtUp(after))
            }
        }
        return rows
    }

    /// "Today" and "Yesterday" first, then the date: a heading is read to
    /// find where a day starts, not to learn a calendar.
    private func activityDayHeader(_ date: Date) -> some View {
        let calendar = Calendar.current
        let title: String
        if calendar.isDateInToday(date) {
            title = String(localized: "Today", comment: "Activity day heading")
        } else if calendar.isDateInYesterday(date) {
            title = String(localized: "Yesterday", comment: "Activity day heading")
        } else {
            title = date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        return HStack(spacing: AlohaMetrics.space2) {
            Text(title)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(palette.secondaryLabel)
            Rectangle()
                .fill(palette.separator.opacity(0.6))
                .frame(height: 0.5)
        }
        .padding(.top, AlohaMetrics.space4)
        .padding(.bottom, AlohaMetrics.space1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .accessibilityIdentifier("activity-day-header")
        .accessibilityAddTraits(.isHeader)
    }

    private func flatRow(_ notification: MastodonNotification) -> some View {
        Button {
            if let status = notification.status {
                onAction(.open(status))
            } else {
                onAction(.openProfile(notification.account))
            }
        } label: {
            activityCard(
                kind: notification.type,
                accounts: [notification.account],
                summary: summary(for: notification),
                status: notification.status,
                date: notification.createdAt
            )
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
                if let markerID = caughtUpDisplayID,
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

    /// An activity as a card of its own, rather than a line in a list.
    ///
    /// The face, what happened, a piece of the post and when: four things
    /// read in one glance, the way a notification is actually understood.
    /// The card is drawn like the rest of the app's surfaces — a raised fill
    /// and a hairline — rather than as a tinted, shadowed tile of its own.
    /// The kind is carried by the badge on the avatar, where it belongs.
    private func activityCard(
        kind: NotificationKind,
        accounts: [Account],
        summary: String,
        status: Status?,
        date: Date?
    ) -> some View {
        HStack(alignment: .top, spacing: AlohaMetrics.space3) {
            activityAvatars(accounts, kind: kind)

            VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                Text(summary)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(palette.label)

                if let status {
                    statusPreview(status)
                        .padding(AlohaMetrics.space2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            palette.background.opacity(0.5),
                            in: RoundedRectangle(
                                cornerRadius: AlohaMetrics.cornerSmall, style: .continuous)
                        )
                }

                if let date { activityDate(date) }
            }
        }
        .padding(AlohaMetrics.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            palette.surfaceRaised,
            in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
        )
        // A hairline so the card reads as a layer over the scroll rather than
        // as a slightly different colour — the app's own card language.
        .overlay(
            RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
                .strokeBorder(palette.separator.opacity(0.5), lineWidth: 0.5)
        )
        .contentShape(
            RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous))
    }

    /// Up to three faces, overlapped, with the kind's badge on the corner:
    /// a group announces who and what without spelling out either.
    private func activityAvatars(_ accounts: [Account], kind: NotificationKind) -> some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: -13) {
                if accounts.isEmpty {
                    Circle()
                        .fill(palette.surfaceRaised)
                        .frame(width: 42, height: 42)
                        .overlay(
                            Image(systemName: symbol(for: kind))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(tint(for: kind))
                        )
                } else {
                    ForEach(Array(accounts.prefix(3).enumerated()), id: \.element.id) {
                        index, account in
                        AvatarView(account: account, size: 42)
                            .overlay(
                                Circle().strokeBorder(palette.surfaceRaised, lineWidth: 2)
                            )
                            .zIndex(Double(3 - index))
                    }
                }
            }
            activityBadge(kind, size: 22)
                .offset(x: 5, y: 5)
        }
        .frame(width: 54, height: 48, alignment: .bottomLeading)
    }

    /// The kind of activity as a tinted disc: what happened, legible at a
    /// glance before a word of the sentence under it is read.
    private func activityBadge(_ kind: NotificationKind, size: CGFloat = 30) -> some View {
        Image(systemName: symbol(for: kind))
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint(for: kind))
            .frame(width: size, height: size)
            .background(tint(for: kind).opacity(0.16), in: Circle())
            .overlay(Circle().strokeBorder(palette.surfaceRaised, lineWidth: 2))
            .accessibilityHidden(true)
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

        let types = Endpoint.notifications.everyType(
            onAlohaSocial: session.capabilities.isNextcloudSocial)
        do {
            if session.capabilities.groupedNotifications {
                let results = try await session.client.decode(
                    GroupedNotificationsResults.self,
                    from: Endpoint.notifications.grouped(types: types))
                await verdicts.prepare(results.statuses, session: session)
                guard !Task.isCancelled, loadID == requestID else { return }
                groups = results.notificationGroups
                accounts = Dictionary(
                    results.accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                statuses = Dictionary(
                    results.statuses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            } else {
                let page = try await session.client.decode(
                    LossyArray<MastodonNotification>.self,
                    from: Endpoint.notifications.flat(types: types))
                await verdicts.prepare(page.elements.compactMap(\.status), session: session)
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
            // The divider belongs where the list opened, not wherever the
            // marker has advanced to by the time a refresh returns.
            if caughtUpDisplayID == nil {
                caughtUpDisplayID = caughtUpNotificationID
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
        case .storyReaction: "face.smiling"
        case .storyComment: "bubble.left"
        case .tagged: "person.crop.rectangle"
        case .blueskyRepostLiked: AlohaSymbol.favouriteFilled
        case .blueskyRepostReposted: AlohaSymbol.boost
        case .blueskyVerified: "checkmark.seal.fill"
        case .blueskyUnverified: "checkmark.seal"
        case .blueskyStarterPackJoined: "person.3"
        default: AlohaSymbol.notifications
        }
    }

    private func tint(for kind: NotificationKind) -> Color {
        switch kind {
        case .reblog, .blueskyRepostReposted: palette.boost
        case .favourite, .blueskyRepostLiked: palette.favourite
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
        case .storyReaction:
            return String(
                localized: "\(who) reacted to your story", comment: "Notification summary")
        case .storyComment:
            return String(
                localized: "\(who) replied to your story", comment: "Notification summary")
        case .tagged:
            return String(
                localized: "\(who) tagged you in a photo", comment: "Notification summary")
        case .blueskyRepostLiked:
            return String(
                localized: "\(who) liked your repost on Bluesky", comment: "Notification summary")
        case .blueskyRepostReposted:
            return String(
                localized: "\(who) reposted your repost on Bluesky",
                comment: "Notification summary")
        case .blueskyVerified:
            return String(
                localized: "Bluesky verified your account", comment: "Notification summary")
        case .blueskyUnverified:
            return String(
                localized: "Bluesky no longer verifies your account",
                comment: "Notification summary")
        case .blueskyStarterPackJoined:
            return String(
                localized: "\(who) joined Bluesky with your starter pack",
                comment: "Notification summary")
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

    /// Advances the notifications marker past the divider.
    ///
    /// Async because the local marker lives in an actor: this is the one write
    /// that must not be attempted from a synchronous function, and the server
    /// sync folds into the same await rather than a Task inside a Task.
    private func advanceCaughtUpNotificationMarker(to notificationID: String) async {
        guard caughtUpNotificationID != nil,
            caughtUpNotificationID != notificationID
        else { return }
        caughtUpNotificationID = notificationID

        // Whether the stored marker actually moved does not matter here: the
        // server's copy is written either way, and it never moves backwards.
        do {
            _ = try await session.supportStore.advanceMarker(
                accountID: session.id, timeline: "notifications", to: notificationID)
        } catch {}

        let endpoint = Endpoint.markers.write(home: nil, notifications: notificationID)
        do { _ = try await session.client.send(endpoint) } catch {}
    }

    private func caughtUpDivider(after notificationID: String) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Rectangle()
                .fill(palette.separator.opacity(0.6))
                .frame(height: 0.5)
            Text("You're caught up", comment: "Notifications caught up divider")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.secondaryLabel)
                .padding(.horizontal, AlohaMetrics.space2)
                .padding(.vertical, 5)
                .background(palette.surfaceRaised, in: Capsule())
                .fixedSize()
            Rectangle()
                .fill(palette.separator.opacity(0.6))
                .frame(height: 0.5)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

/// A day heading, a flat notification, or the catch-up divider.
private enum FlatActivityDisplayRow: Identifiable {
    case day(Date)
    case item(MastodonNotification)
    case caughtUp(String)

    var id: String {
        switch self {
        case .day(let date): "flat-day-\(date.timeIntervalSinceReferenceDate)"
        case .item(let notification): "flat-item-\(notification.id)"
        case .caughtUp(let after): "flat-caughtUp-\(after)"
        }
    }
}

/// A day heading, a notification group, or the catch-up divider.
private enum ActivityDisplayRow: Identifiable {
    case day(Date)
    case item(NotificationGroup)
    case caughtUp(String)

    var id: String {
        switch self {
        case .day(let date): "day-\(date.timeIntervalSinceReferenceDate)"
        case .item(let group): "item-\(group.id)"
        case .caughtUp(let after): "caughtUp-\(after)"
        }
    }
}
