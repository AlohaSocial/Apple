// SPDX-License-Identifier: MIT

import Foundation

public enum APIError: Error, Sendable {
    /// 401 — the token was revoked or never presented. Nextcloud Social answers
    /// `{"error": "the access_token was revoked"}`. Handling is prescribed in
    /// docs/02 §6: mark the account, stop polling, **keep the cache**, never
    /// silently delete anything.
    case unauthorised(message: String?)
    case forbidden(message: String?)
    /// 403 with `code: "account-not-set-up"`: a Nextcloud user who has not
    /// chosen a username in Aloha Social yet (`AccountNotSetUpException`).
    /// Not a sign-in failure — the token is fine — and the way out is the
    /// page at `setupURL`, in a browser.
    case accountNotSetUp(message: String?, setupURL: URL?)
    /// 404 or 410. The message is the server's, when it said why — "Bluesky
    /// is not enabled on this server" is a different 404 from a deleted post.
    case notFound(message: String? = nil)
    /// 422 — validation. The message is written for a human and is shown
    /// verbatim, after a lead-in saying what the app was trying to do. When
    /// the server sent a refusal code the app knows, the message is the app's
    /// own sentence for it, in the person's language.
    case unprocessable(message: String)
    /// Any other refusal that carries Aloha Social's machine-readable `code`
    /// (`CodedRefusal::toArray`): a 409 "import running", a 413 "file too
    /// large", a 400 "no file". The code and its numbers are kept so the
    /// sentence can be the app's own.
    case refused(Refusal)
    case rateLimited(retryAfter: TimeInterval?)
    /// Anything else. `body` is the server's own sentence when it sent one as
    /// JSON (`error`, `error_description` or `message`), otherwise the raw
    /// text, for the log.
    case server(status: Int, body: String?)
    case decoding(underlying: any Error, context: String)
    case transport(URLError)
    case invalidResponse
    case cancelled

    /// A refusal the server explained with a stable code beside its English
    /// sentence (docs/API.md "Migration error codes", Atproto-Compatibility
    /// §13.5).
    public struct Refusal: Sendable, Hashable {
        public let status: Int
        public let code: String
        /// The server's English sentence: for logs, and the fallback when the
        /// app has no sentence of its own for `code`.
        public let message: String?
        /// The numbers and names the advice needs — `limit`, `max`, `min`,
        /// `field`, `choices`, `group` — as the server spelled them.
        public let parameters: [String: String]

        public init(status: Int, code: String, message: String?, parameters: [String: String] = [:])
        {
            self.status = status
            self.code = code
            self.message = message
            self.parameters = parameters
        }

        public var limit: Int? { parameters["limit"].flatMap { Int($0) } }
    }

    /// The one place an HTTP response becomes a typed error.
    static func from(
        status: Int, data: Data, headers: [AnyHashable: Any], now: Date = Date()
    ) -> APIError? {
        guard !(200..<300).contains(status) else { return nil }
        let payload = ErrorPayload(data: data)
        let advice = payload.code.flatMap {
            RefusalAdvice.text(code: $0, parameters: payload.parameters)
        }

        switch status {
        case 401: return .unauthorised(message: payload.message)
        case 403:
            if payload.code == "account-not-set-up" {
                return .accountNotSetUp(message: payload.message, setupURL: payload.setupURL)
            }
            return .forbidden(message: advice ?? payload.message)
        case 404, 410: return .notFound(message: advice ?? payload.message)
        case 422:
            return .unprocessable(
                message: advice ?? payload.message
                    ?? String(
                        localized: "The server rejected that.", comment: "HTTP 422 without a reason"
                    ))
        case 429:
            return .rateLimited(retryAfter: retryAfter(in: headers, now: now))
        default:
            if let code = payload.code {
                return .refused(
                    Refusal(
                        status: status, code: code, message: payload.message,
                        parameters: payload.parameters))
            }
            return .server(
                status: status, body: payload.message ?? String(data: data, encoding: .utf8))
        }
    }

