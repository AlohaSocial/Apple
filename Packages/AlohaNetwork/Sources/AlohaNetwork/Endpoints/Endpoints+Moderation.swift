// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

extension Endpoint {
    /// Mastodon's admin API, `/api/v1/admin/*`, which Nextcloud Social serves
    /// from `AdminApiController`.
    ///
    /// The server's own `/moderation/*` routes need a Nextcloud session **and**
    /// a CSRF token, which no API client has; these take the bearer token, and
    /// the server checks that the Nextcloud user behind it is an administrator
    /// on every single route. So a 403 here is the honest answer for an
    /// ordinary account and the app hides the section rather than showing rows
    /// it cannot load.
    ///
    /// Only the moderation half is wired up: the reports queue, what a
    /// moderator may do to an account, and what may trend. Instance
    /// configuration — storage, retention, relays, setup checks — stays in the
    /// web administration page, which is where an administrator already is when
    /// they are doing that.
    public enum moderation {
        // MARK: Reports

        /// The queue a moderator opens the panel to work through. `resolved`
        /// absent means unresolved only, as on Mastodon.
        public static func reports(
            resolved: Bool = false, limit: Int = defaultLimit, anchor: PageAnchor = .cold
        ) -> Endpoint {
            Endpoint(
                path: "api/v1/admin/reports",
                query: pageItems(limit: limit, anchor: anchor)
                    + [URLQueryItem(name: "resolved", value: resolved ? "true" : "false")])
        }

        public static func report(_ id: String) -> Endpoint {
            Endpoint(path: "api/v1/admin/reports/\(id)")
        }

        public static func resolveReport(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/admin/reports/\(id)/resolve")
        }

        public static func reopenReport(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/admin/reports/\(id)/reopen")
        }

        public static func assignReportToSelf(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/admin/reports/\(id)/assign_to_self")
        }

        public static func unassignReport(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/admin/reports/\(id)/unassign")
        }

        // MARK: Accounts

        /// A page of accounts, newest first.
        ///
        /// `email` and `ip` are accepted by the server and match nothing — it
        /// holds neither for a fediverse account — so they are not offered.
        public static func accounts(
            origin: Origin = .any, standing: Standing = .any, username: String = "",
            byDomain: String = "", limit: Int = defaultLimit, anchor: PageAnchor = .cold
        ) -> Endpoint {
            Endpoint(
                path: "api/v1/admin/accounts",
                query: pageItems(limit: limit, anchor: anchor)
                    + .optional("origin", origin.parameter)
                    + .optional("status", standing.parameter)
                    + .optional("username", username.isEmpty ? nil : username)
                    + .optional("by_domain", byDomain.isEmpty ? nil : byDomain))
        }

        public enum Origin: String, Sendable, Hashable, CaseIterable, Identifiable {
            case any, local, remote
            public var id: String { rawValue }
            var parameter: String? { self == .any ? nil : rawValue }
        }

        /// The three states this server has. Mastodon's `pending` and
        /// `disabled` answer with nothing here and are left out.
        public enum Standing: String, Sendable, Hashable, CaseIterable, Identifiable {
            case any, active, silenced, suspended
            public var id: String { rawValue }
            var parameter: String? { self == .any ? nil : rawValue }
        }

        public static func account(_ id: String) -> Endpoint {
            Endpoint(path: "api/v1/admin/accounts/\(id)")
        }

        /// Silences or suspends an account, or records a decision that changes
        /// nothing. `reportID` resolves that report at the same time, which is
        /// what keeps the decision and the report from disagreeing.
        public static func act(
            on id: String, action: AdminAccountAction, note: String = "", reportID: String? = nil
        ) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/admin/accounts/\(id)/action",
                body: .form(
                    [URLQueryItem(name: "type", value: action.rawValue)]
                        + .optional("text", note.isEmpty ? nil : note)
                        + .optional("report_id", reportID)))
        }

        /// Lifts a silence.
        public static func unsilence(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/admin/accounts/\(id)/unsilence")
        }

        /// Lifts a suspension.
        public static func unsuspend(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/admin/accounts/\(id)/unsuspend")
        }

        /// Stops forcing every attachment of the account behind a warning.
        public static func unsensitive(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/admin/accounts/\(id)/unsensitive")
        }

        // MARK: Trends

        /// What may trend, from the moderator's side of the same three readers
        /// the public routes use.
        public static func trendingTags(limit: Int = 20) -> Endpoint {
            Endpoint(
                path: "api/v1/admin/trends/tags",
                query: [URLQueryItem(name: "limit", value: String(clampedLimit(limit)))])
        }

        public static func trendingStatuses(limit: Int = 20) -> Endpoint {
            Endpoint(
                path: "api/v1/admin/trends/statuses",
                query: [URLQueryItem(name: "limit", value: String(clampedLimit(limit)))])
        }

        public static func trendingLinks(limit: Int = 20) -> Endpoint {
            Endpoint(
                path: "api/v1/admin/trends/links",
                query: [URLQueryItem(name: "limit", value: String(clampedLimit(limit)))])
        }

        /// What a trend decision is about.
        public enum TrendKind: String, Sendable, Hashable, CaseIterable, Identifiable {
            case tags, statuses, links
            public var id: String { rawValue }
        }

        /// **Rejecting hides; approving grants nothing.** Everything nobody has
        /// objected to trends already, so an approval only records that a
        /// moderator has looked — which is the server's own arrangement, and
        /// why this screen says so rather than implying a queue.
        public static func approveTrend(_ kind: TrendKind, id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/admin/trends/\(kind.rawValue)/\(id)/approve")
        }

        public static func rejectTrend(_ kind: TrendKind, id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/admin/trends/\(kind.rawValue)/\(id)/reject")
        }
    }
}
