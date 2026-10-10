// SPDX-License-Identifier: MIT

import AlohaHTML
import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation
import OSLog
import Observation

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
    private let logger = Logger(subsystem: "com.nextcloud.alohasocial", category: "session")

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
            let stillSignedIn = (try? await client.decode(
                Account.self, from: Endpoint.session.verifyCredentials)
            ) != nil
            guard !stillSignedIn else { return }
            await markNeedsReauthentication()
        }
    }

    /// Adopts the server's own statement of this account's defaults, and
    /// latches the three capabilities that have nothing to announce them.
    public func refreshServerState() async {
        do {
            if let preferences = try? await client.decode(
                Preferences.self, from: Endpoint.instance.preferences)
            {
                await updateSettings { $0.adopt(preferences) }
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

    public func latchCapabilities(observing statuses: [Status]) async {
        var updated = snapshot.capabilities
        updated.latch(observing: statuses)
        guard updated != snapshot.capabilities else { return }
        await updateCapabilities(updated)
    }
}
