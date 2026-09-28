// SPDX-License-Identifier: MIT

import Foundation

public enum APIError: Error, Sendable {
    /// 401 — the token was revoked or never presented. Nextcloud Social answers
    /// `{"error": "the access_token was revoked"}`. Handling is prescribed in
    /// docs/02 §6: mark the account, stop polling, **keep the cache**, never
    /// silently delete anything.
    case unauthorised(message: String?)
    case forbidden(message: String?)
    case notFound
    /// 422 — validation. The message is written for a human and is shown
    /// verbatim, after a lead-in saying what the app was trying to do.
    case unprocessable(message: String)
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int, body: String?)
    case decoding(underlying: any Error, context: String)
    case transport(URLError)
    case invalidResponse
    case cancelled

    /// The one place an HTTP response becomes a typed error.
    static func from(status: Int, data: Data, headers: [AnyHashable: Any]) -> APIError? {
        guard !(200..<300).contains(status) else { return nil }
        let payload = ErrorPayload(data: data)

        switch status {
        case 401: return .unauthorised(message: payload.message)
        case 403: return .forbidden(message: payload.message)
        case 404, 410: return .notFound
        case 422: return .unprocessable(message: payload.message ?? "The server rejected that.")
        case 429:
            let retryAfter = (headers["Retry-After"] as? String).flatMap(TimeInterval.init)
            return .rateLimited(retryAfter: retryAfter)
        default:
            return .server(
                status: status, body: payload.message ?? String(data: data, encoding: .utf8))
        }
    }

    /// Mastodon-shaped errors are `{"error": …, "error_description": …}`.
    private struct ErrorPayload {
        let message: String?

        init(data: Data) {
            struct Body: Decodable {
                let error: String?
                let errorDescription: String?
                enum CodingKeys: String, CodingKey {
                    case error
                    case errorDescription = "error_description"
                }
            }
            let body = try? JSONDecoder().decode(Body.self, from: data)
            message = body?.errorDescription ?? body?.error
        }
    }
}

extension APIError {
    /// Whether retrying the identical request could plausibly succeed. Writes
    /// are never retried automatically whatever this says (docs/02 §6).
    public var isTransient: Bool {
        switch self {
        case .rateLimited, .transport: true
        case .server(let status, _): status >= 500
        default: false
        }
    }

    /// The account needs re-authentication, which is a state rather than a
    /// failure: cached data stays, polling stops, a banner appears.
    public var requiresReauthentication: Bool {
        if case .unauthorised = self { return true }
        return false
    }
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthorised:
            String(localized: "Your sign-in has expired.", comment: "Error when a token is revoked")
        case .forbidden:
            String(localized: "Your server wouldn't allow that.", comment: "HTTP 403")
        case .notFound:
            String(localized: "That isn't there any more.", comment: "HTTP 404")
        case .unprocessable(let message):
            message
        case .rateLimited:
            String(localized: "Your server is asking for a moment.", comment: "HTTP 429")
        case .server(let status, _):
            String(
                localized: "Your server had a problem (\(status)).",
                comment: "HTTP 5xx, with the status code")
        case .decoding:
            String(localized: "Your server sent something unexpected.", comment: "Decoding failure")
        case .transport:
            String(localized: "Couldn't reach your server.", comment: "Network failure")
        case .invalidResponse:
            String(
                localized: "Your server sent an unreadable reply.", comment: "Malformed response")
        case .cancelled:
            String(localized: "Cancelled.", comment: "Request cancelled")
        }
    }
}
