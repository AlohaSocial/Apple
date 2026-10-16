// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation
import Observation
import TVServices

@MainActor
@Observable
final class TVModel {
    private(set) var client: APIClient?
    private(set) var apiBase: URL?
    private(set) var home: [Status] = []
    private(set) var federated: [Status] = []
    private(set) var shorts: [Status] = []
    private(set) var continueWatching: [ContinueWatchingItem] = []
    private(set) var pendingAuthorisationURL: URL?
    private(set) var errorMessage: String?
    /// A video a Top Shelf item asked for, and where to start it.
    var presentedVideo: PresentedVideo?
    /// The colour of the signed-in server, read from Nextcloud's `theming`
    /// capability exactly as the phone reads it. `nil` leaves tvOS's own focus
    /// tint, which is also what a plain Mastodon gets.
    private(set) var serverTheme: AlohaThemeModifier.ServerTheme?

    private var capabilities: ServerCapabilities?
    private var registration: ClientRegistration?
    private var endpoints: OAuthService.Endpoints?
    private var verifier: String?
    /// The account lives in the app group and the shared Keychain group, so
    /// the Top Shelf extension can read it; a sign-in made by an older build
    /// is moved there on the first read. The phone is a different device and
    /// shares none of it.
    private let accounts = TVAccountStore()
    private var accountID: UUID?
    /// A link that arrived before the account was restored.
    private var pendingLink: TopShelfLink?

    struct PresentedVideo: Identifiable {
        var status: Status
        var position: Double?
        var id: String { status.id }
    }

    func restore() async {
        guard client == nil, let account = accounts.load(adoptingLegacy: true) else { return }

        apiBase = account.apiBase
        accountID = account.id
        client = APIClient(
            accountID: account.id, apiBase: account.apiBase, accessToken: account.token)
        if let pendingLink {
            self.pendingLink = nil
            await open(pendingLink)
        }
        await loadServerTheme()
    }

    /// A Top Shelf item: `alohasocial://tv/play/<id>` or `…/show/<id>`.
    func open(_ url: URL) async {
        guard let link = TopShelfLink(url: url) else { return }
        guard client != nil else {
            pendingLink = link
            return
        }
        await open(link)
    }

    private func open(_ link: TopShelfLink) async {
        guard let client,
            let status = try? await client.decode(
                Status.self, from: Endpoint.statuses.status(link.statusID))
        else { return }
        presentedVideo = PresentedVideo(status: status, position: link.position)
    }

    /// Public and unauthenticated, so it can run before anything else does;
    /// fetched per launch rather than stored, because a TV app launches rarely
    /// and an administrator may have changed the colour since.
    func loadServerTheme() async {
        guard let apiBase else { return }
        let root = ServerCapabilities.minimal(apiBase: apiBase).nextcloudRoot
        guard let theme = await NextcloudThemeProbe().theme(nextcloudRoot: root),
            theme.hasColour
        else {
            serverTheme = nil
            return
        }
        serverTheme = AlohaThemeModifier.ServerTheme(
            brightHex: theme.hex(onDarkBackground: false),
            darkHex: theme.hex(onDarkBackground: true),
            textHex: theme.textHex)
    }

    func beginSignIn(host: String) async {
        errorMessage = nil
        guard let address = ServerProbe.ServerAddress(typed: host) else {
            errorMessage = String(
                localized: "That doesn't look like a server address.", comment: "tvOS sign-in error"
            )
            return
        }

        do {
            let outcome = try await ServerProbe().discover(address)
            apiBase = outcome.apiBase

            let service = OAuthService()
            // The out-of-band redirect is what makes this possible at all:
            // tvOS has no web authentication session.
            let application = try await service.registerApplication(
                base: outcome.apiBase, redirectURI: OAuthService.outOfBandRedirectURI)
            guard let clientID = application.clientID,
                let clientSecret = application.clientSecret
            else { throw APIError.invalidResponse }

            let registration = ClientRegistration(
                host: outcome.instance.domain, clientID: clientID, clientSecret: clientSecret,
                redirectURI: OAuthService.outOfBandRedirectURI)
            self.registration = registration

            let endpoints = await service.discoverEndpoints(base: outcome.apiBase)
            self.endpoints = endpoints

            guard
                let request = service.makeAuthorisationRequest(
                    endpoints: endpoints, clientID: clientID,
                    redirectURI: OAuthService.outOfBandRedirectURI)
            else { throw APIError.invalidResponse }

            verifier = request.pkce.verifier
            pendingAuthorisationURL = request.url
        } catch {
            errorMessage = String(
                localized: "Couldn't reach that server.", comment: "tvOS sign-in error")
        }
    }

    func finishSignIn(code: String) async {
        guard let endpoints, let registration, let apiBase else { return }

        do {
            let token = try await OAuthService().exchange(
                code: code.trimmingCharacters(in: .whitespaces), endpoints: endpoints,
                clientID: registration.clientID, clientSecret: registration.clientSecret,
                redirectURI: OAuthService.outOfBandRedirectURI, verifier: verifier)

            let id = UUID()
            try accounts.save(TVAccount(id: id, apiBase: apiBase, token: token.accessToken))

            accountID = id
            client = APIClient(accountID: id, apiBase: apiBase, accessToken: token.accessToken)
            pendingAuthorisationURL = nil
            await loadServerTheme()
        } catch {
            errorMessage = String(
                localized: "That code didn't work. Try again.", comment: "tvOS sign-in error")
        }
    }

    func loadVideo() async {
        guard let client else { return }
        let filters = TimelineFilters(onlyVideo: true)

        home =
            (try? await client.decode(
                LossyArray<Status>.self,
                from: Endpoint.timelines.timeline(.home, filters: filters, limit: 20)))?
            .elements.filter(hasVideo) ?? []

        federated =
            (try? await client.decode(
                LossyArray<Status>.self,
                from: Endpoint.timelines.timeline(.federated, filters: filters, limit: 20)))?
            .elements.filter(hasVideo) ?? []

        continueWatching =
            (try? await client.decode(
                LossyArray<ContinueWatchingItem>.self,
                from: Endpoint.video.continueWatching()))?.elements ?? []

        updateTopShelf()
    }

    /// Hands the Top Shelf what this screen just loaded, and asks the system
    /// to redraw it only when that changed.
    private func updateTopShelf() {
        guard let accountID, let store = TopShelfSnapshotStore.shared else { return }
        let snapshot = TopShelfSnapshot.make(
            accountID: accountID, continueWatching: continueWatching, following: home)
        if (try? store.write(snapshot)) == true {
            TVTopShelfContentProvider.topShelfContentDidChange()
        }
    }

    func loadShorts() async {
        guard let client else { return }
        let page =
            (try? await client.decode(
                LossyArray<Status>.self,
                from: Endpoint.timelines.timeline(
                    .federated, filters: TimelineFilters(onlyVideo: true), limit: 40)))?.elements
            ?? []
        shorts = page.filter { ContentClassifier.classify($0) == .short }
    }

    private func hasVideo(_ status: Status) -> Bool {
        status.displayed.mediaAttachments.contains { $0.type == .video || $0.type == .gifv }
    }
}
