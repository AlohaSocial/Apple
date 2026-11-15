// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AuthenticationServices
import Foundation
import OSLog
import Observation

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

@MainActor
@Observable
public final class SignInModel {
    public enum Phase {
        case idle
        case probing
        case found(ServerProbe.Outcome)
        case authorising
        case failed(Failure)
    }

    public struct Failure {
        public var message: String
        public var attempted: [ServerProbe.Candidate]
        /// Only offered where the shape of the failure suggests a Nextcloud
        /// that has not had the rewrite rules applied.
        public var offersServerSnippet: Bool
        /// Where to finish setting the account up, when that is what is
        /// wrong: Aloha Social signs a Nextcloud user in, then asks them to
        /// choose a username in a browser first (`account-not-set-up`).
        public var setupURL: URL? = nil
    }

    public private(set) var phase: Phase = .idle
    public private(set) var currentCandidate: String?
    public var manualBase = ""

    private var outcome: ServerProbe.Outcome?
    private var typedHost = ""
    private let logger = Logger(subsystem: "social.aloha.app", category: "signin")

    /// A model that already knows where the account lives — the introduction
    /// probes the server before it hands over, so sign-in opens on the server
    /// card rather than asking for the address again.
    public init(preloaded: ServerProbe.Outcome? = nil) {
        guard let preloaded else { return }
        outcome = preloaded
        typedHost = preloaded.instance.domain
        phase = .found(preloaded)
    }

    /// Back to the address field, for "use a different server" or a fresh
    /// attempt from Settings → Add account.
    public func reset() {
        outcome = nil
        typedHost = ""
        currentCandidate = nil
        manualBase = ""
        phase = .idle
    }

    // MARK: - Probing

    public func probe(_ typed: String, environment: AppEnvironment) async {
        guard let address = ServerProbe.ServerAddress(typed: typed) else {
            phase = .failed(
                Failure(
                    message: String(
                        localized:
                            "That doesn't look like a server address. Try cloud.example.com, https://cloud.example.com or http://192.168.1.10.",
                        comment: "Sign-in validation failure"),
                    attempted: [], offersServerSnippet: false))
            return
        }

        typedHost = address.host
        phase = .probing
        currentCandidate = ServerProbe.candidates(for: address).first?.base.absoluteString

        let probe = ServerProbe(transport: environment.transport)
        do {
            let found = try await probe.discover(address)
            outcome = found
            phase = .found(found)
        } catch let failure as ServerProbe.ProbeFailure {
            switch failure {
            case .noCandidateAnswered(let attempted):
                phase = .failed(
                    Failure(
                        message: String(
                            localized:
                                "Couldn't find a Mastodon API at that address. If this is a Nextcloud, its administrator may still need to apply the web-server rules.",
                            comment: "Sign-in discovery failure"),
                        attempted: attempted,
                        offersServerSnippet: true))
            case .malformedAddress:
                phase = .failed(
                    Failure(
                        message: String(
                            localized: "That address couldn't be understood.",
                            comment: "Sign-in discovery failure"),
                        attempted: [], offersServerSnippet: false))
            }
        } catch {
            phase = .failed(
                Failure(
                    message: error.localizedDescription, attempted: [], offersServerSnippet: false))
        }
        currentCandidate = nil
    }

    /// Finds the server of an account that is already on this device, for
    /// signing it in again.
    ///
    /// The account remembers the API base it signed in at, which is a better
    /// answer than discovery: discovery could settle on another candidate,
    /// and a manual base from "Advanced" would not be found again at all. If
    /// that base no longer answers — the server moved — discovery from the
    /// host is the fallback, exactly as if the address had been typed.
    public func resolveKnownServer(
        apiBase: URL, host: String, environment: AppEnvironment
    ) async {
        typedHost = host
        phase = .probing
        currentCandidate = apiBase.absoluteString
        let probe = ServerProbe(transport: environment.transport)
        guard let resolved = await probe.resolveInstance(base: apiBase) else {
            await self.probe(host, environment: environment)
            return
        }
        let nodeInfo = await probe.fetchNodeInfo(origin: resolved.base.originString)
        let known = ServerProbe.Outcome(
            apiBase: resolved.base, instance: resolved.instance, nodeInfo: nodeInfo,
            winningCandidate: ServerProbe.Candidate(
                rank: 1, base: resolved.base,
                explanation: String(
                    localized: "the address this account signed in at",
                    comment: "Known candidate explanation")),
            attempted: [])
        currentCandidate = nil
        outcome = known
        phase = .found(known)
    }

