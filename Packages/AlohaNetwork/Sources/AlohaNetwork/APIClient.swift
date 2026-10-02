// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import OSLog

/// One per account. Owns the API base, the token, and the etiquette.
public actor APIClient {
    public let accountID: UUID
    public private(set) var apiBase: URL
    private var accessToken: String?
    /// `Basic …` for the Nextcloud app password, once one has been granted.
    /// Only the handful of `.nextcloudSession` routes ever send it.
    private var nextcloudAuthorization: String?

    private let transport: any HTTPTransport
    private let rateLimiter: RateLimiter
    private let logger = Logger(subsystem: "com.nextcloud.alohasocial", category: "network")

    public init(
        accountID: UUID,
        apiBase: URL,
        accessToken: String?,
        transport: any HTTPTransport = URLSessionTransport(),
        rateLimiter: RateLimiter = RateLimiter()
    ) {
        self.accountID = accountID
        self.apiBase = apiBase.normalisedAsAPIBase
        self.accessToken = accessToken
        self.transport = transport
        self.rateLimiter = rateLimiter
    }

    public func updateToken(_ token: String?) { accessToken = token }

    /// Set when a Nextcloud app password is granted or revoked. Without one the
    /// `.nextcloudSession` routes are refused before they leave the device
    /// rather than 401ing at the server.
    public func updateNextcloudAuthorization(_ header: String?) {
        nextcloudAuthorization = header
    }

    public var hasNextcloudAuthorization: Bool { nextcloudAuthorization != nil }

    /// Set after a re-probe finds the administrator has added or removed the
    /// rewrite rules (docs/03 §2).
    public func updateAPIBase(_ base: URL) { apiBase = base.normalisedAsAPIBase }

    /// Headers for an AVFoundation asset hosted by this account's server.
    /// A token is never sent to a federated or otherwise different origin.
    public func mediaRequestHeaders(for url: URL) -> [String: String] {
        guard url.originURL == apiBase.originURL, let accessToken else { return [:] }
        return ["Authorization": "Bearer \(accessToken)"]
    }

    // MARK: - Requests

    @discardableResult
    public func send(_ endpoint: Endpoint) async throws -> RawResponse {
        try await perform(endpoint, followingURL: nil)
    }

    public func decode<T: Decodable & Sendable>(
        _ type: T.Type, from endpoint: Endpoint
    ) async throws -> T {
        let response = try await perform(endpoint, followingURL: nil)
        return try decodeBody(type, response.data, context: endpoint.path)
    }

    /// A page, with its cursors. `limit` is remembered so `mayHaveMore` can fall
    /// back to the row count on the routes that send no `Link` header.
    public func page<T: Decodable & Sendable>(
        _ type: T.Type, from endpoint: Endpoint, limit: Int
    ) async throws -> Paginated<T> {
        let response = try await perform(endpoint, followingURL: nil)
        let value = try decodeBody(type, response.data, context: endpoint.path)
        return Paginated(
            value: value,
            link: response.link,
            rawCount: response.topLevelArrayCount ?? 0,
            requestedLimit: limit
        )
    }

    /// Follow a `Link` cursor verbatim. Rebuilding it would drop whichever
    /// filters the original request carried (docs/02 §5).
    public func page<T: Decodable & Sendable>(
        _ type: T.Type, following url: URL, limit: Int
    ) async throws -> Paginated<T> {
        let response = try await perform(
            Endpoint(path: "", requiresAuthentication: true), followingURL: url)
        let value = try decodeBody(type, response.data, context: url.path())
        return Paginated(
            value: value,
            link: response.link,
            rawCount: response.topLevelArrayCount ?? 0,
            requestedLimit: limit
        )
    }

    // MARK: - Machinery

    private func perform(_ endpoint: Endpoint, followingURL: URL?) async throws -> RawResponse {
        guard let url = followingURL ?? endpoint.url(base: apiBase) else {
            throw APIError.invalidResponse
        }
        if endpoint.requiresAuthentication, followingURL == nil {
            switch endpoint.authentication {
            case .bearer where accessToken == nil,
                .nextcloudSession where nextcloudAuthorization == nil:
                throw APIError.unauthorised(message: nil)
            default:
                break
            }
        }

        let host = url.host() ?? apiBase.host() ?? ""
        await rateLimiter.acquire(host: host)

        var request = URLRequest(url: url)
        request.httpMethod =
            followingURL == nil ? endpoint.method.rawValue : HTTPMethod.get.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        switch endpoint.authentication {
        case .bearer:
            if let accessToken {
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }
        case .nextcloudSession:
            if let nextcloudAuthorization {
                request.setValue(nextcloudAuthorization, forHTTPHeaderField: "Authorization")
                // Nextcloud refuses a session-authenticated write without it.
                request.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
            }
        }
        if let key = endpoint.idempotencyKey {
            request.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        }
        applyBody(endpoint.body, to: &request)

        // Tokens, codes and verifiers never reach a log. OSLog's default for an
        // interpolation is already private; the point here is that the values
        // are not in the message at all.
        logger.debug(
            "\(endpoint.method.rawValue, privacy: .public) \(endpoint.path, privacy: .public)")

        let (data, http) = try await transport.send(request)

        if let error = APIError.from(
            status: http.statusCode, data: data, headers: http.allHeaderFields)
        {
            if case .rateLimited(let retryAfter) = error {
                await rateLimiter.noteRateLimited(host: host, retryAfter: retryAfter)
            }
            logger.warning(
                "\(endpoint.path, privacy: .public) failed with \(http.statusCode, privacy: .public)"
            )
            throw error
        }

        return RawResponse(
            data: data,
            statusCode: http.statusCode,
            link: LinkHeader(parsing: http.value(forHTTPHeaderField: "Link"))
        )
    }

    private func applyBody(_ body: Endpoint.Body?, to request: inout URLRequest) {
        switch body {
        case .none, .empty:
            return
        case .form(let items):
            var components = URLComponents()
            components.queryItems = items.filter { $0.value != nil }
            request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
            request.setValue(
                "application/x-www-form-urlencoded; charset=utf-8",
                forHTTPHeaderField: "Content-Type")
        case .json(let data):
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        case .multipart(let multipart):
            request.httpBody = multipart.encoded()
            request.setValue(multipart.contentType, forHTTPHeaderField: "Content-Type")
        }
    }

    private nonisolated func decodeBody<T: Decodable & Sendable>(
        _ type: T.Type, _ data: Data, context: String
    ) throws -> T {
        if T.self == EmptyResponse.self, let empty = EmptyResponse() as? T { return empty }
        do {
            return try AlohaJSON.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(underlying: error, context: context)
        }
    }
}

