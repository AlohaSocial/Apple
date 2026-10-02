// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaNetwork

@Suite("Address normalisation")
struct ServerAddressTests {
    typealias Address = ServerProbe.ServerAddress

    @Test("Bare hosts, URLs, paths and handles all resolve to a host")
    func acceptedForms() throws {
        #expect(Address(typed: "cloud.example.com")?.host == "cloud.example.com")
        #expect(Address(typed: "https://cloud.example.com/")?.host == "cloud.example.com")
        #expect(Address(typed: "http://192.168.178.162/apps/social/")?.scheme == "http")
        #expect(Address(typed: "  CLOUD.Example.COM ")?.host == "cloud.example.com")
        #expect(Address(typed: "@alice@cloud.example.com")?.host == "cloud.example.com")
        #expect(Address(typed: "alice@cloud.example.com")?.host == "cloud.example.com")
    }

    @Test("A typed path is kept as a hint, not assumed")
    func pathHint() throws {
        let address = try #require(Address(typed: "cloud.example.com/nextcloud"))
        #expect(address.host == "cloud.example.com")
        #expect(address.pathHint == "nextcloud")
    }

    @Test("Nonsense and unsupported schemes are refused")
    func rejectedForms() {
        #expect(Address(typed: "") == nil)
        #expect(Address(typed: "not a host") == nil)
        #expect(Address(typed: "ftp://cloud.example.com") == nil)
    }
}

@Suite("API base candidates")
struct CandidateTests {

    @Test("The six candidates appear in the prescribed order")
    func candidateOrder() {
        let address = ServerProbe.ServerAddress(host: "cloud.example.com", pathHint: "nextcloud")
        let candidates = ServerProbe.candidates(for: address)
        let paths = candidates.map { $0.base.path() }

        #expect(paths[0] == "/")
        #expect(paths[1] == "/index.php/apps/social/")
        #expect(paths[2] == "/apps/social/")
        #expect(paths[3] == "/nextcloud/")
        #expect(paths[4] == "/nextcloud/index.php/apps/social/")
    }

    @Test("Without a path hint there are only three candidates")
    func candidatesWithoutHint() {
        let address = ServerProbe.ServerAddress(host: "mastodon.example")
        #expect(ServerProbe.candidates(for: address).count == 3)
    }

    @Test("Every candidate base ends in a slash so paths compose")
    func basesAreNormalised() {
        let address = ServerProbe.ServerAddress(host: "cloud.example.com")
        for candidate in ServerProbe.candidates(for: address) {
            #expect(candidate.base.absoluteString.hasSuffix("/"))
        }
    }
}

@Suite("Discovery against every server shape")
struct ProbeIntegrationTests {

    private func probe(_ configuration: MockAPIServer.Configuration) -> (ServerProbe, MockAPIServer)
    {
        let server = MockAPIServer(configuration: configuration)
        return (ServerProbe(transport: server), server)
    }

    @Test("A Nextcloud with the rewrite rules resolves to the root")
    func nextcloudWithRewrite() async throws {
        let (probe, _) = probe(.nextcloudSocialWithRewrite)
        let outcome = try await probe.discover(.init(host: "cloud.example.test"))

        #expect(outcome.apiBase.path() == "/")
        #expect(outcome.winningCandidate.rank == 1)
        #expect(outcome.instance.domain == "cloud.example.test")
        #expect(outcome.nodeInfo?.software.name == "Nextcloud Social")
    }

    /// The single most important test in the suite: this is the difference
    /// between the app working for a self-hoster and not (docs/12 §2).
    @Test("A Nextcloud WITHOUT the rewrite rules still resolves")
    func nextcloudWithoutRewrite() async throws {
        let (probe, _) = probe(.nextcloudSocialWithoutRewrite)
        let outcome = try await probe.discover(.init(host: "cloud.example.test"))

        #expect(outcome.apiBase.path() == "/index.php/apps/social/")
        #expect(outcome.winningCandidate.rank == 2)
        #expect(outcome.instance.domain == "cloud.example.test")
        // NodeInfo is served at the true root whatever the rewrite state, which
        // is what makes it usable as the cross-check.
        #expect(outcome.nodeInfo?.software.name == "Nextcloud Social")
    }

