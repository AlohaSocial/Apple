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
/// **`nonisolated` deliberately.** This package compiles with `MainActor`
/// default isolation, and these callbacks arrive on `URLSession`'s delegate
/// queue and on a global queue. An isolated closure invoked from either trips
/// Swift's runtime isolation check and traps the process.
public nonisolated final class StreamingConnection: @unchecked Sendable {
    public enum Event: Sendable {
        case update(Status)
        case delete(String)
        case notification
        case filtersChanged
        case closed
    }

    private let url: URL
    private let token: String
    private let onEvent: @Sendable (Event) -> Void
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var attempt = 0
    private var isClosing = false
    private let logger = Logger(subsystem: "com.nextcloud.alohasocial", category: "streaming")

    public private(set) var isOpen = false

    public init(
        url: URL, token: String,
        session: URLSession = URLSession(configuration: .default),
        onEvent: @escaping @Sendable (Event) -> Void
    ) {
        self.url = url
        self.token = token
        self.session = session
        self.onEvent = onEvent
    }

    public func open() {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return
        }
        components.queryItems =
            (components.queryItems ?? []) + [
                URLQueryItem(name: "stream", value: "user")
            ]
        guard let socketURL = components.url else { return }

        var request = URLRequest(url: socketURL)
        // In the header rather than the query string: a token in a URL ends up
        // in logs on the way through.
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        self.task = task
        isOpen = true
        task.resume()
        receive()
    }

    public func close() {
        isClosing = true
        isOpen = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.attempt = 0
                self.handle(message)
                self.receive()
            case .failure:
                self.isOpen = false
                guard !self.isClosing else { return }
                self.reconnect()
            }
        }
    }

    /// Five attempts, then it gives up and says why. Polling never stopped, so
    /// giving up is a degradation rather than a failure.
    private func reconnect() {
        attempt += 1
        guard attempt <= 5 else {
            logger.notice("streaming gave up after 5 attempts; polling continues")
            onEvent(.closed)
            return
        }
        let delay = Backoff.delay(attempt: attempt, cap: 60)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.open()
        }
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
