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
    }

    public private(set) var phase: Phase = .idle
    public private(set) var currentCandidate: String?
    public var manualBase = ""

    private var outcome: ServerProbe.Outcome?
    private var typedHost = ""
    private let logger = Logger(subsystem: "com.nextcloud.alohasocial", category: "signin")

    public init() {}

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

    /// The documented-unsupported escape hatch for an unusual deployment.
    public func useManualBase(environment: AppEnvironment) async {
        guard var url = URL(string: manualBase.trimmingCharacters(in: .whitespaces)) else { return }
        if !url.absoluteString.hasSuffix("/") {
            url = URL(string: url.absoluteString + "/") ?? url
        }

        phase = .probing
        let probe = ServerProbe(transport: environment.transport)
        guard let instance = await probe.fetchInstance(base: url) else {
            phase = .failed(
                Failure(
                    message: String(
                        localized: "Nothing answered at that address.",
                        comment: "Manual API base failure"),
                    attempted: [], offersServerSnippet: false))
            return
        }

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
            phase = .failed(
                Failure(
                    message: (error as? APIError)?.errorDescription
                        ?? String(
                            localized: "Signing in didn't finish.",
                            comment: "Sign-in authorisation failure"),
                    attempted: [], offersServerSnippet: false))
        }
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
