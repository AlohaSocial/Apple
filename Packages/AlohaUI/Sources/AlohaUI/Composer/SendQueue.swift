// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation
import Network
import OSLog
import Observation

/// Posts what was written while the server could not be reached.
///
/// A post that fails for a reason that says nothing about the post — no
/// network, a timeout, a 5xx — is saved as a draft with `queuedForSend`, and
/// the composer says "Will post when you're online". This is what keeps that
/// promise (docs/07 §7): it drains on the way back to the foreground, when the
/// network returns, and in a background refresh. In order, one at a time, with
/// the key the draft was saved with, so a first attempt that did land is
/// recognised by the server rather than posted twice.
@MainActor
@Observable
public final class SendQueue {
    /// How many posts went out on the last pass, for anything that wants to
    /// say so.
    public private(set) var lastSentCount = 0

    private var isDraining = false
    private weak var environment: AppEnvironment?
    @ObservationIgnored private var monitor: NWPathMonitor?
    private let logger = Logger(subsystem: "social.aloha.app", category: "send-queue")

    public init() {}

    /// Starts listening for the network to come back. Idempotent.
    public func attach(to environment: AppEnvironment) {
        self.environment = environment
        guard monitor == nil else { return }

        let monitor = NWPathMonitor()
        // The first update reports the current path, which is itself a fine
        // moment to drain: the app has just started.
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.drainAll() }
        }
        monitor.start(queue: DispatchQueue(label: "social.aloha.app.send-queue"))
        self.monitor = monitor
    }

    /// Drains every signed-in account's queue.
    public func drainAll() async {
        guard let environment, !isDraining else { return }
        isDraining = true
        defer { isDraining = false }

        var sent = 0
        for session in environment.sessions where !session.needsReauthentication {
            sent += await Self.drain(session: session)
        }
        lastSentCount = sent
        if sent > 0 { logger.info("sent \(sent, privacy: .public) queued posts") }
    }

    /// One account's queue. Returns how many posts went out.
    ///
    /// Stops at the first failure that could pass: the next post must not
    /// overtake one still waiting, or a thread comes out of order. A refusal
    /// takes that one post off the queue with the server's reason, because
    /// what was refused once will be refused again — it waits in Drafts.
    @discardableResult
    static func drain(session: AccountSession) async -> Int {
        guard let queued = try? await session.supportStore.queuedDrafts(accountID: session.id)
        else { return 0 }

        var sent = 0
        for draft in queued {
            switch await send(draft, session: session) {
            case .sent:
                sent += 1
            case .refused(let message):
                try? await session.supportStore.markSendFailed(id: draft.id, message: message)
            case .later:
                return sent
            }
        }
        return sent
    }

    enum Outcome: Equatable {
        case sent
        case refused(String)
        case later
    }

    static func send(_ draft: DraftSnapshot, session: AccountSession) async -> Outcome {
        do {
            let posted = try await session.client.decode(
                Status.self, from: Endpoint.composing.post(draft.statusPost))
            session.notePosted(posted)
            try? await session.timelineStore.updateStatus(accountID: session.id, status: posted)

            // The rest of a thread chains off the post that just went out. A
            // segment that fails leaves the remainder queued under the same
            // draft, now replying to the last segment that made it.
            var parentID = posted.id
            var remaining = draft.threadSegments
            while let next = remaining.first {
                do {
                    let reply = try await session.client.decode(
                        Status.self,
                        from: Endpoint.composing.post(
                            StatusPost(
                                text: next, visibility: draft.visibility,
                                spoilerText: draft.spoilerText.isEmpty ? nil : draft.spoilerText,
                                sensitive: draft.sensitive, language: draft.language,
                                inReplyToID: parentID)))
                    parentID = reply.id
                    session.notePosted(reply)
                    remaining.removeFirst()
                } catch {
                    var rest = draft
                    rest.text = next
                    rest.threadSegments = Array(remaining.dropFirst())
                    rest.inReplyToID = parentID
                    rest.uploadedMediaIDs = []
                    rest.pollOptions = []
                    rest.quotedID = nil
                    rest.scheduledAt = nil
                    rest.idempotencyKey = UUID().uuidString
                    _ = try? await session.supportStore.saveDraft(rest)
                    return .later
                }
            }

            try? await session.supportStore.deleteDraft(id: draft.id)
            return .sent
        } catch let error as APIError {
            if error.isTransient { return .later }
            // A 401 pauses this account's queue and raises the sign-in banner;
            // nothing is discarded (docs/07 §7).
            await session.handle(error)
            if error.requiresReauthentication { return .later }
            if case .notFound = error, !draft.uploadedMediaIDs.isEmpty {
                return .refused(
                    String(
                        localized:
                            "Its attachments expired on your server before it could be sent. Open it to add them again.",
                        comment: "Queued post refused because its uploads are gone"))
            }
            return .refused(
                error.errorDescription
                    ?? String(localized: "Couldn't post that.", comment: "Post failed"))
        } catch {
            return .later
        }
    }
}

extension DraftSnapshot {
    /// The post a queued draft sends, exactly as the composer would have.
    var statusPost: StatusPost {
        StatusPost(
            text: text, visibility: visibility,
            spoilerText: spoilerText.isEmpty ? nil : spoilerText,
            sensitive: sensitive, language: language, inReplyToID: inReplyToID,
            mediaIDs: uploadedMediaIDs, pollOptions: pollOptions, pollExpiresIn: pollExpiresIn,
            pollMultiple: pollMultiple, scheduledAt: scheduledAt,
            idempotencyKey: idempotencyKey, quotedID: quotedID, quotePolicy: quotePolicy)
    }
}
