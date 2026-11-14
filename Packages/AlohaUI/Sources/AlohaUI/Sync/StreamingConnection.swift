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
        /// A new post in the home timeline.
        case update(Status)
        /// A post already out there, edited (`status.update`).
        case edit(Status)
        case delete(String)
        case notification
        case filtersChanged
        case closed
    }

    /// How many reconnects before giving up. Polling never stopped, so giving
    /// up is a degradation rather than a failure.
    static let maximumAttempts = 5
    /// How often an open socket is pinged, and how long a ping may go
    /// unanswered. A socket can be silently dead — a NAT that forgot it, a
    /// network that changed under it — and without a ping it reads as open
    /// for as long as nothing arrives, which on a quiet account is forever.
    static let pingInterval: Duration = .seconds(30)
    static let pingTimeout: Duration = .seconds(10)

    private let url: URL
    /// Asked on every connect rather than read once: a reconnect after the
    /// person signed in again must carry the token they have now.
    private let token: @Sendable () -> String?
    private let onEvent: @Sendable (Event) -> Void
    private let session: URLSession
    /// Whether `session` was made here, and so is this connection's to end.
    private let ownsSession: Bool
    private var socket: URLSessionWebSocketTask?
    private var loop: Task<Void, Never>?
    /// Set by `close()` and never cleared: a closed connection does not come
    /// back, so a reconnect already sleeping cannot reopen it.
    private var isClosed = false
    /// Reconnects since the socket was last proven open.
    private var attempt = 0
    private let logger = Logger(subsystem: "social.aloha.app", category: "streaming")

    public private(set) var isOpen = false

    public init(
        url: URL, token: @escaping @Sendable () -> String?,
        session: URLSession? = nil,
        onEvent: @escaping @Sendable (Event) -> Void
    ) {
        self.url = url
        self.token = token
        self.session = session ?? URLSession(configuration: .default)
        self.ownsSession = session == nil
        self.onEvent = onEvent
    }

    public init(
        url: URL, token: String,
        session: URLSession? = nil,
        onEvent: @escaping @Sendable (Event) -> Void
    ) {
        self.init(url: url, token: { token }, session: session, onEvent: onEvent)
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
        attempt = 0
        while !isClosed, !Task.isCancelled {
            guard let request = makeRequest() else {
                // No token any more — signed out, or being removed. Nothing
                // to reconnect with; polling carries on.
                loop = nil
                onEvent(.closed)
                return
            }
            let socket = session.webSocketTask(with: request)
            self.socket = socket
            socket.resume()
            // Not open yet: `resume()` only starts the handshake, and a
            // refused token or a proxy that does not speak WebSocket fails
            // after it. Open is what the first pong or message proves, and
            // until then the poller keeps its own interval.
            let pinger = Task { await keepAlive(socket) }
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    markOpen()
                    handle(message)
                }
            } catch {
                // Falls through to reconnecting, below.
            }
            pinger.cancel()
            isOpen = false
            guard !isClosed, !Task.isCancelled else { return }

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

    /// A socket proven open starts the count of failed attempts again.
    private func markOpen() {
        guard !isClosed else { return }
        isOpen = true
        attempt = 0
    }

    /// Pings at once — the first pong is the handshake's proof — and then
    /// every `pingInterval`. A ping that fails or goes unanswered cancels the
    /// socket, which ends the receive loop and starts a reconnect: the
    /// socket was closed, whatever it still claimed.
    private func keepAlive(_ socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            let answered = await Self.ping(socket, within: Self.pingTimeout)
            guard !Task.isCancelled, self.socket === socket else { return }
            guard answered else {
                logger.notice("streaming ping went unanswered; reconnecting")
                isOpen = false
                socket.cancel(with: .abnormalClosure, reason: nil)
                return
            }
            markOpen()
            try? await Task.sleep(for: Self.pingInterval)
        }
    }

    /// Whether a ping came back within `timeout`.
    nonisolated private static func ping(
        _ socket: URLSessionWebSocketTask, within timeout: Duration
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    // `@Sendable`: URLSession calls it on its delegate queue,
                    // and an isolated closure called there traps.
                    socket.sendPing { @Sendable error in
                        continuation.resume(returning: error == nil)
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let first = await group.next() ?? false
            // A pong that never comes leaves its handler waiting until the
            // socket goes; cancelling it here is what lets the group end.
            if !first { socket.cancel(with: .abnormalClosure, reason: nil) }
            group.cancelAll()
            return first
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

        guard let token = token() else { return nil }
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
            onEvent(event == "update" ? .update(status) : .edit(status))
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
