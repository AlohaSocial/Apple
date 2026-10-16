// SPDX-License-Identifier: MIT

import AlohaHTML
import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation
import OSLog
import Observation
import Synchronization

/// One signed-in account's live services. Created and torn down with the
/// account — a signed-out account leaves no live object and no cached bytes.
@Observable
public final class AccountSession: Identifiable, @unchecked Sendable {
    public let id: UUID
    public private(set) var snapshot: AccountStore.Snapshot
    public let client: APIClient

    private let timelines: TimelineStore
    private let support: SupportStore
    private let accounts: AccountStore
    private let logger = Logger(subsystem: "social.aloha.app", category: "session")

    public init(
        snapshot: AccountStore.Snapshot,
        token: String?,
        transport: any HTTPTransport,
        timelines: TimelineStore,
        support: SupportStore,
        accounts: AccountStore
    ) {
        self.id = snapshot.id
        self.snapshot = snapshot
        self.timelines = timelines
        self.support = support
        self.accounts = accounts
        self.client = APIClient(
            accountID: snapshot.id,
            apiBase: snapshot.capabilities.apiBase,
            accessToken: token,
            transport: transport
        )
    }

    public var capabilities: ServerCapabilities { snapshot.capabilities }
    public var settings: AccountSettings { snapshot.settings }
    public var needsReauthentication: Bool { snapshot.needsReauthentication }

    /// Whether a Nextcloud app password has been granted for this account.
    /// Files browsing and push both depend on it.
    public private(set) var hasNextcloudConnection = false

    /// The status this account just posted. Timelines showing the account's own
    /// feed insert it at the top immediately — a post that only turns up after
    /// the next refresh, behind a "new posts" pill, reads as lost.
    public private(set) var lastPosted: Status?

    public func notePosted(_ status: Status) {
        lastPosted = status
    }

    /// Records whether a Nextcloud app password has been granted, and hands it
    /// to the client so the few `#[NoAdminRequired]` routes — deleting the
    /// Social account is the one that matters — can be reached at all. The
    /// Social OAuth token is not a Nextcloud session and those routes refuse
    /// it (docs/03 §5).
    public func setNextcloudConnection(_ credentials: NextcloudLoginFlow.Credentials?) async {
        hasNextcloudConnection = credentials != nil
        await client.updateNextcloudAuthorization(credentials?.basicAuthorization)
    }

    /// True once Nextcloud's proxy is delivering pushes for this account.
    /// The poller drops to a safety-net interval rather than stopping, because
    /// a push that never arrives should still be caught.
    public private(set) var isPushActive = false

    public func setPushActive(_ value: Bool) async {
        isPushActive = value
    }

    /// Set when the server said this Nextcloud user has not set up their
    /// Aloha Social account yet (`account-not-set-up`): where to finish, in a
    /// browser. A state, like re-authentication, rather than an error to show
    /// once and forget — every screen fails the same way until it is done.
    public private(set) var accountSetupURL: URL?
    /// Whether the server said so at all, with or without an address.
    public private(set) var needsAccountSetup = false

    /// Whether this account's server reads Bluesky for it. Learned by asking
    /// (`BlueskyAvailability.probe`); `.unknown` until then.
    public private(set) var bluesky: BlueskyAvailability = .unknown

    public func refreshBlueskyAvailability() async {
        guard capabilities.isNextcloudSocial else {
            bluesky = .off
            return
        }
        bluesky = await BlueskyAvailability.probe(client)
    }

    /// The server's notification delivery as last read, so a write sends the
    /// parts this app does not edit (the passthrough switches) back as they
    /// were rather than as defaults.
    var serverNotificationDelivery: NotificationDeliverySettings?

    public var visibleModes: [FeedMode] {
        settings.visibleModes(capabilities: capabilities)
    }

    // MARK: - Stores

    public var timelineStore: TimelineStore { timelines }
    public var supportStore: SupportStore { support }

    // MARK: - Mutation

    public func updateSettings(_ transform: @Sendable (inout AccountSettings) -> Void) async {
        var settings = snapshot.settings
        transform(&settings)
        snapshot.settings = settings
        try? await accounts.updateSettings(settings, for: id)
    }

    public func updateCapabilities(_ capabilities: ServerCapabilities) async {
        snapshot.capabilities = capabilities
        await client.updateAPIBase(capabilities.apiBase)
        try? await accounts.updateCapabilities(capabilities, for: id)
    }