    @Test("Stock Mastodon resolves to the root and advertises streaming")
    func mastodon() async throws {
        let (probe, _) = probe(.mastodon43)
        let outcome = try await probe.discover(.init(host: "cloud.example.test"))

        #expect(outcome.apiBase.path() == "/")
        #expect(outcome.instance.hasStreaming)
        #expect(outcome.instance.hasWebPush)
        #expect(outcome.instance.limits.maxStatusCharacters == 500)
    }

    @Test("Nextcloud Social announces no streaming and no push, and says so")
    func nextcloudAnnouncesItsGaps() async throws {
        let (probe, _) = probe(.nextcloudSocialWithRewrite)
        let outcome = try await probe.discover(.init(host: "cloud.example.test"))

        // An empty urls object and an empty vapid key are deliberate signals,
        // not missing data (docs/02 §1).
        #expect(outcome.instance.hasStreaming == false)
        #expect(outcome.instance.hasWebPush == false)
        #expect(outcome.instance.limits.maxStatusCharacters == 5000)
        #expect(outcome.instance.mastodonAPIVersion == 3)
    }

    @Test("A host that answers nothing reports what was tried")
    func nothingAnswers() async {
        let server = MockAPIServer(
            configuration: .nextcloudSocialWithRewrite, host: "other.example")
        let probe = ServerProbe(transport: server)

        await #expect(throws: ServerProbe.ProbeFailure.self) {
            _ = try await probe.discover(.init(host: "cloud.example.test"))
        }
    }
}

@Suite("Capability detection")
struct CapabilityDetectionTests {

    private func detect(
        _ configuration: MockAPIServer.Configuration
    ) async throws -> ServerCapabilities {
        let server = MockAPIServer(configuration: configuration)
        let probe = ServerProbe(transport: server)
        let outcome = try await probe.discover(.init(host: "cloud.example.test"))
        let detector = CapabilityDetector(transport: server)
        return await detector.detect(
            apiBase: outcome.apiBase, accessToken: "token",
            instance: outcome.instance, nodeInfo: outcome.nodeInfo)
    }

    @Test("Nextcloud Social's extensions are found and its transport gaps honoured")
    func nextcloudCapabilities() async throws {
        let capabilities = try await detect(.nextcloudSocialWithoutRewrite)

        #expect(capabilities.isNextcloudSocial)
        #expect(capabilities.syncTier == .polling)
        #expect(capabilities.onlyVideoFilter)
        #expect(capabilities.onlyNewsFilter)
        #expect(capabilities.watchPositions)
        #expect(capabilities.stories)
        #expect(capabilities.collections)
        #expect(capabilities.mediaFromNextcloudFiles)
        #expect(capabilities.translation)
        #expect(capabilities.supports(.news))
    }

    @Test("Mastodon gets none of the extensions and News is hidden")
    func mastodonCapabilities() async throws {
        let capabilities = try await detect(.mastodon43)

        #expect(capabilities.isNextcloudSocial == false)
        #expect(capabilities.syncTier == .webPush)
        #expect(capabilities.onlyVideoFilter == false)
        #expect(capabilities.onlyNewsFilter == false)
        #expect(capabilities.watchPositions == false)
        #expect(capabilities.stories == false)
        #expect(capabilities.supports(.news) == false)
        // Every other mode still works: the app is usable with every flag off.
        #expect(capabilities.supports(.shorts))
    }

    @Test("A server that 404s the 4.x routes is treated as not having them")
    func unknownMeansAbsent() async throws {
        let capabilities = try await detect(.coreOnly)
        #expect(capabilities.groupedNotifications == false)
        #expect(capabilities.filtersV2 == false)
        #expect(capabilities.notificationPolicy == false)
    }

    @Test("hls_url, reactions and quotes latch on first sighting")
    func latching() {
        var capabilities = ServerCapabilities(apiBase: URL(string: "https://x.test/")!)
        #expect(capabilities.hlsLadder == false)

        let account = Account(id: "1", username: "a", acct: "a")
        let withLadder = Status(
            id: "1", account: account,
            mediaAttachments: [
                MediaAttachment(id: "m", type: .video, hlsURL: URL(string: "https://x.test/m.m3u8"))
            ])
        capabilities.latch(observing: [withLadder])
        #expect(capabilities.hlsLadder)
        #expect(capabilities.emojiReactions == false)
    }
}
