// SPDX-License-Identifier: MIT

import Foundation
import OSLog

/// Nextcloud's Login Flow v2, which is how an app obtains a real Nextcloud
/// **app password**.
///
/// The Social OAuth token is issued by the Social app's own authorisation
/// server and resolves through its `social_client_auth` table — it is not a
/// Nextcloud session, so WebDAV and the OCS APIs will not accept it. That is
/// the gap recorded as open question §3 item 4, and this closes it.
///
/// One app password unlocks two things this app could not otherwise do:
/// browsing Files, and registering for push through Nextcloud's proxy.
public struct NextcloudLoginFlow: Sendable {
    private let transport: any HTTPTransport
    private let logger = Logger(subsystem: "com.nextcloud.alohasocial", category: "nextcloud")

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public struct Start: Sendable, Hashable {
        /// Opened in a browser for the person to approve.
        public var loginURL: URL
        var pollToken: String
        var pollEndpoint: URL
    }

    public struct Credentials: Sendable, Hashable, Codable {
        public var server: URL
        public var loginName: String
        public var appPassword: String

        public init(server: URL, loginName: String, appPassword: String) {
            self.server = server
            self.loginName = loginName
            self.appPassword = appPassword
        }

        /// Nextcloud accepts an app password as HTTP Basic, which is what both
        /// WebDAV and the OCS endpoints expect.
        public var basicAuthorization: String {
            let raw = "\(loginName):\(appPassword)"
            return "Basic " + Data(raw.utf8).base64EncodedString()
        }
    }

    public enum FlowError: Error, Sendable {
        case unsupported
        case declined
        case timedOut
        case malformedResponse
    }

    /// `POST /index.php/login/v2`. A 404 here means this host is not a
    /// Nextcloud, which is a normal answer for a plain Mastodon server.
    public func begin(server: URL) async throws -> Start {
        var request = URLRequest(url: server.appending(path: "index.php/login/v2"))
        request.httpMethod = "POST"
        request.setValue(AlohaUserAgent.value, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw FlowError.unsupported }

        struct Payload: Decodable {
            struct Poll: Decodable {
                let token: String
                let endpoint: String
            }
            let poll: Poll
            let login: String
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
            let loginURL = URL(string: payload.login),
            let pollEndpoint = URL(string: payload.poll.endpoint)
        else { throw FlowError.malformedResponse }

        return Start(
            loginURL: loginURL, pollToken: payload.poll.token, pollEndpoint: pollEndpoint)
    }

    /// Polls until the person finishes in the browser. Nextcloud answers 404
    /// while it is still waiting, and 200 with the credentials once done.
    public func awaitApproval(
        _ start: Start, timeout: TimeInterval = 300, interval: TimeInterval = 2
    ) async throws -> Credentials {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if Task.isCancelled { throw FlowError.declined }

            var request = URLRequest(url: start.pollEndpoint)
            request.httpMethod = "POST"
            request.setValue(
                "application/x-www-form-urlencoded; charset=utf-8",
                forHTTPHeaderField: "Content-Type")
            request.setValue(AlohaUserAgent.value, forHTTPHeaderField: "User-Agent")

            var components = URLComponents()
            components.queryItems = [URLQueryItem(name: "token", value: start.pollToken)]
            request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)

            if let (data, response) = try? await transport.send(request),
                response.statusCode == 200
            {
                struct Payload: Decodable {
                    let server: String
                    let loginName: String
                    let appPassword: String
                }
                guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
                    let server = URL(string: payload.server)
                else { throw FlowError.malformedResponse }

                logger.info("nextcloud app password obtained")
                return Credentials(
                    server: server, loginName: payload.loginName,
                    appPassword: payload.appPassword)
            }

            try? await Task.sleep(for: .seconds(interval))
        }

        throw FlowError.timedOut
    }

    /// Revokes the app password. Signing out of Aloha should not leave a live
    /// credential on the Nextcloud.
    public func revoke(_ credentials: Credentials) async {
        var request = URLRequest(
            url: credentials.server.appending(path: "ocs/v2.php/core/apppassword"))
        request.httpMethod = "DELETE"
        request.setValue(credentials.basicAuthorization, forHTTPHeaderField: "Authorization")
        request.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
        _ = try? await transport.send(request)
    }
}

extension CredentialStore {
    /// Stored beside the Social token, under the same `ThisDeviceOnly`
    /// accessibility class.
    public func nextcloudCredentials(for accountID: UUID) throws -> NextcloudLoginFlow.Credentials?
    {
        guard let raw = try nextcloudRaw(for: accountID), let data = raw.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(NextcloudLoginFlow.Credentials.self, from: data)
    }

    public func setNextcloudCredentials(
        _ credentials: NextcloudLoginFlow.Credentials, for accountID: UUID
    ) throws {
        let data = try JSONEncoder().encode(credentials)
        guard let raw = String(data: data, encoding: .utf8) else { return }
        try setNextcloudRaw(raw, for: accountID)
    }
}
