// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import Foundation
import Observation

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

    private var capabilities: ServerCapabilities?
    private var registration: ClientRegistration?
    private var endpoints: OAuthService.Endpoints?
    private var verifier: String?
    /// Its own keychain, deliberately: the TV app is a separate application
    /// with its own bundle id, so it shares no access group with the phone.
    private let credentials = CredentialStore()
    private let accountKey = "aloha.tv.account"

    func restore() async {
        guard let raw = UserDefaults.standard.string(forKey: accountKey),
            let id = UUID(uuidString: raw),
            let token = (try? credentials.token(for: id)) ?? nil,
            let base = UserDefaults.standard.url(forKey: "aloha.tv.apiBase")
        else { return }

        apiBase = base
        client = APIClient(accountID: id, apiBase: base, accessToken: token)
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
            try credentials.setToken(token.accessToken, for: id)
            UserDefaults.standard.set(id.uuidString, forKey: accountKey)
            UserDefaults.standard.set(apiBase, forKey: "aloha.tv.apiBase")

            client = APIClient(accountID: id, apiBase: apiBase, accessToken: token.accessToken)
            pendingAuthorisationURL = nil
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
