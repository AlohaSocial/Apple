// SPDX-License-Identifier: MIT

import AlohaNetwork
import AlohaStore
import Foundation
import Testing

@testable import AlohaUI

/// "Sign in again" goes back to the server the account signed in at, without
/// asking for the address, and still finds it if that address has moved.
@Suite("Signing in again")
@MainActor
struct SignInAgainTests {
    private func environment(_ server: MockAPIServer) -> AppEnvironment {
        AppEnvironment(
            container: StoreContainer.make(inMemory: true), transport: server,
            credentials: CredentialStore(inMemory: true))
    }

    @Test("The account's own API base is used as it is, not rediscovered")
    func usesTheRememberedBase() async throws {
        let server = MockAPIServer(configuration: .nextcloudSocialWithoutRewrite)
        let base = try #require(
            URL(string: "https://cloud.example.test/index.php/apps/social/"))
        let model = SignInModel()
        await model.resolveKnownServer(
            apiBase: base, host: "cloud.example.test", environment: environment(server))

        guard case .found(let outcome) = model.phase else {
            Issue.record("No server found at the remembered base: \(model.phase)")
            return
        }
        #expect(outcome.apiBase == base)
        #expect(outcome.winningCandidate.rank == 1)
    }

    @Test("A base that no longer answers falls back to discovery from the host")
    func fallsBackToDiscovery() async throws {
        let server = MockAPIServer(configuration: .nextcloudSocialWithRewrite)
        let gone = try #require(URL(string: "https://cloud.example.test/moved-away/"))
        let model = SignInModel()
        await model.resolveKnownServer(
            apiBase: gone, host: "cloud.example.test", environment: environment(server))

        guard case .found(let outcome) = model.phase else {
            Issue.record("Discovery did not run after the base failed: \(model.phase)")
            return
        }
        #expect(outcome.apiBase.host() == "cloud.example.test")
        #expect(outcome.apiBase != gone)
    }
}
