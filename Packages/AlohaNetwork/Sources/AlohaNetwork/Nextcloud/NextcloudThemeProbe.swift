// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import OSLog

/// Reads the colour a Nextcloud is wearing.
///
/// `GET {root}/ocs/v2.php/cloud/capabilities`, which is Nextcloud's own route
/// and not the Social app's — the Social API serves no colour, and the OCS
/// routes live at the **Nextcloud root** whether or not the rewrite rules put
/// the Mastodon API there too.
///
/// Public and unauthenticated: it is what themes a client's sign-in screen
/// before anybody has signed in, so no token is sent and none is needed. The
/// `OCS-APIRequest` header is not optional — Nextcloud refuses an OCS call
/// without it.
///
/// Every failure means "no colour", which leaves the app's own accent in place.
/// A plain Mastodon answers 404 here, which is the normal case rather than an
/// error worth reporting.
public struct NextcloudThemeProbe: Sendable {
    private let transport: any HTTPTransport
    private let timeout: Duration
    private let logger = Logger(subsystem: "com.nextcloud.alohasocial", category: "theming")

    public init(
        transport: any HTTPTransport = URLSessionTransport(),
        timeout: Duration = .seconds(5)
    ) {
        self.transport = transport
        self.timeout = timeout
    }

    public func theme(nextcloudRoot: URL) async -> NextcloudTheme? {
        guard
            var components = URLComponents(
                url: nextcloudRoot.appending(path: "ocs/v2.php/cloud/capabilities"),
                resolvingAgainstBaseURL: false)
        else { return nil }
        components.queryItems = [URLQueryItem(name: "format", value: "json")]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Without this Nextcloud answers 412 and says why in a body nobody reads.
        request.setValue("true", forHTTPHeaderField: "OCS-APIRequest")

        // `let` before the closure: a `var` captured by concurrently-executing
        // code is a data race the compiler refuses, and the request is finished
        // being built by here anyway.
        let prepared = request
        do {
            let (data, response) = try await withThrowingTimeout(timeout) {
                try await transport.send(prepared)
            }
            guard (200..<300).contains(response.statusCode) else { return nil }
            let capabilities = try AlohaJSON.decoder.decode(OCSCapabilities.self, from: data)
            guard let theme = capabilities.theming, theme.hasColour else { return nil }
            logger.debug("server theming colour found")
            return theme
        } catch {
            return nil
        }
    }

    /// The probe must not hold up sign-in on a server that never answers.
    private func withThrowingTimeout<T: Sendable>(
        _ duration: Duration, _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw CancellationError()
            }
            guard let first = try await group.next() else { throw CancellationError() }
            group.cancelAll()
            return first
        }
    }
}
