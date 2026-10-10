// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import OSLog

/// Finds where a server's Mastodon API actually lives.
///
/// Mastodon's client protocol has no way to be told about a non-root API base,
/// so every client builds `https://<host>/api/v1/…`. Nextcloud Social registers
/// its routes under the app prefix, and the rewrite rules that expose them at
/// the root are **administrator-configured**. Many instances will not have them.
///
/// This is the difference between "works with my Nextcloud" and "doesn't", and
/// it cannot be retrofitted (docs/03 §2, docs/13 Phase 1).
public struct ServerProbe: Sendable {
    private let transport: any HTTPTransport
    private let perCandidateTimeout: Duration
    private let logger = Logger(subsystem: "com.nextcloud.alohasocial", category: "probe")

    public init(
        transport: any HTTPTransport = URLSessionTransport(),
        perCandidateTimeout: Duration = .seconds(5)
    ) {
        self.transport = transport
        self.perCandidateTimeout = perCandidateTimeout
    }

    // MARK: - Input normalisation

    /// What a person typed, turned into a host and an optional path hint.
    ///
    /// Accepts `cloud.example.com`, `https://cloud.example.com/`,
    /// `cloud.example.com/nextcloud` and `@alice@cloud.example.com`.
    public struct ServerAddress: Sendable, Hashable {
        public var scheme: String
        public var host: String
        public var pathHint: String?
        /// The port as typed. `https://cloud.example` leaves it nil; a private
        /// network server is very often `http://192.168.1.20:8080`, and
        /// dropping the port silently rewrites the address to port 80.
        public var port: Int?

        public init?(typed raw: String) {
            var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            // A handle names a host: @alice@cloud.example -> cloud.example
            if text.hasPrefix("@") {
                let parts = text.dropFirst().split(separator: "@", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                text = String(parts[1])
            } else if !text.contains("://"), text.contains("@"), !text.contains("/") {
                let parts = text.split(separator: "@", maxSplits: 1)
                if parts.count == 2 { text = String(parts[1]) }
            }

            if !text.contains("://") { text = "https://" + text }
            guard let components = URLComponents(string: text),
                let host = components.host?.lowercased(),
                !host.isEmpty,
                host.contains(".") || host == "localhost"
            else { return nil }

            guard let scheme = components.scheme?.lowercased(),
                scheme == "http" || scheme == "https"
            else {
                return nil
            }

            if let port = components.port, !(1...65535).contains(port) { return nil }

            self.scheme = scheme
            self.host = host
            self.port = components.port
            let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            self.pathHint = path.isEmpty ? nil : path
        }

        public init(
            scheme: String = "https", host: String, pathHint: String? = nil, port: Int? = nil
        ) {
            self.scheme = scheme
            self.host = host
            self.pathHint = pathHint
            self.port = port
        }

        /// The address an already signed-in account is reached at, rebuilt
        /// from its stored API base.
        ///
        /// `instanceHost` is only ever a bare host — handles and `acct`
        /// strings are built from it — so the scheme and a port exist solely
        /// in the API base. Anything that re-derives an origin (a re-probe,
        /// a NodeInfo fetch) must read them from there rather than assume
        /// https, or a private-network http account can no longer be found.
        public init(apiBase: URL) {
            self.init(
                scheme: apiBase.scheme?.lowercased() ?? "https",
                host: (apiBase.host() ?? "").lowercased(),
                pathHint: nil,
                port: apiBase.port)
        }

        public var origin: String {
            if let port { return "\(scheme)://\(host):\(port)" }
            return "\(scheme)://\(host)"
        }
    }

    // MARK: - Candidates

    public struct Candidate: Sendable, Hashable, Identifiable {
        public var rank: Int
        public var base: URL
        public var explanation: String
        public var id: Int { rank }

        public init(rank: Int, base: URL, explanation: String) {
            self.rank = rank
            self.base = base
            self.explanation = explanation
        }
    }

    /// The six candidates, in the order docs/03 §2 prescribes.
    public static func candidates(for address: ServerAddress) -> [Candidate] {
        var result: [Candidate] = []

        func add(_ suffix: String, _ explanation: String) {
            let text = suffix.isEmpty ? address.origin + "/" : address.origin + "/" + suffix
            guard let url = URL(string: text) else { return }
            let normalised = url.normalisedAsAPIBase
            guard !result.contains(where: { $0.base == normalised }) else { return }
            result.append(
                Candidate(rank: result.count + 1, base: normalised, explanation: explanation))
        }

        add("", "the domain root")
        add("index.php/apps/social/", "Nextcloud Social, without the rewrite rules")
        add("apps/social/", "Nextcloud Social with pretty URLs, without the rewrite rules")

        if let hint = address.pathHint {
            add("\(hint)/", "the address you typed")
            add("\(hint)/index.php/apps/social/", "Nextcloud Social in a subdirectory")
        }

        return result
    }

    // MARK: - Result

    public struct Outcome: Sendable {
        public var apiBase: URL
        public var instance: InstanceDescription
        public var nodeInfo: NodeInfo?
        public var winningCandidate: Candidate
        public var attempted: [Candidate]

