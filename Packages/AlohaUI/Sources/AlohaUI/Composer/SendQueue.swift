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

    /// Sends one draft and the rest of its thread.
    ///
    /// Every post goes out with the key of its place in the thread, so a
    /// segment whose earlier attempt landed unseen is recognised rather than
    /// repeated. Whatever stops the thread part-way — a dropped connection or
    /// a refusal — leaves the draft as what is left of it: the next segment,
    /// replying to the last post that made it. The first post is never sent
    /// twice.
    static func send(_ draft: DraftSnapshot, session: AccountSession) async -> Outcome {
        var current = draft
        var posted = 0
        do {
            while true {
                let status = try await session.client.decode(
                    Status.self,
                    from: Endpoint.composing.post(
                        try await current.statusPost(
                            session: session, total: draft.threadTotal)))
                session.notePosted(status)
                try? await session.timelineStore.updateStatus(
                    accountID: session.id, status: status)
                posted += 1
                guard !current.threadSegments.isEmpty else { break }
                current = current.resuming(
                    afterPosted: current.threadPosition + 1, lastPostedID: status.id)
            }
            try? await session.supportStore.deleteDraft(id: draft.id)
            return .sent
        } catch {
            // Part of the thread is out: keep only what is left, still queued
            // and under the same draft, so the outcome below — later or
            // refused — applies to that.
            if posted > 0 {
                current.queuedForSend = true
                _ = try? await session.supportStore.saveDraft(current)
            }
            return await outcome(of: error, sending: current, session: session)
        }
    }

    /// What a failure means for the queue: wait, or give this one up.
    private static func outcome(
        of error: any Error, sending draft: DraftSnapshot, session: AccountSession
    ) async -> Outcome {
        guard let error = error as? APIError else { return .later }
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
    }
}

extension DraftSnapshot {
    /// How many posts the whole thread has, counting those already out.
    var threadTotal: Int { threadPosition + 1 + threadSegments.count }

    /// The post a queued draft sends, exactly as the composer would have: the
    /// games played, the AI label and the card added, the team, the place and
    /// the video's details carried, numbered where the account numbers its
    /// threads, and keyed by its place in the thread.
    @MainActor
    func statusPost(session: AccountSession, total: Int) async throws -> StatusPost {
        let isNextcloud = session.capabilities.isNextcloudSocial
        var body = ComposerCommands.resolve(text).text
        if threadPosition > 0, total > 1, session.settings.appendThreadNumbering {
            body = ComposerModel.numbered(body, position: threadPosition, total: total)
        }
        if isNextcloud, marksAsAIGenerated {
            body = ComposerModel.labelledAsAIGenerated(body)
        }
        var mediaIDs = uploadedMediaIDs
        if let cardBackgroundID,
            let card = try await ComposerModel.uploadCard(
                text: text, backgroundID: cardBackgroundID, session: session)
        {
            mediaIDs = [card]
        }
        var post = StatusPost(
            text: body, visibility: visibility,
            spoilerText: spoilerText.isEmpty ? nil : spoilerText,
            sensitive: sensitive, language: language, inReplyToID: inReplyToID,
            mediaIDs: mediaIDs, pollOptions: pollOptions, pollExpiresIn: pollExpiresIn,
            pollMultiple: pollMultiple, scheduledAt: scheduledAt,
            idempotencyKey: idempotencyKey(forPosition: threadPosition),
            quotedID: quotedID, quotePolicy: quotePolicy,
            placeID: placeID, placeName: placeID == nil ? placeName : nil,
            placeCountry: placeID == nil ? placeCountry : nil,
            postAs: postAs, videoTitle: videoTitle, videoCategory: videoCategory,
            videoLicence: videoLicence)
        if isNextcloud { post.replyPolicy = replyPolicy.flatMap(ReplyPolicy.init(rawValue:)) }
        return post
    }
}
