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

    let accounts: AccountStore
    let timelines: TimelineStore
    let support: SupportStore

    private static let themeKey = "aloha.theme"
    private static let activeAccountKey = AppGroup.activeAccountKey
    private let logger = Logger(subsystem: "com.nextcloud.alohasocial", category: "environment")

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

    public var activeSession: AccountSession? {
        guard let activeAccountID else { return sessions.first }
        return sessions.first { $0.id == activeAccountID } ?? sessions.first
    }

    public var hasAccounts: Bool { !sessions.isEmpty }

    // MARK: - Lifecycle

    public func load() async {
        isLoading = true
        defer { isLoading = false }

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
            let connected = nextcloud != nil
            if connected, nextcloudRegistration(for: session.id) != nil {
                await session.setPushActive(true)
            }

            Task { await refreshCapabilitiesIfStale(session) }
            Task { await session.refreshServerState() }
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
        var shouldAsk = sessions.count == 1
        #if DEBUG
            if MockMode.isEnabled { shouldAsk = false }
        #endif
        if shouldAsk { Task { await notifier.requestAuthorisation() } }
        return session
    }

    /// Removing takes everything local with it — token, rows, cached media,
    /// drafts (docs/11 §2).
    public func removeAccount(_ id: UUID) async {
        guard let session = sessions.first(where: { $0.id == id }) else { return }

        await revokeToken(for: session)
        try? credentials.removeToken(for: id)
        try? await timelines.deleteEverything(forAccount: id)

        sessions.removeAll { $0.id == id }
        if activeAccountID == id {
            activeAccountID = sessions.first?.id
            if let activeAccountID {
                AppGroup.defaults.set(activeAccountID.uuidString, forKey: Self.activeAccountKey)
            } else {
                AppGroup.defaults.removeObject(forKey: Self.activeAccountKey)
            }
        }
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

        let nodeInfo = await probe.fetchNodeInfo(origin: "https://\(session.snapshot.instanceHost)")
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
        if let last = lastReprobe[session.id], now.timeIntervalSince(last) < 3600 { return }
        lastReprobe[session.id] = now

        let probe = ServerProbe(transport: transport)
        guard let address = ServerProbe.ServerAddress(typed: session.snapshot.instanceHost),
            let outcome = try? await probe.discover(address)
        else { return }

        guard outcome.apiBase != session.capabilities.apiBase else { return }
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
        if sessions.isEmpty { await load() }
        sync.attach(to: self)
        return await sync.performBackgroundRefresh()
    }
}
