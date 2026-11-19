// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Observation

/// Opens a link to a fediverse post or profile inside the app.
///
/// A link in a post to `https://other.server/@bob/1234` is a post the reader
/// could reply to, boost and favourite — but only through their own server.
/// So the link is looked up there (`GET /api/v2/search?q=<url>&resolve=true`)
/// and, when the server finds it, the thread or profile is pushed with the
/// reader's relationship state and working buttons (docs/09 §10). Anything
/// else — not a fediverse address, nothing found, a server too slow to say —
/// opens in the browser as every link did before.
@MainActor
@Observable
final class FediverseLinkResolver {
    /// How the server's search is asked. A closure rather than an
    /// `APIClient`, so the decisions can be tested without a network.
    typealias Search = @Sendable (URL) async throws -> SearchResults

    /// What one lookup came to.
    enum Lookup: Equatable, Sendable {
        /// The server knows the post or the account: open it here.
        case found(Route)
        /// The server answered and found nothing that is this link.
        case nothingThere
        /// No answer: an error, or none within `timeout`.
        case failed
    }

    /// The link being looked up, while the reader waits for it.
    private(set) var pending: URL?

    /// How long a tap waits before the browser takes over. A link is a
    /// promise of something now; a server that takes longer than this to
    /// fetch a remote post would make every tap feel broken.
    @ObservationIgnored let timeout: Duration

    /// What each account's server said about each link, for as long as the
    /// app runs: a second tap opens at once. "Nothing there" is kept too, so
    /// a web page is only ever waited on once; a failure is not, because the
    /// next tap may well succeed.
    @ObservationIgnored private var answers: [Key: Route?] = [:]
    @ObservationIgnored private var work: Task<Void, Never>?

    private struct Key: Hashable {
        let accountID: UUID
        let link: String
    }

    init(timeout: Duration = .seconds(4)) {
        self.timeout = timeout
    }

    /// Opens `url` in the app when it can, and hands it to `fallback`
    /// otherwise. A second tap while one is pending replaces it.
    func open(
        _ url: URL, accountID: UUID, search: @escaping Search,
        onRoute: @escaping @MainActor (Route) -> Void,
        fallback: @escaping @MainActor (URL) -> Void
    ) {
        cancel()
        guard RouteResolver.isFediverseCandidate(url) else {
            fallback(url)
            return
        }
        if let known = answers[Key(accountID: accountID, link: url.absoluteString)] {
            if let known { onRoute(known) } else { fallback(url) }
            return
        }
        pending = url
        work = Task {
            let lookup = await self.lookup(url, accountID: accountID, search: search)
            // Replaced by another tap, or abandoned for the browser.
            guard !Task.isCancelled, self.pending == url else { return }
            self.pending = nil
            if case .found(let route) = lookup { onRoute(route) } else { fallback(url) }
        }
    }

    /// Stops waiting. The lookup is abandoned; nothing opens.
    func cancel() {
        work?.cancel()
        work = nil
        pending = nil
    }

    /// Asks the server about `url`, through the cache.
    func lookup(_ url: URL, accountID: UUID, search: @escaping Search) async -> Lookup {
        let key = Key(accountID: accountID, link: url.absoluteString)
        if let known = answers[key] { return known.map(Lookup.found) ?? .nothingThere }

        guard let results = await Self.search(url, within: timeout, using: search) else {
            return .failed
        }
        let route = Self.route(for: url, in: results)
        answers[key] = .some(route)
        return route.map(Lookup.found) ?? .nothingThere
    }

    /// The search, or nil when it throws or outlasts `limit`. Raced rather
    /// than left to `URLRequest.timeoutInterval`, which is an idle timeout:
    /// a server trickling bytes never trips it.
    nonisolated private static func search(
        _ url: URL, within limit: Duration, using search: @escaping Search
    ) async -> SearchResults? {
        await withTaskGroup(of: SearchResults?.self) { group in
            group.addTask { try? await search(url) }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Deciding what the answer is

    /// The thread or profile in `results` that *is* the link, if any.
    ///
    /// A server that resolved the address answers with exactly what it
    /// found. One that did not may fall back to a full-text search and return
    /// posts that merely *mention* the address — opening one of those would
    /// show the reader a stranger's post in place of the one they tapped. So
    /// a result is taken only when it names the link (its `url` or `uri`), is
    /// the account a `/@user@host` link spells, or is the single thing the
    /// server returned and does not itself quote the link.
    nonisolated static func route(for url: URL, in results: SearchResults) -> Route? {
        let link = comparable(url)
        if let status = results.statuses.first(where: {
            comparable($0.url) == link || comparable(URL(string: $0.uri)) == link
        }) {
            return .thread(statusID: status.id)
        }
        if let account = results.accounts.first(where: {
            comparable($0.url) == link || comparable($0.uri) == link
        }) {
            return .profile(accountID: account.id)
        }
        if let handle = spelledHandle(in: url),
            let account = results.accounts.first(where: {
                $0.acct.caseInsensitiveCompare(handle) == .orderedSame
                    || "\($0.acct)@\(url.host() ?? "")".caseInsensitiveCompare(handle)
                        == .orderedSame
            })
        {
            // A profile viewed through another server's page
            // (`https://mastodon.social/@bob@elsewhere.example`): the
            // account's own address is elsewhere, but its handle is the path.
            if !looksLikePost(url) { return .profile(accountID: account.id) }
        }
        if results.statuses.count == 1, results.accounts.isEmpty,
            let status = results.statuses.first,
            let host = url.host(), !status.content.contains(host + url.path())
        {
            return .thread(statusID: status.id)
        }
        if results.accounts.count == 1, results.statuses.isEmpty,
            let account = results.accounts.first, !looksLikePost(url)
        {
            return .profile(accountID: account.id)
        }
        return nil
    }

    /// A URL reduced to what identifies the page: host and path, without
    /// case in the host, a trailing slash, a query or a fragment.
    nonisolated static func comparable(_ url: URL?) -> String? {
        guard let url, let host = url.host()?.lowercased(), !host.isEmpty else { return nil }
        var path = url.path(percentEncoded: false)
        while path.hasSuffix("/") { path.removeLast() }
        return host + path
    }

    /// `bob@elsewhere.example` from `/@bob@elsewhere.example/…`, or `bob`
    /// from `/@bob`.
    nonisolated private static func spelledHandle(in url: URL) -> String? {
        guard let segment = RouteResolver.fediversePath(url).first, segment.hasPrefix("@")
        else { return nil }
        let handle = String(segment.dropFirst())
        return handle.isEmpty ? nil : handle
    }

    /// Whether the path names one post rather than a profile.
    nonisolated private static func looksLikePost(_ url: URL) -> Bool {
        let path = RouteResolver.fediversePath(url)
        guard let first = path.first else { return false }
        if first.hasPrefix("@") { return path.count >= 2 }
        if first == "users" { return path.count >= 4 }
        return true
    }
}