        public init(
            apiBase: URL, instance: InstanceDescription, nodeInfo: NodeInfo?,
            winningCandidate: Candidate, attempted: [Candidate]
        ) {
            self.apiBase = apiBase
            self.instance = instance
            self.nodeInfo = nodeInfo
            self.winningCandidate = winningCandidate
            self.attempted = attempted
        }
    }

    public enum ProbeFailure: Error, Sendable {
        /// Nothing answered. Carries what was tried so the sign-in sheet can say
        /// so in plain language rather than reading like a crash (docs/03 §2).
        case noCandidateAnswered(attempted: [Candidate])
        case malformedAddress
    }

    // MARK: - Probing

    /// Probes all candidates concurrently and takes the lowest-ranked success.
    /// Total budget 10 seconds; per candidate 5.
    public func discover(_ address: ServerAddress) async throws -> Outcome {
        let candidates = Self.candidates(for: address)
        guard !candidates.isEmpty else { throw ProbeFailure.malformedAddress }

        async let nodeInfo = fetchNodeInfo(origin: address.origin)

        let winner = await withTaskGroup(of: (Candidate, InstanceDescription)?.self) { group in
            for candidate in candidates {
                group.addTask {
                    guard let instance = await self.fetchInstance(base: candidate.base) else {
                        return nil
                    }
                    return (candidate, instance)
                }
            }

            var best: (Candidate, InstanceDescription)?
            for await result in group {
                guard let result else { continue }
                if best == nil || result.0.rank < best!.0.rank {
                    best = result
                }
                // Rank 1 cannot be beaten, so stop paying for the rest.
                if best?.0.rank == 1 {
                    group.cancelAll()
                    break
                }
            }
            return best
        }

        guard let winner else {
            throw ProbeFailure.noCandidateAnswered(attempted: candidates)
        }

        logger.info(
            "resolved API base via candidate \(winner.0.rank, privacy: .public): \(winner.0.explanation, privacy: .public)"
        )

        return Outcome(
            apiBase: winner.0.base,
            instance: winner.1,
            nodeInfo: await nodeInfo,
            winningCandidate: winner.0,
            attempted: candidates
        )
    }

    /// A candidate qualifies when it answers 200 **and** decodes as an Instance
    /// entity with a non-empty domain. A 200 that is a Nextcloud login page is
    /// not a Mastodon API.
    public func fetchInstance(base: URL) async -> InstanceDescription? {
        if let v2: InstancePayload.V2 = await get(base.appending(path: "api/v2/instance")) {
            let described = InstanceDescription(v2: v2)
            if !described.domain.isEmpty { return described }
        }
        if let v1: InstancePayload.V1 = await get(base.appending(path: "api/v1/instance/")) {
            let described = InstanceDescription(v1: v1)
            if !described.domain.isEmpty { return described }
        }
        return nil
    }

    /// NodeInfo is served at the **true domain root** on Nextcloud Social
    /// regardless of the rewrite, which is what makes it a usable cross-check.
    public func fetchNodeInfo(origin: String) async -> NodeInfo? {
        guard let root = URL(string: origin) else { return nil }
        if let info: NodeInfo = await get(root.appending(path: ".well-known/nodeinfo/2.1")) {
            return info
        }
        if let info: NodeInfo = await get(root.appending(path: ".well-known/nodeinfo/2.0")) {
            return info
        }
        // Some servers only publish the directory document.
        if let directory: NodeInfoDirectory = await get(
            root.appending(path: ".well-known/nodeinfo")),
            let href = directory.links.last(where: { $0.href != nil })?.href,
            let info: NodeInfo = await get(href)
        {
            return info
        }
        return nil
    }

    private func get<T: Decodable & Sendable>(_ url: URL) async -> T? {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Double(perCandidateTimeout.components.seconds)

        do {
            let (data, response) = try await transport.send(request)
            guard (200..<300).contains(response.statusCode) else { return nil }
            return try AlohaJSON.decoder.decode(T.self, from: data)
        } catch {
            return nil
        }
    }
}

extension ServerProbe {
    /// The snippet the failure UI copies, so a self-hoster can hand it to
    /// whoever runs the server. Straight from Nextcloud Social's PR #2250 —
    /// the rules proxy internally rather than redirect, because a redirect
    /// loses the `Authorization` header clients drop when following one.
    public static let webServerSnippet = """
        # Apache — serve the Mastodon client API at the domain root.
        # Internal proxy, not a redirect: a redirect loses the Authorization
        # header that clients drop when following one.
        RewriteEngine On
        RewriteRule ^/?api/(.*)$   /index.php/apps/social/api/$1   [PT,L,QSA]
        RewriteRule ^/?oauth/(.*)$ /index.php/apps/social/oauth/$1 [PT,L,QSA]

        # nginx
        location ^~ /api/   { rewrite ^/api/(.*)$   /index.php/apps/social/api/$1   last; }
        location ^~ /oauth/ { rewrite ^/oauth/(.*)$ /index.php/apps/social/oauth/$1 last; }
        """
}