    /// A revoked token stops polling and raises a banner. It never deletes the
    /// account or its cache (docs/02 §6).
    public func markNeedsReauthentication() async {
        guard !snapshot.needsReauthentication else { return }
        snapshot.needsReauthentication = true
        try? await accounts.setNeedsReauthentication(true, for: id)
        logger.notice("account marked as needing re-authentication")
    }

    public func handle(_ error: any Error) async {
        if let apiError = error as? APIError, apiError.isAccountNotSetUp {
            needsAccountSetup = true
            accountSetupURL = apiError.accountSetupURL ?? accountSetupURL
            return
        }
        if let apiError = error as? APIError, apiError.requiresReauthentication {
            // A 401 on one route is not a revoked token.
            //
            // Nextcloud Social's own routes — statistics, interests, channels,
            // memories — and anything behind a token scope answer 401 for
            // reasons that say nothing about the account. Marking the whole
            // account from one request's failure is how a person ends up being
            // told their sign-in expired on half the screens while they are
            // perfectly signed in.
            //
            // So verify against the one endpoint that is authoritative before
            // believing it: if the token still works, the 401 belonged to that
            // route and nothing else changes.
            guard await isTokenRefused() else { return }
            await markNeedsReauthentication()
        }
    }

    /// The check in flight, shared: ten screens failing at once ask once.
    /// Behind a lock because the failures arrive from wherever they happened.
    private let tokenCheck = Mutex<Task<Bool, Never>?>(nil)

    /// Whether `verify_credentials` itself says the token is no good.
    ///
    /// Only its own 401 counts. Offline, a timeout or a 5xx says nothing
    /// about the token, and treating any failure as "signed out" is how a
    /// person on a train is asked to sign in again.
    private func isTokenRefused() async -> Bool {
        let client = client
        let check = tokenCheck.withLock { slot in
            if let running = slot { return running }
            let started = Task<Bool, Never> {
                do {
                    _ = try await client.decode(
                        Account.self, from: Endpoint.session.verifyCredentials)
                    return false
                } catch let error as APIError {
                    return error.requiresReauthentication
                } catch {
                    return false
                }
            }
            slot = started
            return started
        }
        let refused = await check.value
        tokenCheck.withLock { slot in
            if slot == check { slot = nil }
        }
        return refused
    }

    /// Adopts the server's own statement of this account's defaults, and
    /// latches the three capabilities that have nothing to announce them.
    public func refreshServerState() async {
        await refreshProfile()
        do {
            if let preferences = try? await client.decode(
                Preferences.self, from: Endpoint.instance.preferences)
            {
                await updateSettings { $0.adopt(preferences) }
                // An answer at all means the account exists now.
                needsAccountSetup = false
                accountSetupURL = nil
            }
            if capabilities.isNextcloudSocial {
                await adoptServerReaderSettings()
            }
            if capabilities.filtersV2 {
                let filters = try await client.decode(
                    LossyArray<Filter>.self, from: Endpoint.filters.all)
                try await support.replaceFilters(filters.elements, accountID: id)
            }
        } catch {
            await handle(error)
        }
    }

    /// The account as the server has it now: a handle, a name or an avatar
    /// changed on the web would otherwise stay as they were at sign-in.
    func refreshProfile() async {
        guard
            let account = try? await client.decode(
                Account.self, from: Endpoint.session.verifyCredentials)
        else { return }
        adoptProfile(account)
        try? await accounts.updateProfile(account, for: id)
    }

    /// The profile fields of the snapshot, as `account` has them.
    func adoptProfile(_ account: Account) {
        snapshot.handle = account.acct
        snapshot.displayName = account.bestDisplayName
        snapshot.avatarURL = account.preferredAvatarURL
        snapshot.headerURL = account.preferredHeaderURL
    }

    /// Back to signed in, after a fresh sign-in to this same account.
    func clearNeedsReauthentication() async {
        guard snapshot.needsReauthentication else { return }
        snapshot.needsReauthentication = false
        try? await accounts.setNeedsReauthentication(false, for: id)
    }

    public func latchCapabilities(observing statuses: [Status]) async {
        var updated = snapshot.capabilities
        updated.latch(observing: statuses)
        guard updated != snapshot.capabilities else { return }
        await updateCapabilities(updated)
    }
}
