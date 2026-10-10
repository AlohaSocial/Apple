// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaIntelligence
import AlohaMedia
import AlohaModels
import AlohaNetwork
import SwiftUI

public struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.alohaPalette) private var palette

    /// Eight sections in one scroll is a lot to read through for one switch.
    @State private var settingsQuery = ""

    /// Section titles and the words somebody might actually type looking for
    /// them — "dark" should find Appearance, not nothing.
    private static let searchTerms: [(title: String, keywords: String)] = [
        ("Accounts", "account accounts add sign switch remove"),
        (
            "Your account",
            "profile edit name bio avatar header fields featured hashtags portfolio channels migration export import move alias authorized apps tokens"
        ),
        ("Appearance", "appearance theme density serif icon dark light text"),
        ("Nextcloud", "nextcloud files push notification server connect"),
        ("Media", "media autoplay video sensitive blur mute loop data"),
        ("Posting", "posting compose composer visibility language alt draft"),
        ("Intelligence", "intelligence ai writing rewrite summary on-device apple"),
        ("Storage", "storage cache cached media clear disk"),
        (
            "Content",
            "content filter filters language translate translation mute block drafts held review waiting moderator memories recap looking back on this day"
        ),
        ("Sound & touch", "sound touch haptics vibrate vibration audio chime tick senses silent"),
        ("Moderation", "moderation moderator reports admin administrator suspend silence trends"),
        (
            "Delete account",
            "delete account erase remove deactivate close"
        ),
        (
            "About",
            "about licence license version source code developer contact server peers activity federation keyboard shortcuts year wrapped"
        ),
    ]

    private func shows(_ title: String, _ keywords: String) -> Bool {
        guard !settingsQuery.isEmpty else { return true }
        let needle = settingsQuery.lowercased()
        return title.lowercased().contains(needle) || keywords.contains(needle)
    }

    private var hasAnyMatch: Bool {
        Self.searchTerms.contains { shows($0.title, $0.keywords) }
    }

    /// The host comes from the server, so the string is not ours to trust: a
    /// name the URL parser refuses is a link with nowhere to go, and there is
    /// no forced URL that could be asked for one. The scheme and port are
    /// read from the stored API base so a private-network `http` server opens
    /// over `http` rather than a connection that can only fail.
    private func serverDestination(_ session: AccountSession) -> URL? {
        guard
            let url = URL(string: session.capabilities.apiBase.originString),
            url.host != nil
        else { return nil }
        return url
    }

    /// The shell's sheets carry the same guard: with no active account there
    /// is no session to build the next screen from, so the presentation reads
    /// back as not presented rather than going up with an empty body.
    private func whenSignedIn(_ binding: Binding<Bool>) -> Binding<Bool> {
        let hasSession = environment.activeSession != nil
        return Binding(
            get: { hasSession && binding.wrappedValue },
            set: { binding.wrappedValue = hasSession && $0 })
    }

    private let onAddAccount: () -> Void
    @State private var cacheSize = 0
    @State private var isShowingNextcloudConnect = false
    @State private var isShowingShortcuts = false

    public init(onAddAccount: @escaping () -> Void) {
        self.onAddAccount = onAddAccount
    }

    public var body: some View {
        @Bindable var environment = environment

        Form {
            if shows("Accounts", "account accounts add sign switch remove") {
                Section {
                    ForEach(environment.sessions) { session in
                        Button {
                            environment.setActiveAccount(session.id)
                        } label: {
                            HStack(spacing: AlohaMetrics.space3) {
                                AvatarView(
                                    account: session.snapshot.asAccount,
                                    size: AlohaMetrics().avatarSize
                                )
                                .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.snapshot.bestDisplayName).font(.body)
                                    Text(session.snapshot.qualifiedHandle)
                                        .font(.caption)
                                        .foregroundStyle(palette.secondaryLabel)
                                }
                                Spacer()
                                if session.needsReauthentication {
                                    Text("Sign in again", comment: "Account state")
                                        .font(.caption)
                                        .foregroundStyle(palette.destructive)
                                }
                                if session.id == environment.activeSession?.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(palette.accent)
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accountLabel(session))
                        .accessibilityAddTraits(
                            session.id == environment.activeSession?.id
                                ? [.isButton, .isSelected] : .isButton
                        )
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await environment.removeAccount(session.id) }
                            } label: {
                                Text("Remove", comment: "Account action")
                            }
                        }
                    }

                    Button(action: onAddAccount) {
                        Text("Add account…", comment: "Settings action")
                    }
                } header: {
                    Text("Accounts", comment: "Settings section")
                }
            }

            if shows(
                "Appearance",
                "appearance theme density serif icon counts numbers text size compact")
            {
                Section {
                    Picker(selection: $environment.theme) {
                        ForEach(AlohaTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    } label: {
                        Text("Theme", comment: "Settings item")
                    }

                    Picker(selection: $environment.metrics.density) {
                        Text("Compact", comment: "Density").tag(AlohaMetrics.Density.compact)
                        Text("Comfortable", comment: "Density").tag(
                            AlohaMetrics.Density.comfortable)
                        Text("Spacious", comment: "Density").tag(AlohaMetrics.Density.spacious)
                    } label: {
                        Text("Density", comment: "Settings item")
                    }

                    // docs/05 §9: the appearance section owns the counts switch
                    // — "show/hide counts" sits with how the app looks, next to
                    // density and the reading options, not buried in the feed's
                    // behaviour. It is the same setting either way.
                    if let session = environment.activeSession {
                        Toggle(
                            isOn: Binding(
                                get: { session.settings.showPopularityCounts },
                                set: { value in
                                    Task {
                                        await session.updateSettings {
                                            $0.showPopularityCounts = value
                                        }
                                    }
                                })
                        ) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show numbers", comment: "Settings item")
                                Text(
                                    "Reply, boost and favourite counts, follower and post counts, and view counts.",
                                    comment: "Settings explanation"
                                )
                                .font(.footnote)
                                .foregroundStyle(palette.secondaryLabel)
                            }
                        }
                    }

                    Toggle(isOn: $environment.metrics.useSerifBody) {
                        Text("Serif body text", comment: "Settings item")
                    }

                    #if os(iOS)
                        AppIconPicker()
                    #endif
                } header: {
                    Text("Appearance", comment: "Settings section")
                } footer: {
                    if environment.serverAccent != nil {
                        Text(
                            "The accent colour comes from your Nextcloud, so the app looks like the server it is signed in to.",
                            comment: "Where the accent colour comes from")
                    }
                }
            }

            if let session = environment.activeSession {
                if shows(
                    "Your account",
                    "profile edit name bio avatar header fields featured hashtags portfolio channels migration export import move alias authorized apps tokens"
                ) {
                    yourAccountSection(session)
                }
                if shows("Timeline", "timeline feed boosts replies pill position restore numbers") {
                    timelineSection(session)
                }
                if shows("Nextcloud", "nextcloud files push notification server connect") {
                    nextcloudSection(session)
                }
                if shows("Media", "media autoplay video sensitive blur mute loop data") {
                    mediaSection(session)
                }
                if shows("Notifications", "notifications push digest quiet hours delivery sounds") {
                    notificationsSection(session)
                }
                if shows("Posting", "posting compose composer visibility language alt draft") {
                    composerSection(session)
                }
            }

            if shows("Intelligence", "intelligence ai writing rewrite summary on-device apple") {
                intelligenceSection
            }

            if !settingsQuery.isEmpty && !hasAnyMatch {
                ContentUnavailableView.search(text: settingsQuery)
            }

            if shows("Storage", "storage cache cached media clear disk") {
                Section {
                    LabeledContent {
                        Text(cacheSize.formatted(.byteCount(style: .file)))
                    } label: {
                        Text("Cached media", comment: "Settings item")
                    }

                    Button(role: .destructive) {
                        Task {
                            await ImageLoader.shared.clear()
                            cacheSize = await ImageLoader.shared.currentDiskSize()
                        }
                    } label: {
                        Text("Clear cache", comment: "Settings action")
                    }
                } header: {
                    Text("Storage", comment: "Settings section")
                }
            }

            if shows(
                "Content",
                "content filter filters language translate translation mute block drafts held review waiting moderator memories recap looking back on this day"
            ) {
                Section {
                    NavigationLink(value: Route.filters) {
                        Label {
                            Text("Filters", comment: "Settings item")
                        } icon: {
                            Image(systemName: "line.3.horizontal.decrease")
                        }
                    }
                    NavigationLink(value: Route.safety) {
                        Label {
                            Text("Privacy & Safety", comment: "Settings item")
                        } icon: {
                            Image(systemName: AlohaSymbol.block)
                        }
                    }
                    NavigationLink(value: Route.notificationRequests) {
                        Label {
                            Text("Filtered notifications", comment: "Settings item")
                        } icon: {
                            Image(systemName: AlohaSymbol.filter)
                        }
                    }
                    // The notification policy screen is only shown when the server
                    // supports it (Mastodon 4.3+ / Nextcloud Social with v2).
                    if session.capabilities.notificationPolicy {
                        NavigationLink(value: Route.notificationPolicy) {
                            Label {
                                Text("Notification policy", comment: "Settings item")
                            } icon: {
                                Image(systemName: AlohaSymbol.shield)
                            }
                        }
                    }
                    NavigationLink(value: Route.drafts) {
                        Label {
                            Text("Drafts", comment: "Settings item")
                        } icon: {
                            Image(systemName: AlohaSymbol.compose)
                        }
                    }
                    if environment.activeSession?.capabilities.isNextcloudSocial == true {
                        // A post a moderator holds must never vanish without a
                        // word; this is where it waits.
                        NavigationLink(value: Route.heldPosts) {
                            Label {
                                Text("Waiting to be looked at", comment: "Settings item")
                            } icon: {
                                Image(systemName: "clock.badge.questionmark")
                            }
                        }
                        NavigationLink(value: Route.memories) {
                            Label {
                                Text("Looking back", comment: "Settings item")
                            } icon: {
                                Image(systemName: "calendar.badge.clock")
                            }
                        }
                    }
                } header: {
                    Text("Content", comment: "Settings section")
                }
            }

            if shows(
                "Sound & touch",
                "sound touch haptics vibrate vibration audio chime tick senses silent")
            {
                sensesSection
            }

            if let session = environment.activeSession,
                session.capabilities.isNextcloudSocial,
                shows(
                    "Moderation",
                    "moderation moderator reports admin administrator suspend silence trends")
            {
                moderationSection(session)
            }

            if let session = environment.activeSession,
                shows("Delete account", "delete account erase remove deactivate close"),
                session.capabilities.isNextcloudSocial || serverDestination(session) != nil
            {
                Section {
                    if session.capabilities.isNextcloudSocial {
                        // Nextcloud Social can do this over the API, so the
                        // reader never has to ask an administrator — which
                        // means explaining to a colleague why.
                        NavigationLink(value: Route.deleteAccount) {
                            Text("Delete my Social account", comment: "Settings action")
                                .foregroundStyle(palette.destructive)
                        }
                    } else if let serverURL = serverDestination(session) {
                        Link(destination: serverURL) {
                            Text("Delete my account on this server", comment: "Settings action")
                        }
                    }
                } footer: {
                    if session.capabilities.isNextcloudSocial {
                        Text(
                            "Your posts and follows go, every server that knew you is told, and your Nextcloud account is untouched.",
                            comment: "Account deletion explanation")
                    } else {
                        Text(
                            "Signing out removes everything from this device. Deleting the account itself happens on \(session.snapshot.instanceHost), because that is where it lives.",
                            comment: "Account deletion explanation")
                    }
                }
            }

            if shows("About", "about licence license version source code developer contact") {
                Section {
                    LabeledContent {
                        Text(verbatim: "1.0")
                    } label: {
                        Text("Version", comment: "Settings item")
                    }
                    Link(destination: URL(string: "https://github.com/AlohaSocial/Apple")!) {
                        Text("Source code", comment: "Settings item")
                    }
                    Link(
                        destination: URL(string: "https://github.com/AlohaSocial/Apple/issues")!
                    ) {
                        Text("Contact the developer", comment: "Settings item")
                    }
                    if environment.activeSession != nil {
                        NavigationLink(value: Route.serverInfo) {
                            Label {
                                Text("About this server", comment: "Settings item")
                            } icon: {
                                Image(systemName: "server.rack")
                            }
                        }
                    }
                    Button {
                        isShowingShortcuts = true
                    } label: {
                        Label {
                            Text("Keyboard shortcuts", comment: "Settings item")
                        } icon: {
                            Image(systemName: "keyboard")
                        }
                    }
                } header: {
                    Text("About", comment: "Settings section")
                } footer: {
                    Text(
                        "Aloha Social is open source under the MIT licence.",
                        comment: "Settings footer")
                }
            }
        }
        .formStyle(.grouped)
        .alohaGround(palette)
        .searchable(
            text: $settingsQuery,
            placement: .automatic,
            prompt: Text("Search settings", comment: "Settings search field")
        )
        .navigationTitle(Text("Settings", comment: "Screen title"))
        .sheet(isPresented: $isShowingShortcuts) { ShortcutHelpView() }
        .sheet(isPresented: whenSignedIn($isShowingNextcloudConnect)) {
            if let session = environment.activeSession {
                NextcloudConnectView(session: session)
            }
        }
        .task { cacheSize = await ImageLoader.shared.currentDiskSize() }
    }

    /// Everything about who you are on the server, the way Nextcloud Social's
    /// own settings page lists it: profile first, then what hangs off it.
    private func yourAccountSection(_ session: AccountSession) -> some View {
        Section {
            NavigationLink(value: Route.editProfile) {
                Label {
                    Text("Edit profile", comment: "Settings item")
                } icon: {
                    Image(systemName: AlohaSymbol.profile)
                }
            }
            NavigationLink(value: Route.featuredTags) {
                Label {
                    Text("Featured hashtags", comment: "Settings item")
                } icon: {
                    Image(systemName: AlohaSymbol.hashtag)
                }
            }
            if session.capabilities.isNextcloudSocial {
                NavigationLink(value: Route.portfolio) {
                    Label {
                        Text("Portfolio", comment: "Settings item")
                    } icon: {
                        Image(systemName: "photo.on.rectangle.angled")
                    }
                }
                NavigationLink(value: Route.channels) {
                    Label {
                        Text("Video channels", comment: "Settings item")
                    } icon: {
                        Image(systemName: "tv")
                    }
                }
                NavigationLink(value: Route.migration) {
                    Label {
                        Text("Migration", comment: "Settings item")
                    } icon: {
                        Image(systemName: "shippingbox")
                    }
                }
                NavigationLink(value: Route.authorizedApps) {
                    Label {
                        Text("Authorized apps", comment: "Settings item")
                    } icon: {
                        Image(systemName: "key")
                    }
                }
                NavigationLink(value: Route.annualReport) {
                    Label {
                        Text("Your year", comment: "Settings item")
                    } icon: {
                        Image(systemName: "calendar")
                    }
                }
            }
        } header: {
            Text("Your account", comment: "Settings section")
        }
    }

    /// Sound and touch, per device. Nothing here goes to the server: both are
    /// about the phone or the Mac in front of the reader.
    private var sensesSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { Senses.shared.soundsEnabled },
                    set: { Senses.shared.soundsEnabled = $0 })
            ) {
                Text("Play sounds", comment: "Settings item")
            }

            // Its own row rather than a neighbour inside the switch's: in the
            // switch's row VoiceOver read the preview as part of the toggle,
            // and a tap anywhere on the row flipped the setting instead.
            HStack {
                Spacer(minLength: 0)
                Button {
                    Senses.shared.play(.like)
                } label: {
                    Label {
                        Text("Listen", comment: "Settings action")
                    } icon: {
                        Image(systemName: AlohaSymbol.play)
                    }
                }
                .buttonStyle(.borderless)
            }

            Toggle(
                isOn: Binding(
                    get: { Senses.shared.hapticsEnabled },
                    set: { Senses.shared.hapticsEnabled = $0 })
            ) {
                Text("Vibrate", comment: "Settings item")
            }
        } header: {
            Text("Sound & touch", comment: "Settings section")
        } footer: {
            Text(
                "A soft tick when you like something, a breath of air when a post goes out, and a two-note chime for a direct message. Off until you turn it on. A tap in the hand follows your Reduce Motion setting.",
                comment: "Senses explanation")
        }
    }

    /// The moderator's screens. Shown only where the server could serve them;
    /// everything behind the row says plainly when it is not yours to see.
    private func moderationSection(_ session: AccountSession) -> some View {
        Section {
            NavigationLink(value: Route.moderation) {
                Label {
                    Text("Moderation", comment: "Settings item")
                } icon: {
                    Image(systemName: "shield.lefthalf.filled")
                }
            }
        } header: {
            Text("Moderation", comment: "Settings section")
        } footer: {
            Text(
                "Only an administrator of this Nextcloud can act on reports and accounts. Everything else about running the instance stays in its administration page.",
                comment: "Moderation section explanation")
        }
    }

    private func nextcloudSection(_ session: AccountSession) -> some View {
        Section {
            Button {
                isShowingNextcloudConnect = true
            } label: {
                HStack {
                    Label {
                        Text("Your Nextcloud", comment: "Settings item")
                    } icon: {
                        Image(systemName: "cloud")
                    }
                    Spacer()
                    Text(
                        session.hasNextcloudConnection
                            ? String(localized: "Connected", comment: "Nextcloud state")
                            : String(localized: "Not connected", comment: "Nextcloud state")
                    )
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                }
            }
            .buttonStyle(.plain)

            if session.isPushActive {
                Label {
                    Text("Notifications are pushed", comment: "Push state")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .font(.footnote)
                .foregroundStyle(palette.boost)
            }
        } header: {
            Text("Nextcloud", comment: "Settings section")
        } footer: {
            Text(
                "Connecting your Nextcloud lets you attach files already on it, and lets notifications be pushed instead of polled.",
                comment: "Nextcloud settings explanation")
        }
    }

    /// What your home feed shows.
    ///
    /// These preferences were stored and read by the timeline but had no
    /// screen: `showBoosts`, `showReplies`, `restoreTimelinePosition` and
    /// `showNewPostsPill` all changed behaviour with no way to change them,
    /// and "Show numbers" sat under Media, where it is not about media at
    /// all. Every switch here now exists (docs/05 §2).
    private func timelineSection(_ session: AccountSession) -> some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { session.settings.showBoosts },
                    set: { value in
                        Task { await session.updateSettings { $0.showBoosts = value } }
                    })
            ) {
                Text("Show boosts", comment: "Settings item")
            }

            Toggle(
                isOn: Binding(
                    get: { session.settings.showReplies },
                    set: { value in
                        Task { await session.updateSettings { $0.showReplies = value } }
                    })
            ) {
                Text("Show replies", comment: "Settings item")
            }

            // "Show numbers" lives in Appearance, where docs/05 §9 puts it:
            // it is about how much the app shows, next to density and the
            // reading options, not about what the feed does.

            Toggle(
                isOn: Binding(
                    get: { session.settings.showNewPostsPill },
                    set: { value in
                        Task { await session.updateSettings { $0.showNewPostsPill = value } }
                    })
            ) {
                Text("New posts pill", comment: "Settings item")
            }

            Toggle(
                isOn: Binding(
                    get: { session.settings.restoreTimelinePosition },
                    set: { value in
                        Task { await session.updateSettings { $0.restoreTimelinePosition = value } }
                    })
            ) {
                Text("Return to where I was", comment: "Settings item")
            }
        } header: {
            Text("Home feed", comment: "Settings section")
        } footer: {
            Text(
                "Off, the new-posts pill disappears and every refresh scrolls to the top instead of holding your place.",
                comment: "Home feed section explanation")
        }
    }

    private func mediaSection(_ session: AccountSession) -> some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { session.settings.autoplayVideo },
                    set: { value in
                        Task { await session.updateSettings { $0.autoplayVideo = value } }
                    })
            ) {
                Text("Autoplay video", comment: "Settings item")
            }

            Toggle(
                isOn: Binding(
                    get: { session.settings.startMuted },
                    set: { value in Task { await session.updateSettings { $0.startMuted = value } }
                    })
            ) {
                Text("Start muted", comment: "Settings item")
            }

            Picker(
                selection: Binding(
                    get: { session.settings.sensitiveMediaPolicy },
                    set: { value in
                        Task { await session.updateSettings { $0.sensitiveMediaPolicy = value } }
                    })
            ) {
                Text("Always show", comment: "Sensitive media policy").tag(
                    SensitiveMediaPolicy.showAll)
                Text("Blur until tapped", comment: "Sensitive media policy").tag(
                    SensitiveMediaPolicy.blur)
                Text("Don't show at all", comment: "Sensitive media policy").tag(
                    SensitiveMediaPolicy.hideAll)
            } label: {
                Text("Sensitive media", comment: "Settings item")
            }
        } header: {
            Text("Media", comment: "Settings section")
        } footer: {
            // The cost is stated in one line rather than hidden.
            Text("Videos play automatically, including on cellular.", comment: "Autoplay footnote")
        }
    }

    private func notificationsSection(_ session: AccountSession) -> some View {
        Section {
            Picker(
                selection: Binding(
                    get: { session.settings.notificationDeliveryMode },
                    set: { value in
                        Task {
                            await session.updateSettings { $0.notificationDeliveryMode = value }
                        }
                    })
            ) {
                Text("As they arrive", comment: "Notification delivery mode")
                    .tag(AccountSettings.NotificationDeliveryMode.immediate)
                Text("In a digest", comment: "Notification delivery mode")
                    .tag(AccountSettings.NotificationDeliveryMode.digest)
            } label: {
                Text("Delivery", comment: "Notification delivery mode")
            }

            if session.settings.notificationDeliveryMode == .digest {
                Section {
                    ForEach(session.settings.digestTimes.indices, id: \.self) { idx in
                        Stepper(
                            value: Binding(
                                get: { session.settings.digestTimes[idx] },
                                set: { value in
                                    Task {
                                        await session.updateSettings {
                                            var times = $0.digestTimes
                                            times[idx] = max(0, min(23, value))
                                        }
                                    }
                                }),
                            in: 0...23
                        ) {
                            Text("Digest \(idx + 1): \(session.settings.digestTimes[idx]):00")
                        }
                    }

                    Button {
                        Task {
                            await session.updateSettings { settings in
                                if settings.digestTimes.count < 4 {
                                    settings.digestTimes.append(
                                        (settings.digestTimes.last ?? 8) + 2)
                                }
                            }
                        }
                    } label: {
                        Label {
                            Text("Add digest time", comment: "Settings action")
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }
                    .disabled(session.settings.digestTimes.count >= 4)

                    if session.settings.digestTimes.count > 1 {
                        Button(role: .destructive) {
                            Task {
                                await session.updateSettings { settings in
                                    if settings.digestTimes.count > 1 {
                                        settings.digestTimes.removeLast()
                                    }
                                }
                            }
                        } label: {
                            Label {
                                Text("Remove last digest time", comment: "Settings action")
                            } icon: {
                                Image(systemName: "minus")
                            }
                        }
                    }
                } header: {
                    Text("Digest times", comment: "Settings section")
                } footer: {
                    Text(
                        "Notifications are grouped and delivered at these hours (local time). Direct messages and mentions from accounts you follow always come through immediately. Quiet hours override digest times.",
                        comment: "Digest times explanation")
                }
            }

            // Quiet hours (existing fields, now exposed)
            Section {
                HStack {
                    Text("Quiet hours start", comment: "Settings item")
                    Spacer()
                    Picker(
                        "",
                        selection: Binding(
                            get: { session.settings.quietHoursStart ?? 22 },
                            set: { value in
                                Task { await session.updateSettings { $0.quietHoursStart = value } }
                            })
                    ) {
                        ForEach(0..<24) { hour in
                            Text("\(hour):00").tag(hour)
                        }
                    }
                    .pickerStyle(.menu)
                }
                HStack {
                    Text("Quiet hours end", comment: "Settings item")
                    Spacer()
                    Picker(
                        "",
                        selection: Binding(
                            get: { session.settings.quietHoursEnd ?? 7 },
                            set: { value in
                                Task { await session.updateSettings { $0.quietHoursEnd = value } }
                            })
                    ) {
                        ForEach(0..<24) { hour in
                            Text("\(hour):00").tag(hour)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Quiet hours", comment: "Settings section")
            } footer: {
                Text(
                    "During quiet hours no notifications are delivered. Digest times that fall within quiet hours are skipped; the badge updates at the next digest time.",
                    comment: "Quiet hours explanation")
            }
        } header: {
            Text("Notifications", comment: "Settings section")
        } footer: {
            Text(
                "\"As they arrive\" is the default. \"In a digest\" batches notifications at your chosen hours; DMs and mentions from people you follow always break through.",
                comment: "Notifications section explanation")
        }
    }

    private func composerSection(_ session: AccountSession) -> some View {
        Section {
            Picker(
                selection: Binding(
                    get: { session.settings.defaultVisibility },
                    set: { value in
                        Task { await session.updateSettings { $0.defaultVisibility = value } }
                    })
            ) {
                Text("Public", comment: "Visibility").tag(Visibility.public)
                Text("Unlisted", comment: "Visibility").tag(Visibility.unlisted)
                Text("Followers only", comment: "Visibility").tag(Visibility.private)
            } label: {
                Text("Default visibility", comment: "Settings item")
            }

            Toggle(
                isOn: Binding(
                    get: { session.settings.warnAboutMissingAltText },
                    set: { value in
                        Task { await session.updateSettings { $0.warnAboutMissingAltText = value } }
                    })
            ) {
                Text("Warn about missing descriptions", comment: "Settings item")
            }
        } header: {
            Text("Posting", comment: "Settings section")
        }
    }

    @ViewBuilder
    private var intelligenceSection: some View {
        let availability = environment.intelligence.availability
        // Hidden entirely on an ineligible device; shown disabled with a reason
        // where the model exists but is not ready (docs/10 §2).
        if availability.shouldShowSettingsSection {
            Section {
                LabeledContent {
                    Text(
                        availability.isAvailable
                            ? String(localized: "On this device", comment: "Intelligence state")
                            : String(localized: "Unavailable", comment: "Intelligence state"))
                } label: {
                    Text("Writing help", comment: "Settings item")
                }
                .disabled(!availability.isAvailable)
            } header: {
                Text("Intelligence", comment: "Settings section")
            } footer: {
                if let explanation = availability.explanation {
                    Text(explanation)
                } else {
                    Text(
                        "These run entirely on this device. Nothing you write is sent to Aloha Social or anyone else.",
                        comment: "Intelligence privacy footnote")
                }
            }
        }
    }
}

extension SettingsView {
    /// A handle is not a sentence. Read aloud it should be words, not
    /// punctuation — "alice at cloud.example.test".
    fileprivate func accountLabel(_ session: AccountSession) -> Text {
        let handle = session.snapshot.qualifiedHandle
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .replacingOccurrences(of: "@", with: " at ")
        return Text(
            "\(session.snapshot.bestDisplayName), \(handle)",
            comment: "Accessibility label for an account row")
    }
}