    /// `Retry-After` as seconds or as an HTTP-date (RFC 9110 §10.2.3). Header
    /// names are case-insensitive, and `allHeaderFields` keeps whatever case
    /// the server or a proxy used, so the lookup cannot be a subscript.
    static func retryAfter(in headers: [AnyHashable: Any], now: Date = Date()) -> TimeInterval? {
        guard
            let raw = headers.first(where: {
                ($0.key as? String)?.caseInsensitiveCompare("Retry-After") == .orderedSame
            })?.value as? String
        else { return nil }
        let value = raw.trimmingCharacters(in: .whitespaces)
        if let seconds = TimeInterval(value) { return max(0, seconds) }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }

    /// Mastodon-shaped errors are `{"error": …, "error_description": …}`;
    /// some routes say `message` instead. Aloha Social adds a
    /// machine-readable `code`, the numbers its advice needs, and for some an
    /// address to go to (`CodedRefusal::toArray`).
    private struct ErrorPayload {
        let message: String?
        let code: String?
        let setupURL: URL?
        let parameters: [String: String]

        private static let parameterNames = ["limit", "max", "min", "field", "choices", "group"]

        init(data: Data) {
            let object =
                (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let string = { (key: String) -> String? in
                (object[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
            }
            message = string("error_description") ?? string("error") ?? string("message")
            code = string("code")
            setupURL = string("setup_url").flatMap(URL.init(string:)).flatMap {
                // Opened in a browser, so only ever a web address.
                ["https", "http"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil
            }
            var parameters: [String: String] = [:]
            for name in Self.parameterNames {
                switch object[name] {
                case let value as String: parameters[name] = value
                case let value as NSNumber: parameters[name] = value.stringValue
                case let values as [Any]:
                    parameters[name] = values.map { "\($0)" }.joined(separator: ", ")
                default: break
                }
            }
            self.parameters = parameters
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
        case .refused(let refusal): refusal.status >= 500
        default: false
        }
    }

    /// The account needs re-authentication, which is a state rather than a
    /// failure: cached data stays, polling stops, a banner appears.
    public var requiresReauthentication: Bool {
        if case .unauthorised = self { return true }
        return false
    }

    /// Where to finish setting the account up, when that is what is wrong.
    public var accountSetupURL: URL? {
        if case .accountNotSetUp(_, let url) = self { return url }
        return nil
    }

    public var isAccountNotSetUp: Bool {
        if case .accountNotSetUp = self { return true }
        return false
    }

    /// The server's refusal code, for a caller that branches on one.
    public var refusalCode: String? {
        if case .refused(let refusal) = self { return refusal.code }
        return nil
    }
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthorised:
            // Deliberately not the token story. A 401 on one of a server's own
            // routes means that route refused this account — Nextcloud Social
            // answers 401 from statistics, interests and channels for reasons
            // nothing to do with the token — and telling somebody their sign-in
            // expired there is how they end up believing it. The token story is
            // the banner, which is only ever raised after verify_credentials
            // confirms the token really is dead.
            String(localized: "Your server wouldn't allow that.", comment: "HTTP 401")
        case .forbidden(let message):
            message.flatMap(Self.readable)
                ?? String(localized: "Your server wouldn't allow that.", comment: "HTTP 403")
        case .accountNotSetUp(let message, _):
            message
                ?? String(
                    localized:
                        "Your account isn't set up yet. Open Aloha Social in a web browser and choose your username.",
                    comment: "HTTP 403, account not set up")
        case .notFound(let message):
            message.flatMap(Self.readable)
                ?? String(localized: "That isn't there any more.", comment: "HTTP 404")
        case .unprocessable(let message):
            message
        case .refused(let refusal):
            RefusalAdvice.text(code: refusal.code, parameters: refusal.parameters)
                ?? refusal.message.flatMap(Self.readable)
                ?? Self.statusDescription(refusal.status)
        case .rateLimited:
            String(localized: "Your server is asking for a moment.", comment: "HTTP 429")
        case .server(let status, let body):
            // A 5xx sentence is the server's fixed "something went wrong", and
            // a 4xx one says what was wrong with the request; only the second
            // is worth showing.
            (status < 500 ? body.flatMap(Self.readable) : nil) ?? Self.statusDescription(status)
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

    private static func statusDescription(_ status: Int) -> String {
        String(
            localized: "Your server had a problem (\(status)).",
            comment: "HTTP 5xx, with the status code")
    }

    /// A server sentence fit to show: not an HTML error page, not a stack
    /// trace, not a paragraph.
    private static func readable(_ message: String) -> String? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 300, !trimmed.contains("<") else { return nil }
        return trimmed
    }
}
