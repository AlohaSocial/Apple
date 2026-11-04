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
    private let totalBudget: Duration
    private let logger = Logger(subsystem: "social.aloha.app", category: "probe")

    public init(
        transport: any HTTPTransport = URLSessionTransport(),
        perCandidateTimeout: Duration = .seconds(5),
        totalBudget: Duration = .seconds(10)
    ) {
        self.transport = transport
        self.perCandidateTimeout = perCandidateTimeout
        self.totalBudget = totalBudget
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

            guard var scheme = components.scheme?.lowercased(),
                scheme == "http" || scheme == "https"
            else {
                return nil
            }

            if let port = components.port, !(1...65535).contains(port) { return nil }

            // Plain http only on the local network (docs/11 §5): a public
            // server is asked over https, which every one of them speaks,
            // rather than sent a password and a token anybody can read.
            var port = components.port
            if scheme == "http", !LocalNetwork.isLocal(host: host) {
                scheme = "https"
                if port == 80 { port = nil }
            }

            self.scheme = scheme
            self.host = host
            self.port = port
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

    /// What a probe task hands back: a candidate's answer, or the moment the
    /// whole probe's time ran out.
    private enum ProbeEvent: Sendable {
        case answered(Candidate, (base: URL, instance: InstanceDescription)?)
        case outOfTime
    }

    /// Probes all candidates concurrently and takes the lowest-ranked success.
    ///
    /// Total budget 10 seconds, per candidate 5, both enforced here rather
    /// than left to `URLRequest.timeoutInterval`: that is an idle timeout, so
    /// a server that trickles a byte every few seconds never trips it, and a
    /// transport other than URLSession does not read it at all. Sign-in waits
    /// for this, so a hanging server must not hang it. When the budget runs
    /// out, the best answer so far wins; with none, it is a failure that says
    /// what was tried.
    public func discover(_ address: ServerAddress) async throws -> Outcome {
        let candidates = Self.candidates(for: address)
        guard !candidates.isEmpty else { throw ProbeFailure.malformedAddress }

        let origin = address.origin
        async let nodeInfo = Self.within(perCandidateTimeout) {
            await self.fetchNodeInfo(origin: origin)
        }

        let perCandidate = perCandidateTimeout
        let budget = totalBudget
        let winner = await withTaskGroup(of: ProbeEvent.self) { group in
            for candidate in candidates {
                group.addTask {
                    let resolved = await Self.within(perCandidate) {
                        await self.resolveInstance(base: candidate.base)
                    }
                    return .answered(candidate, resolved)
                }
            }
            group.addTask {
                try? await Task.sleep(for: budget)
                return .outOfTime
            }

            var best: (Candidate, (base: URL, instance: InstanceDescription))?
            var outstanding = candidates.count
            for await event in group {
                guard case .answered(let candidate, let resolved) = event else {
                    // Out of time: whatever answered so far is the answer.
                    group.cancelAll()
                    break
                }
                outstanding -= 1
                if let resolved, best == nil || candidate.rank < best!.0.rank {
                    best = (candidate, resolved)
                }
                // Rank 1 cannot be beaten, and with every candidate heard
                // from there is nothing left to wait for.
                if best?.0.rank == 1 || outstanding == 0 {
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

        // Where the instance actually answered, which is the candidate's
        // own address unless the server redirected it somewhere else.
        return Outcome(
            apiBase: winner.1.base,
            instance: winner.1.instance,
            nodeInfo: await nodeInfo,
            winningCandidate: winner.0,
            attempted: candidates
        )
    }

    /// A candidate qualifies when it answers 200 **and** decodes as an Instance
    /// entity with a non-empty domain. A 200 that is a Nextcloud login page is
    /// not a Mastodon API.
    public func fetchInstance(base: URL) async -> InstanceDescription? {
        await resolveInstance(base: base)?.instance
    }

    /// The instance, and the API base that actually answered for it.
    ///
    /// URLSession follows redirects, so a 200 for a candidate may have come
    /// from somewhere else: `example.com` sending the client on to
    /// `social.example.com`, or `http://nas.local` to `https://nas.local`.
    /// The base is read back from where the answer came from, so the token
    /// request and every API call go there directly rather than through a
    /// redirect that drops the credential on the way.
    public func resolveInstance(base: URL) async -> (base: URL, instance: InstanceDescription)? {
        let v2Route = "api/v2/instance"
        if let answer: (value: InstancePayload.V2, url: URL) = await fetch(
            base.appending(path: v2Route)),
            let resolved = Self.base(answering: v2Route, at: answer.url, requested: base)
        {
            let described = InstanceDescription(v2: answer.value)
            if !described.domain.isEmpty { return (resolved, described) }
        }
        let v1Route = "api/v1/instance"
        if let answer: (value: InstancePayload.V1, url: URL) = await fetch(
            base.appending(path: v1Route + "/")),
            let resolved = Self.base(answering: v1Route, at: answer.url, requested: base)
        {
            let described = InstanceDescription(v1: answer.value)
            if !described.domain.isEmpty { return (resolved, described) }
        }
        return nil
    }

    /// The API base under which `route` was answered at `url`: the URL with
    /// the route taken off its end.
    ///
    /// Nil when a redirect also rewrote the route itself — nothing then says
    /// where the API lives — and when it took an https request to plain http
    /// on a public host, which sign-in never uses on its own (docs/11 §5).
    static func base(answering route: String, at url: URL, requested: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let host = components.host
        else { return nil }
        if components.scheme?.lowercased() == "http", requested.scheme?.lowercased() == "https",
            !LocalNetwork.isLocal(host: host)
        {
            return nil
        }
        var path = components.percentEncodedPath
        // A server may add or take off a trailing slash on the way.
        if path.hasSuffix("/") { path.removeLast() }
        let suffix = "/" + route
        guard path.hasSuffix(suffix) else { return nil }
        components.percentEncodedPath = String(path.dropLast(suffix.count)) + "/"
        components.percentEncodedQuery = nil
        components.fragment = nil
        return components.url
    }

    /// Runs `work`, giving up with nil once `limit` has passed. The work is
    /// cancelled, not left running, so a hanging request is not still holding
    /// a connection after the probe has moved on.
    static func within<T: Sendable>(
        _ limit: Duration, _ work: @escaping @Sendable () async -> T?
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
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
        await fetch(url)?.value
    }

    /// The decoded answer, and the URL it finally came from after redirects.
    private func fetch<T: Decodable & Sendable>(_ url: URL) async -> (value: T, url: URL)? {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Double(perCandidateTimeout.components.seconds)

        do {
            let (data, response) = try await transport.send(request)
            guard (200..<300).contains(response.statusCode) else { return nil }
            return (try AlohaJSON.decoder.decode(T.self, from: data), response.url ?? url)
        } catch {
            return nil
        }
    }
}

extension ServerProbe {
    /// How often a signed-in account may set off a fresh discovery.
    ///
    /// The trigger is the instance route failing at the stored API base,
    /// which is what an administrator adding or removing the rewrite looks
    /// like from here. Once an hour: often enough to follow a real move the
    /// same day, rarely enough that a server that is simply down is not
    /// probed at six candidate addresses on every refresh.
    public static let reprobeInterval: TimeInterval = 3600

    public static func mayReprobe(lastAttempt: Date?, now: Date = Date()) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= reprobeInterval
    }

    /// Whether a signed-in account may follow a re-probe to `found`.
    ///
    /// The account's token was issued by the server at `stored`, and every
    /// request carries it. A re-probe follows redirects, so it can end on
    /// another host — a misconfigured or hijacked redirect — and adopting
    /// that would hand the token to whoever answers there. Only a move on
    /// the same host is followed: a rewrite added or removed, a port, or
    /// plain http becoming https. Going the other way, to http, is not.
    public static func mayAdopt(apiBase found: URL, replacing stored: URL) -> Bool {
        guard let foundHost = found.host()?.lowercased(),
            foundHost == stored.host()?.lowercased()
        else { return false }
        return !(stored.scheme?.lowercased() == "https" && found.scheme?.lowercased() != "https")
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
