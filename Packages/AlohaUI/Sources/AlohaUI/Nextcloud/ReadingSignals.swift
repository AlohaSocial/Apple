// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import Foundation
import OSLog
import SwiftUI

/// What For you learns from reading: how long a post stayed on screen, which
/// ones were scrolled straight past, which were opened.
///
/// Aloha Social learns the reader's interests from these
/// (`POST /api/v1/interests/signals`) — the web interface sends them, and an
/// app that did not would leave For you learning only from what was liked.
/// Nothing here leaves the reader's own server, and the server keeps none of
/// it: each signal is folded into the scores as it arrives (`InterestService`).
///
/// Batched and slow on purpose. The server takes at most 100 events per
/// request and 30 requests a minute; this sends at most one request every 20
/// seconds, so a fast scroll never comes near either.
@MainActor
final class ReadingSignals {
    /// How long a post has to stay on screen to count as read rather than
    /// passed. Below `skipBelow` it was scrolled past; in between says nothing.
    static let dwellFrom: Duration = .milliseconds(1500)
    static let skipBelow: Duration = .milliseconds(500)
    static let minimumInterval: Duration = .seconds(20)
    static let flushAt = 50

    private let client: APIClient
    private var queue: [InterestSignal] = []
    private var onScreen: [String: ContinuousClock.Instant] = [:]
    private var lastSent: ContinuousClock.Instant?
    private var pendingFlush: Task<Void, Never>?
    /// Set when the server refuses (For you switched off is a 403): there is
    /// nothing to learn for, so nothing more is sent this session.
    private var isRefused = false
    private let clock = ContinuousClock()
    private let logger = Logger(subsystem: "social.aloha.app", category: "signals")

    private init(client: APIClient) {
        self.client = client
    }

    private static var collectors: [UUID: ReadingSignals] = [:]

    /// The collector for one account, or `nil` where its server learns
    /// nothing from reading — anything but Aloha Social.
    static func forSession(_ session: AccountSession) -> ReadingSignals? {
        guard session.capabilities.isNextcloudSocial else { return nil }
        if let existing = collectors[session.id] { return existing }
        let collector = ReadingSignals(client: session.client)
        collectors[session.id] = collector
        return collector
    }

    // MARK: Recording

    func appeared(_ status: Status, context: InterestSignal.Context) {
        onScreen[key(status, context)] = clock.now
    }

    func disappeared(_ status: Status, context: InterestSignal.Context) {
        guard let start = onScreen.removeValue(forKey: key(status, context)) else { return }
        let elapsed = clock.now - start
        if elapsed >= Self.dwellFrom {
            record(status, .dwell, milliseconds: Self.milliseconds(elapsed), context: context)
        } else if elapsed < Self.skipBelow {
            record(status, .skip, context: context)
        }
    }

    /// A post opened on its own: the strongest thing reading can say.
    func opened(_ status: Status, context: InterestSignal.Context = .detail) {
        record(status, .open, context: context)
    }

    func record(
        _ status: Status, _ kind: InterestSignal.Kind, milliseconds: Int = 0,
        context: InterestSignal.Context
    ) {
        guard !isRefused else { return }
        let signal = InterestSignal(
            statusID: status.displayed.id, kind: kind, milliseconds: milliseconds,
            context: context)
        // Only the server's own posts teach it anything; it skips the rest.
        guard signal.isLearnable else { return }
        queue.append(signal)
        scheduleFlush()
    }

    // MARK: Sending

    private func scheduleFlush() {
        if queue.count >= Self.flushAt, canSendNow {
            pendingFlush?.cancel()
            pendingFlush = nil
            Task { await flush() }
            return
        }
        guard pendingFlush == nil else { return }
        let wait = lastSent.map { Self.minimumInterval - (clock.now - $0) } ?? Self.minimumInterval
        pendingFlush = Task { [weak self] in
            try? await Task.sleep(for: max(wait, .seconds(1)))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private var canSendNow: Bool {
        guard let lastSent else { return true }
        return clock.now - lastSent >= Self.minimumInterval
    }

    func flush() async {
        pendingFlush = nil
        guard !queue.isEmpty, !isRefused else { return }
        let batch = Array(queue.prefix(Endpoint.interests.maximumSignals))
        queue.removeFirst(batch.count)
        lastSent = clock.now
        do {
            try await client.send(Endpoint.interests.signals(batch))
        } catch let error as APIError {
            switch error {
            case .forbidden, .notFound, .unauthorised, .accountNotSetUp:
                // For you is off, or not there: stop asking.
                isRefused = true
                queue.removeAll()
            default:
                // A signal is a hint, not a record: one that could not be
                // delivered is dropped rather than retried into a backlog.
                logger.debug("reading signals not delivered")
            }
        } catch {
            logger.debug("reading signals not delivered")
        }
        if !queue.isEmpty { scheduleFlush() }
    }

    // MARK: Helpers

    private func key(_ status: Status, _ context: InterestSignal.Context) -> String {
        "\(context.rawValue):\(status.displayed.id)"
    }

    nonisolated static func milliseconds(_ duration: Duration) -> Int {
        let parts = duration.components
        return Int(parts.seconds) * 1000 + Int(parts.attoseconds / 1_000_000_000_000_000)
    }
}

extension View {
    /// Reports how long the row stayed on screen to For you, on a server
    /// that learns from it. Nothing at all elsewhere.
    func readingSignal(
        _ status: Status, context: InterestSignal.Context, session: AccountSession
    ) -> some View {
        modifier(ReadingSignalModifier(status: status, context: context, session: session))
    }
}

private struct ReadingSignalModifier: ViewModifier {
    let status: Status
    let context: InterestSignal.Context
    let session: AccountSession

    func body(content: Content) -> some View {
        content
            .onAppear { ReadingSignals.forSession(session)?.appeared(status, context: context) }
            .onDisappear {
                ReadingSignals.forSession(session)?.disappeared(status, context: context)
            }
    }
}

extension InterestSignal.Context {
    /// The context a timeline's rows are read in, in the server's words.
    init(key: TimelineKey) {
        switch key.mode {
        case .photos:
            self = .photos
        case .video:
            self = .videos
        case .shorts:
            self = .shorts
        case .home, .news, .audio:
            switch key.source {
            case .local: self = .local
            case .federated: self = .federated
            case .hashtag: self = .tag
            default: self = .home
            }
        }
    }
}
