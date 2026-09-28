// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

extension Endpoint {
    /// "Your year": Mastodon's `#Wrapstodon`, which Nextcloud Social serves
    /// over the API and has no web page of its own for (`ApiController`
    /// §"the year an account had").
    public enum annualReports {
        /// Every year this account has a report for, newest first.
        public static var all: Endpoint { Endpoint(path: "api/v1/annual_reports") }

        public static func year(_ year: Int) -> Endpoint {
            Endpoint(path: "api/v1/annual_reports/\(year)")
        }

        /// Whether a year has a report. `generating` never comes back from
        /// this server — the report is a query rather than a job.
        public static func state(_ year: Int) -> Endpoint {
            Endpoint(path: "api/v1/annual_reports/\(year)/state")
        }

        /// Asks for one to be generated, which this server answers instantly
        /// with nothing to wait for. Called before a read because Mastodon
        /// clients do, and because a server that needs it will act on it.
        public static func generate(_ year: Int) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/annual_reports/\(year)/generate")
        }

        /// Marks one read, so the app stops offering it at the top of Home.
        public static func markRead(_ year: Int) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/annual_reports/\(year)/read")
        }
    }
}