    /// The documented-unsupported escape hatch for an unusual deployment.
    public func useManualBase(environment: AppEnvironment) async {
        guard var typed = URL(string: manualBase.trimmingCharacters(in: .whitespaces)) else {
            return
        }
        if !typed.absoluteString.hasSuffix("/") {
            typed = URL(string: typed.absoluteString + "/") ?? typed
        }

        phase = .probing
        let probe = ServerProbe(transport: environment.transport)
        // The base the instance answered under, not the one typed: a typed
        // address that redirects would otherwise sign in at the wrong host.
        guard let resolved = await probe.resolveInstance(base: typed) else {
            phase = .failed(
                Failure(
                    message: String(
                        localized: "Nothing answered at that address.",
                        comment: "Manual API base failure"),
                    attempted: [], offersServerSnippet: false))
            return
        }

        let (url, instance) = (resolved.base, resolved.instance)
        let nodeInfo = await probe.fetchNodeInfo(origin: url.originString)
        let manual = ServerProbe.Outcome(
            apiBase: url, instance: instance, nodeInfo: nodeInfo,
            winningCandidate: ServerProbe.Candidate(
                rank: 6, base: url,
                explanation: String(
                    localized: "the address you entered", comment: "Manual candidate explanation")),
            attempted: [])
        outcome = manual
        phase = .found(manual)
    }

    // MARK: - Authorising

    public func authorise(environment: AppEnvironment, onSuccess: @escaping () -> Void) async {
        guard let outcome else { return }
        phase = .authorising

        let service = OAuthService(transport: environment.transport)
        let host = outcome.instance.domain.isEmpty ? typedHost : outcome.instance.domain

        do {
            // The registration is cached per host and reused for every account
            // there — safe because Nextcloud Social moved authorisations to a
            // table of their own, so one app row holds many tokens.
            let registration: ClientRegistration
            if let cached = try environment.credentials.registration(forHost: host) {
                registration = cached
            } else {
                let application = try await service.registerApplication(base: outcome.apiBase)
                guard let clientID = application.clientID,
                    let clientSecret = application.clientSecret
                else { throw APIError.invalidResponse }

                registration = ClientRegistration(
                    host: host, clientID: clientID, clientSecret: clientSecret)
                try environment.credentials.setRegistration(registration)
            }

            let endpoints = await service.discoverEndpoints(base: outcome.apiBase)
            guard
                let request = service.makeAuthorisationRequest(
                    endpoints: endpoints, clientID: registration.clientID)
            else { throw APIError.invalidResponse }

            let callback = try await presentWebAuthentication(
                url: request.url, state: request.state)
            let code = try service.extractCode(from: callback, expectedState: request.state)

            let token = try await service.exchange(
                code: code, endpoints: endpoints, clientID: registration.clientID,
                clientSecret: registration.clientSecret,
                verifier: endpoints.supportsPKCE ? request.pkce.verifier : nil)

            let client = APIClient(
                accountID: UUID(), apiBase: outcome.apiBase,
                accessToken: token.accessToken, transport: environment.transport)
            let account = try await client.decode(
                Account.self, from: Endpoint.session.verifyCredentials)

            let detector = CapabilityDetector(transport: environment.transport)
            let capabilities = await detector.detect(
                apiBase: outcome.apiBase, accessToken: token.accessToken,
                instance: outcome.instance, nodeInfo: outcome.nodeInfo)

            _ = try await environment.addAccount(
                instanceHost: host, apiBase: outcome.apiBase, account: account,
                capabilities: capabilities, token: token.accessToken)

            onSuccess()
        } catch {
            logger.error("sign-in failed: \(String(describing: error), privacy: .public)")
            let apiError = error as? APIError
            let missingActor = apiError?.isMissingSocialActor == true
            phase = .failed(
                Failure(
                    message: missingActor
                        ? String(
                            localized:
                                "Your account isn't set up yet. Open Aloha Social in a web browser and choose your username.",
                            comment: "HTTP 403, account not set up")
                        : (apiError?.errorDescription
                            ?? String(
                                localized: "Signing in didn't finish.",
                                comment: "Sign-in authorisation failure")),
                    attempted: [], offersServerSnippet: false,
                    setupURL: missingActor
                        ? socialSetupURL(for: outcome)
                        : (apiError?.isAccountNotSetUp == true
                            ? (apiError?.accountSetupURL ?? socialSetupURL(for: outcome))
                            : nil)))
        }
    }

    /// The Social app's own address on this server, where a Nextcloud user
    /// chooses the username their actor gets.
    private func socialSetupURL(for outcome: ServerProbe.Outcome) -> URL? {
        if outcome.apiBase.path.contains("apps/social") { return outcome.apiBase }
        return URL(string: outcome.apiBase.originString)?
            .appending(path: "index.php/apps/social/")
    }

    private func presentWebAuthentication(url: URL, state: String) async throws -> URL {
        try await WebAuthenticator.shared.authenticate(url: url, state: state)
    }

    public func copyServerSnippet() {
        #if canImport(UIKit)
            UIPasteboard.general.string = ServerProbe.webServerSnippet
        #elseif canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(ServerProbe.webServerSnippet, forType: .string)
        #endif
    }
}
