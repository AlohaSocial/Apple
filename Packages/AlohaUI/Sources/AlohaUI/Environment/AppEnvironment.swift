// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaIntelligence
import AlohaMedia
import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation
import OSLog
import Observation
import SwiftData

/// The composition root. Owns the account list, the active account, the theme
/// and the shared services, and is injected through the SwiftUI environment.
@MainActor
@Observable
public final class AppEnvironment {
    public private(set) var sessions: [AccountSession] = []
    public private(set) var activeAccountID: UUID?
    public private(set) var isLoading = true

    public var theme: AlohaTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey) }
    }
    public var metrics: AlohaMetrics

    public let container: ModelContainer
    public let credentials: CredentialStore
    public let intelligence: any IntelligenceProviding
    public let transport: any HTTPTransport
    public let sync: SyncEngine
    public let notifier: LocalNotifier
    /// Posts written while the server was out of reach (docs/07 §7).
    public let sendQueue = SendQueue()

    let accounts: AccountStore
    let timelines: TimelineStore
    let support: SupportStore

    private static let themeKey = "aloha.theme"
    private static let activeAccountKey = AppGroup.activeAccountKey
    private let logger = Logger(subsystem: "social.aloha.app", category: "environment")

    public init(
        container: ModelContainer,
        transport: any HTTPTransport = URLSessionTransport(),
        credentials: CredentialStore = .shared,
        intelligence: any IntelligenceProviding = OnDeviceIntelligence()
    ) {
        self.container = container
        self.transport = transport
        self.credentials = credentials
        self.intelligence = intelligence
        self.accounts = AccountStore(modelContainer: container)
        self.timelines = TimelineStore(modelContainer: container)
        self.support = SupportStore(modelContainer: container)

        self.notifier = LocalNotifier()
        self.sync = SyncEngine(notifier: notifier)

        let stored = UserDefaults.standard.string(forKey: Self.themeKey)
        self.theme = stored.flatMap(AlohaTheme.init(rawValue:)) ?? .system
        self.metrics = AlohaMetrics()
        // An intent run in this process uses these sessions rather than
        // opening the store a second time.
        IntentContext.live = self
    }

    /// The colour the app wears: the active account's Nextcloud, as its
    /// `theming` capability reports it.
    ///
    /// Not a preference. An administrator who has themed their Nextcloud has
    /// already chosen the colour their people know that server by, and asking
    /// the same question again in here gets two answers to it. `nil` on a plain
    /// Mastodon and on a Nextcloud with the Theming app off, which leaves the
    /// app's own accent in place (docs/05 §2).
    public var serverAccent: AlohaThemeModifier.ServerTheme? {
        guard let theme = activeSession?.capabilities.theme, theme.hasColour else { return nil }
        return AlohaThemeModifier.ServerTheme(
            brightHex: theme.hex(onDarkBackground: false),
            darkHex: theme.hex(onDarkBackground: true),
            textHex: theme.textHex)
    }

    /// What the watch needs to follow the active account, or `nil` when there
    /// is none. A function rather than a property because it reads the
    /// Keychain, which a view body should not do on every pass.
    public func watchPairing() -> WatchPairing? {
        guard let session = activeSession,
            let token = (try? credentials.token(for: session.id)) ?? nil
        else { return nil }
        let accent = serverAccent
        return WatchPairing(
            accountID: session.id, apiBase: session.snapshot.apiBase, token: token,
            handle: session.snapshot.qualifiedHandle,
            accentBrightHex: accent?.brightHex, accentDarkHex: accent?.darkHex,
            accentTextHex: accent?.textHex)
    }

    public var activeSession: AccountSession? {
        guard let activeAccountID else { return sessions.first }
        return sessions.first { $0.id == activeAccountID } ?? sessions.first
    }

    public var hasAccounts: Bool { !sessions.isEmpty }

    // MARK: - Lifecycle

    /// The first load, shared by everyone who needs the accounts before the
    /// window has asked for them: a notification action answered from the
    /// lock screen launches the app in the background, and arrives before the
    /// shell's own load — or while it is still running.
    private var initialLoad: Task<Void, Never>?

    /// Loads the accounts once; later callers wait for the same load rather
    /// than starting a second one that would replace the sessions under them.
    public func loadIfNeeded() async {
        if let initialLoad {
            await initialLoad.value
            return
        }
        let task = Task { await load() }
        initialLoad = task
        await task.value
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        // Before the first read of the active account: a build that kept it
        // in the app's own defaults would otherwise open on the wrong one.
        AppGroup.adoptStandardDefaultsIfNeeded()

        do {
            let snapshots = try await accounts.allAccounts()
            sessions = snapshots.map(makeSession)

            let storedActive = AppGroup.defaults.string(forKey: Self.activeAccountKey)
                .flatMap(UUID.init(uuidString:))
            activeAccountID =
                snapshots.contains { $0.id == storedActive } ? storedActive : snapshots.first?.id
        } catch {
            logger.error("failed to load accounts: \(String(describing: error), privacy: .public)")
            sessions = []
        }

        // Capabilities refresh on launch and every 24 h, and never block the
        // first paint.
        for session in sessions {
            // A connected Nextcloud is remembered in the Keychain; the flag is
            // derived from it rather than stored twice.
            let nextcloud = (try? credentials.nextcloudCredentials(for: session.id)) ?? nil
            await session.setNextcloudConnection(nextcloud)
            if let nextcloud, nextcloud.userID == nil {
                Task { await completeNextcloudUserID(nextcloud, for: session) }
            }
            let connected = nextcloud != nil
            if connected, nextcloudRegistration(for: session.id) != nil {
                await session.setPushActive(true)
            }

            Task { await refreshCapabilitiesIfStale(session) }
            Task { await session.refreshServerState() }
            if !session.needsReauthentication {
                Task(priority: .background) { await SpotlightIndexer.refreshIfStale(session) }
            }
        }
    }

    private func makeSession(_ snapshot: AccountStore.Snapshot) -> AccountSession {
        AccountSession(
            snapshot: snapshot,
            token: try? credentials.token(for: snapshot.id),
            transport: transport,
            timelines: timelines,
            support: support,
            accounts: accounts
        )
    }

    /// Switching is instantaneous: the new account's cached timeline paints
    /// before any network call (docs/03 §6).
    public func setActiveAccount(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        activeAccountID = id
        AppGroup.defaults.set(id.uuidString, forKey: Self.activeAccountKey)
    }

    // MARK: - Adding and removing

    @discardableResult
    public func addAccount(
        instanceHost: String,
        apiBase: URL,
        account: Account,
        capabilities: ServerCapabilities,
        token: String
    ) async throws -> AccountSession {
        if let existing = existingSession(instanceHost: instanceHost, serverAccountID: account.id) {
            return try await signInAgain(existing, account: account, token: token)
        }
        let id = UUID()
        try credentials.setToken(token, for: id)

        let snapshot = try await accounts.addAccount(
            id: id, instanceHost: instanceHost, apiBase: apiBase,
            account: account, capabilities: capabilities)

        let session = makeSession(snapshot)
        sessions.append(session)
        setActiveAccount(session.id)

        Task { await session.refreshServerState() }
        // The first account is the moment notifications become meaningful.
        // Only the app asks: an extension has no prompt to show, and outside
        // an app bundle the notification centre does not exist at all.
        var shouldAsk = sessions.count == 1 && Bundle.main.bundleURL.pathExtension == "app"
        #if DEBUG
            if MockMode.isEnabled { shouldAsk = false }
        #endif
        if shouldAsk { Task { await notifier.requestAuthorisation() } }
        return session
    }

    /// The account already signed in on this server as this person, if any:
    /// signing in to it again is a new token for it, not a second account.
    func existingSession(instanceHost: String, serverAccountID: String) -> AccountSession? {
        sessions.first {
            $0.snapshot.instanceHost.lowercased() == instanceHost.lowercased()
                && $0.snapshot.serverAccountID == serverAccountID
        }
    }

    /// A fresh sign-in to an account that is already here — the usual answer
    /// to "your sign-in expired". It keeps its id, so its drafts, its queue
    /// and its cache stay its own, and only the token and the flag change.
    private func signInAgain(
        _ session: AccountSession, account: Account, token: String
    ) async throws -> AccountSession {
        try credentials.setToken(token, for: session.id)
        try? await accounts.setNeedsReauthentication(false, for: session.id)
        try? await accounts.updateProfile(account, for: session.id)

        // The client holds the old token; a session built from the stored
        // row picks up the new one.
        let snapshot = (try? await accounts.account(id: session.id)) ?? session.snapshot
        let renewed = makeSession(snapshot)
        let nextcloud = (try? credentials.nextcloudCredentials(for: session.id)) ?? nil
        await renewed.setNextcloudConnection(nextcloud)
        await renewed.setPushActive(session.isPushActive)
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = renewed
        }
        ReadingSignals.forget(session.id)
        setActiveAccount(renewed.id)
        Task { await renewed.refreshServerState() }
        return renewed
    }

    /// Removing takes everything with it — token, app password, push, rows,
    /// cached responses, drafts, snapshots (docs/11 §2) — in an order that
    /// cannot leave half an account behind.
    ///
    /// The account's rows go first. If they cannot be deleted nothing else is
    /// touched and `false` comes back: an account whose token was thrown
    /// away but whose row remains is a dead entry that can neither post nor
    /// be removed. Once the rows are gone, everything after is best effort
    /// and runs to the end whatever fails.
    ///
    /// Before anything, polling and streaming for it stop: a poll that
    /// finished after the rows were deleted wrote them back, for an account
    /// that no longer exists.
    @discardableResult
    public func removeAccount(_ id: UUID) async -> Bool {
        guard let session = sessions.first(where: { $0.id == id }) else { return false }

        await sync.forget(id)

        do {
            try await timelines.deleteEverything(forAccount: id)
        } catch {
            logger.error(
                "could not delete the account's rows: \(String(describing: error), privacy: .public)"
            )
            sync.readmit(id)
            return false
        }

        // The server and the push proxy, while the secrets they need exist.
        await unregisterNextcloudPush(session: session)
        await revokeToken(for: session)

        // The secrets.
        try? credentials.removeToken(for: id)
        try? credentials.removeNextcloudCredentials(for: id)
        try? credentials.removePushKeys(for: id)
        let host = session.snapshot.instanceHost
        let others = sessions.filter { $0.id != id }
        if !others.contains(where: { $0.snapshot.instanceHost.lowercased() == host.lowercased() }) {
            // The app's registration with that server, which no other
            // account here uses any more.
            try? credentials.removeRegistration(forHost: host)
        }

        // What the extensions and the system hold for it.
        AccountTeardown.removeSharedState(for: id, in: AppGroup.defaults)
        await SpotlightIndexer.removeEverything(for: id)
        ReadingSignals.forget(id)
        // Responses were cached under this account's token; they are not
        // keyed by account, so the cache goes as a whole.
        transport.removeCachedResponses()

        sessions.removeAll { $0.id == id }
        if activeAccountID == id {
            activeAccountID = sessions.first?.id
            if let activeAccountID {
                AppGroup.defaults.set(activeAccountID.uuidString, forKey: Self.activeAccountKey)
            } else {
                AppGroup.defaults.removeObject(forKey: Self.activeAccountKey)
            }
        }
        return true
    }

    /// A revocation failure does not block local sign-out.
    private func revokeToken(for session: AccountSession) async {
        guard let token = try? credentials.token(for: session.id),
            let registration = try? credentials.registration(forHost: session.snapshot.instanceHost)
        else { return }

        let service = OAuthService(transport: transport)
        let endpoints = await service.discoverEndpoints(base: session.capabilities.apiBase)
        try? await service.revoke(
            token: token, endpoints: endpoints,
            clientID: registration.clientID, clientSecret: registration.clientSecret)
    }

    // MARK: - Capabilities

    private func refreshCapabilitiesIfStale(_ session: AccountSession) async {
        guard session.capabilities.isStale() else { return }

        let probe = ServerProbe(transport: transport)
        guard let instance = await probe.fetchInstance(base: session.capabilities.apiBase) else {
            // A 404 where a route should exist may mean an administrator added
            // or removed the rewrite; re-probe, at most once an hour.
            await reprobeAPIBase(session)
            return
        }

        let nodeInfo = await probe.fetchNodeInfo(
            origin: session.capabilities.apiBase.originString)
        let detector = CapabilityDetector(transport: transport)
        let token = try? credentials.token(for: session.id)
        let capabilities = await detector.detect(
            apiBase: session.capabilities.apiBase, accessToken: token,
            instance: instance, nodeInfo: nodeInfo)

        await session.updateCapabilities(capabilities)
    }

    private var lastReprobe: [UUID: Date] = [:]

    private func reprobeAPIBase(_ session: AccountSession) async {
        let now = Date()
        guard ServerProbe.mayReprobe(lastAttempt: lastReprobe[session.id], now: now) else {
            return
        }
        lastReprobe[session.id] = now

        let probe = ServerProbe(transport: transport)
        // The address is rebuilt from the stored API base rather than from the
        // bare host: only the API base carries the scheme and the port, and a
        // private-network http account must be found again over http.
        let address = ServerProbe.ServerAddress(
            apiBase: session.capabilities.apiBase)
        guard let outcome = try? await probe.discover(address)
        else { return }

        guard outcome.apiBase != session.capabilities.apiBase else { return }
        guard
            ServerProbe.mayAdopt(
                apiBase: outcome.apiBase, replacing: session.capabilities.apiBase)
        else {
            logger.notice("API base answered from another host; keeping the stored one")
            return
        }
        logger.notice("API base moved; adopting the new one")

        var capabilities = session.capabilities
        capabilities.apiBase = outcome.apiBase
        await session.updateCapabilities(capabilities)
    }

    // MARK: - Maintenance

    public func sweepCaches() async {
        try? await timelines.sweep()
        await ImageLoader.shared.evictDiskCacheIfNeeded()
    }

    // MARK: - Nextcloud push

    /// The APNs token, handed over by the app delegate.
    public private(set) var deviceToken: Data?

    public func setDeviceToken(_ token: Data) async {
        deviceToken = token
        for session in sessions where session.hasNextcloudConnection {
            await registerForNextcloudPush(session: session)
        }
    }

    /// A connection made before the user ID was asked for learns it once, so
    /// Files is browsed under the right name where it is not the login name.
    /// Written back only if the connection is still the one asked about: a
    /// disconnect while the request was out must stay a disconnect.
    private func completeNextcloudUserID(
        _ nextcloud: NextcloudLoginFlow.Credentials, for session: AccountSession
    ) async {
        let flow = NextcloudLoginFlow(transport: transport)
        guard let userID = await flow.userID(for: nextcloud),
            let current = (try? credentials.nextcloudCredentials(for: session.id)) ?? nil,
            current == nextcloud
        else { return }
        var completed = current
        completed.userID = userID
        try? credentials.setNextcloudCredentials(completed, for: session.id)
        await session.setNextcloudConnection(completed)
    }

    /// Registers through **Nextcloud's own push proxy**, which is what the
    /// official client uses. Social serves no Web Push of its own, but the
    /// Nextcloud underneath it does — so where the person has connected it,
    /// this is a real push path and polling can stand down (docs/08 §6).
    public func registerForNextcloudPush(session: AccountSession) async {
        guard let deviceToken,
            let credentials = (try? credentials.nextcloudCredentials(for: session.id)) ?? nil
        else { return }

        let keys: NextcloudPushKeys
        if let existing = nextcloudPushKeys(for: session.id) {
            keys = existing
        } else {
            guard let generated = try? NextcloudPushKeys.generate() else { return }
            keys = generated
            storeNextcloudPushKeys(generated, for: session.id)
        }

        do {
            let registration = try await NextcloudPush(transport: transport).subscribe(
                credentials: credentials, deviceToken: deviceToken, keys: keys)
            storeNextcloudRegistration(registration, for: session.id)
            await session.setPushActive(true)
            logger.info("nextcloud push active for an account")
        } catch NextcloudPush.PushError.notificationsAppUnavailable {
            // A Nextcloud without the notifications app. Polling continues.
            logger.notice("nextcloud has no notifications app; polling continues")
        } catch {
            logger.error(
                "nextcloud push registration failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    public func unregisterNextcloudPush(session: AccountSession) async {
        guard let credentials = (try? credentials.nextcloudCredentials(for: session.id)) ?? nil,
            let registration = nextcloudRegistration(for: session.id)
        else { return }

        await NextcloudPush(transport: transport).unsubscribe(
            credentials: credentials, registration: registration)
        removeNextcloudPushState(for: session.id)
        await session.setPushActive(false)
    }

    // Stored in the Keychain beside the token, under the same accessibility
    // class: a push key that syncs is a push key another device can read.
    func nextcloudPushKeys(for accountID: UUID) -> NextcloudPushKeys? {
        guard let raw = (try? credentials.pushKeys(for: accountID)) ?? nil,
            let data = raw.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(NextcloudPushKeys.self, from: data)
    }

    private func storeNextcloudPushKeys(_ keys: NextcloudPushKeys, for accountID: UUID) {
        guard let data = try? JSONEncoder().encode(keys),
            let raw = String(data: data, encoding: .utf8)
        else { return }
        try? credentials.setPushKeys(raw, for: accountID)
    }

    func nextcloudRegistration(for accountID: UUID) -> NextcloudPush.Registration? {
        guard
            let data = AppGroup.defaults.data(
                forKey: "aloha.ncPush.\(accountID.uuidString)")
        else { return nil }
        return try? JSONDecoder().decode(NextcloudPush.Registration.self, from: data)
    }

    private func storeNextcloudRegistration(
        _ registration: NextcloudPush.Registration, for accountID: UUID
    ) {
        guard let data = try? JSONEncoder().encode(registration) else { return }
        AppGroup.defaults.set(data, forKey: "aloha.ncPush.\(accountID.uuidString)")
    }

    private func removeNextcloudPushState(for accountID: UUID) {
        try? credentials.removePushKeys(for: accountID)
        AppGroup.defaults.removeObject(forKey: "aloha.ncPush.\(accountID.uuidString)")
    }

    /// Entry point for `BGAppRefreshTask`.
    public func performBackgroundRefresh() async -> Int {
        await loadIfNeeded()
        sync.attach(to: self)
        // A post waiting for the network is worth more than a badge: send it
        // first, while the refresh still has its time.
        sendQueue.attach(to: self)
        await sendQueue.drainAll()
        let fresh = await sync.performBackgroundRefresh()
        // A new day can begin while the app sleeps; the Memories widget
        // should not wait for the app to be opened to turn it over.
        if let activeSession { await MemoriesWidgetWriter.refreshIfStale(activeSession) }
        return fresh
    }
}