public struct RawResponse: Sendable {
    public var data: Data
    public var statusCode: Int
    public var link: LinkHeader

    public init(data: Data, statusCode: Int, link: LinkHeader) {
        self.data = data
        self.statusCode = statusCode
        self.link = link
    }

    /// How many rows the query returned, for the "shorter than limit is the
    /// last page" fallback. Counted from the raw bytes so it reflects what the
    /// server sent rather than what survived lossy decoding.
    public var topLevelArrayCount: Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let array = json as? [Any] { return array.count }
        // Grouped notifications are an object whose groups are the page.
        if let object = json as? [String: Any],
            let groups = object["notification_groups"] as? [Any]
        {
            return groups.count
        }
        return nil
    }
}

/// For the routes that answer `{}` and mean it.
public struct EmptyResponse: Codable, Sendable, Hashable {
    public init() {}
    public init(from decoder: any Decoder) throws {}
    public func encode(to encoder: any Encoder) throws {}
}

extension URL {
    /// The scheme, host and port used to reach a server, without its API path.
    public var originURL: URL? {
        guard let scheme, let host = host() else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        return components.url
    }

    /// An API base always ends in `/`, so `appending(path:)` composes rather
    /// than replacing the last component.
    public var normalisedAsAPIBase: URL {
        absoluteString.hasSuffix("/") ? self : URL(string: absoluteString + "/") ?? self
    }
}
