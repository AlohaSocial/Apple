// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import Foundation
import OSLog

/// The streaming upgrade path (docs/08 §6).
///
/// Dormant against Nextcloud Social, which announces no streaming by sending an
/// empty `urls` object — that empty object is how a client learns to fall back
/// to polling immediately rather than after a timeout. Live against real
/// Mastodon, which is why it is written rather than deferred.
///
/// **An actor.** The socket's state used to be touched from `URLSession`'s
/// delegate queue, a global queue and the main actor at once. Here one receive
/// loop owns it: messages are decoded on the actor, off the main thread, and
/// only finished events leave through `onEvent`.
public actor StreamingConnection {
    public enum Event: Sendable {
        case update(Status)
        case delete(String)
        case notification
        case filtersChanged
        case closed
    }

    /// How many reconnects before giving up. Polling never stopped, so giving
    /// up is a degradation rather than a failure.
    static let maximumAttempts = 5

    private let url: URL
    private let token: String
    private let onEvent: @Sendable (Event) -> Void
    private let session: URLSession
    /// Whether `session` was made here, and so is this connection's to end.
    private let ownsSession: Bool
    private var socket: URLSessionWebSocketTask?
    private var loop: Task<Void, Never>?
    /// Set by `close()` and never cleared: a closed connection does not come
    /// back, so a reconnect already sleeping cannot reopen it.
    private var isClosed = false
    private let logger = Logger(subsystem: "social.aloha.app", category: "streaming")

    public private(set) var isOpen = false

    public init(
        url: URL, token: String,
        session: URLSession? = nil,
        onEvent: @escaping @Sendable (Event) -> Void
    ) {
        self.url = url
        self.token = token
        self.session = session ?? URLSession(configuration: .default)
        self.ownsSession = session == nil
        self.onEvent = onEvent
    }

    public func open() {
        guard !isClosed, loop == nil else { return }
        loop = Task { await run() }
    }

    public func close() {
        isClosed = true
        isOpen = false
        loop?.cancel()
        loop = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        // A session left valid keeps its delegate queue and its connections
        // alive for the life of the process.
        if ownsSession { session.invalidateAndCancel() }
    }

    private func run() async {
        var attempt = 0
        while !isClosed, !Task.isCancelled {
            guard let request = makeRequest() else { return }
            let socket = session.webSocketTask(with: request)
            self.socket = socket
            socket.resume()
            isOpen = true
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    attempt = 0
                    handle(message)
                }
            } catch {
                isOpen = false
                guard !isClosed, !Task.isCancelled else { return }
            }

            attempt += 1
            guard attempt <= Self.maximumAttempts else {
                logger.notice("streaming gave up after 5 attempts; polling continues")
                loop = nil
                onEvent(.closed)
                return
            }
            try? await Task.sleep(for: .seconds(Backoff.delay(attempt: attempt, cap: 60)))
        }
    }

    private func makeRequest() -> URLRequest? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems =
            (components.queryItems ?? []) + [
                URLQueryItem(name: "stream", value: "user")
            ]
        guard let socketURL = components.url else { return nil }

        var request = URLRequest(url: socketURL)
        // In the header rather than the query string: a token in a URL ends up
        // in logs on the way through.
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let value): text = value
        case .data(let data): text = String(data: data, encoding: .utf8) ?? ""
        @unknown default: return
        }

        guard let data = text.data(using: .utf8),
            let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let event = envelope["event"] as? String
        else { return }

        let payload = envelope["payload"] as? String

        switch event {
        case "update", "status.update":
            guard let payload, let statusData = payload.data(using: .utf8),
                let status = try? AlohaJSON.decoder.decode(Status.self, from: statusData)
            else { return }
            onEvent(.update(status))
        case "delete":
            guard let payload else { return }
            onEvent(.delete(payload))
        case "notification":
            onEvent(.notification)
        case "filters_changed":
            onEvent(.filtersChanged)
        default:
            break
        }
    }
}
