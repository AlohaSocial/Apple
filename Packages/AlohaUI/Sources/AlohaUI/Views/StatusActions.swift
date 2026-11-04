// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import Foundation

/// Actions that reach the server. Optimistic where the answer is predictable,
/// reconciled against what comes back, reverted with an explanation on failure
/// (docs/08 §8).
///
/// On the main actor: every action updates the session and the visible
/// rows, which SwiftUI reads there.
@MainActor
public enum StatusActions {

    // MARK: - Nextcloud Social extras

    /// Archive is Pixelfed's: the post leaves the profile and the timelines
    /// but is neither deleted nor federated as gone. The server answers
    /// `{code: 200}` rather than a status, so the local copy is updated by
    /// hand and the row is taken out of the cache while archived.
    static func archive(_ status: Status, session: AccountSession) async {
        let target = status.displayed
        let isArchived = target.archived == true
        let endpoint =
            isArchived
            ? Endpoint.statusExtras.unarchive(target.id)
            : Endpoint.statusExtras.archive(target.id)
        do {
            _ = try await session.client.send(endpoint)
            var updated = target
            updated.archived = !isArchived
            if isArchived {
                try await session.timelineStore.updateStatus(accountID: session.id, status: updated)
            } else {
                try await session.timelineStore.deleteStatus(
                    accountID: session.id, serverID: target.id)
            }
        } catch {
            await session.handle(error)
        }
    }

    /// Pin to, or unpin from, the profile. Mastodon's own route pair.
    static func pin(_ status: Status, session: AccountSession) async {
        await toggle(status: status, session: session, on: status.displayed.pinned ? .unpin : .pin)
    }

    /// PeerTube's thumbs-down, on a video. Optimistic, like a favourite.
    static func dislike(_ status: Status, session: AccountSession) async {
        let target = status.displayed
        let endpoint =
            target.disliked
            ? Endpoint.statusExtras.undislike(target.id)
            : Endpoint.statusExtras.dislike(target.id)
        var optimistic = target
        optimistic.disliked.toggle()
        optimistic.dislikesCount = max(0, target.dislikesCount + (target.disliked ? -1 : 1))
        try? await session.timelineStore.updateStatus(accountID: session.id, status: optimistic)
        do {
            let updated = try await session.client.decode(Status.self, from: endpoint)
            try await session.timelineStore.updateStatus(accountID: session.id, status: updated)
        } catch {
            try? await session.timelineStore.updateStatus(accountID: session.id, status: target)
            await session.handle(error)
        }
    }

    /// Who may reply, changed after posting. The server answers the status,
    /// which is written back as it is rather than as it was guessed.
    static func setReplyPolicy(
        _ status: Status, _ policy: ReplyPolicy, session: AccountSession
    ) async {
        let target = status.displayed
        do {
            let updated = try await session.client.decode(
                Status.self, from: Endpoint.replyControls.setReplyPolicy(target.id, policy))
            try await session.timelineStore.updateStatus(accountID: session.id, status: updated)
        } catch {
            await session.handle(error)
        }
    }

    /// Hides a reply to one of the reader's own posts, or shows it again.
    /// Optimistic: the row collapses at once, and comes back if refused.
    static func hideReply(_ status: Status, session: AccountSession) async {
        let target = status.displayed
        let hide = !target.isHiddenByAuthor
        var optimistic = target
        optimistic.hiddenByAuthor = hide
        try? await session.timelineStore.updateStatus(accountID: session.id, status: optimistic)
        NotificationCenter.default.post(name: replyVisibilityChanged, object: optimistic)
        do {
            let endpoint =
                hide
                ? Endpoint.replyControls.hide(target.id)
                : Endpoint.replyControls.unhide(target.id)
            let updated = try await session.client.decode(Status.self, from: endpoint)
            try await session.timelineStore.updateStatus(accountID: session.id, status: updated)
            NotificationCenter.default.post(name: replyVisibilityChanged, object: updated)
        } catch {
            try? await session.timelineStore.updateStatus(accountID: session.id, status: target)
            NotificationCenter.default.post(name: replyVisibilityChanged, object: target)
            await session.handle(error)
        }
    }

    /// Posted with the reply as it now stands, so a thread on screen — which
    /// holds its replies itself rather than reading the cache — can follow.
    public static let replyVisibilityChanged = Notification.Name(
        "alohasocial.reply.visibilityChanged")

    public static func perform(_ action: StatusRowAction, session: AccountSession) async {
        // A cue for the three things a finger does to a post, and only while
        // they are being turned *on* — a tick for undoing a like reads as a
        // second like (docs/05 §3).
        cue(for: action)

        switch action {
        case .favourite(let status):
            await toggle(
                status: status, session: session,
                on: status.displayed.favourited ? .unfavourite : .favourite)
        case .boost(let status):
            await toggle(
                status: status, session: session,
                on: status.displayed.reblogged ? .unreblog : .reblog)
        case .bookmark(let status):
            await toggle(
                status: status, session: session,
                on: status.displayed.bookmarked ? .unbookmark : .bookmark)
        case .muteConversation(let status):
            await toggle(
                status: status, session: session,
                on: status.displayed.muted ? .unmute : .mute)
        case .vote(let pollID, let choices):
            await vote(pollID: pollID, choices: choices, session: session)
        case .react(let status, let name, let add):
            await react(status, name: name, add: add, session: session)
        case .archive(let status):
            await archive(status, session: session)
        case .pin(let status):
            await pin(status, session: session)
        case .dislike(let status):
            await dislike(status, session: session)
        case .setReplyPolicy(let status, let policy):
            await setReplyPolicy(status, policy, session: session)
        case .hideReply(let status):
            await hideReply(status, session: session)

        // Answered by the shell, because each presents something or navigates.
        // Listed rather than left to a `default:` — a bare default is how six
        // actions silently did nothing, and an exhaustive switch makes the next
        // added case a compile error instead of a dead menu item.
        case .open, .watch, .reply, .openProfile, .openMedia, .openCard, .followLink,
            .report, .share, .translate, .edit, .delete, .redraft, .block, .mute,
            .quote, .showDelivery, .showEditHistory, .quoteControls, .tagPeople,
            .addToCollection, .addToList:
            break
        }
    }

    @MainActor
    private static func cue(for action: StatusRowAction) {
        switch action {
        case .favourite(let status) where !status.displayed.favourited:
            Senses.shared.feel(.like)
        case .boost(let status) where !status.displayed.reblogged:
            Senses.shared.feel(.interact)
        case .react(_, _, let add) where add:
            Senses.shared.feel(.interact)
        default:
            break
        }
    }

    /// An edit composer must load the original plain text, never the rendered
    /// HTML (docs/07 §8).
    public static func source(
        of status: Status, session: AccountSession
    ) async -> StatusSource? {
        do {
            return try await session.client.decode(
                StatusSource.self, from: Endpoint.statuses.source(status.displayed.id))
        } catch {
            await session.handle(error)
            return nil
        }
    }

    /// Deletes a post, and says so when the server would not. The row only
    /// leaves the cache once the server has agreed, so a refusal leaves
    /// nothing to put back — but it must be heard: a post the person believes
    /// gone while it is still public is the worst way this can fail.
    ///
    /// - Returns: nil when deleted, otherwise what to tell the person.
    @discardableResult
    public static func delete(_ status: Status, session: AccountSession) async -> String? {
        do {
            _ = try await session.client.send(Endpoint.statuses.delete(status.displayed.id))
        } catch {
            await session.handle(error)
            return failureMessage(
                error,
                fallback: String(
                    localized: "The post could not be deleted. It is still up.",
                    comment: "Delete failure"))
        }
        // The server has deleted it; a cache that could not be written is
        // repaired by the next refresh and is not the person's problem.
        try? await session.timelineStore.deleteStatus(
            accountID: session.id, serverID: status.displayed.id)
        return nil
    }

    /// Blocking and muting both take effect locally at once — a person who has
    /// just blocked somebody should not keep seeing them while a refresh
    /// happens (docs/11 §1.3). The store announces what it removed, and every
    /// list on screen drops those rows (`StatusRemovals`); a deletion goes
    /// the same way.
    ///
    /// - Returns: nil when it took effect, otherwise what to tell the person.
    ///   A block that failed without a word leaves somebody able to reach a
    ///   person who believes they no longer can, so a failure is always said.
    @discardableResult
    public static func moderate(
        _ request: ModerationRequest, session: AccountSession
    ) async -> String? {
        await moderate(request.kind, account: request.account.id, session: session)
    }

    /// The same, for a block or mute that does not come from a confirmation
    /// — the "also block" after a report.
    @discardableResult
    static func moderate(
        _ kind: ModerationRequest.Kind, account accountID: String, session: AccountSession
    ) async -> String? {
        do {
            _ = try await session.client.decode(
                Relationship.self, from: moderationEndpoint(kind, account: accountID))
        } catch {
            await session.handle(error)
            return failureMessage(error, fallback: moderationFailure(kind))
        }
        try? await session.timelineStore.removeEverything(
            fromAccount: accountID, accountID: session.id)
        return nil
    }

    static func moderationEndpoint(_ kind: ModerationRequest.Kind, account: String) -> Endpoint {
        switch kind {
        case .block:
            Endpoint.accounts.simpleAction(account, "block")
        case .mute:
            Endpoint.accounts.mute(account, notifications: true, duration: nil)
        }
    }

    static func moderationFailure(_ kind: ModerationRequest.Kind) -> String {
        switch kind {
        case .block:
            String(
                localized: "The block did not go through. They can still see and reach you.",
                comment: "Block failure")
        case .mute:
            String(
                localized: "The mute did not go through. Their posts will still appear.",
                comment: "Mute failure")
        }
    }

    /// Ours first, so the person knows what did not happen, then the server's
    /// own words where it gave some.
    static func failureMessage(_ error: any Error, fallback: String) -> String {
        guard let description = (error as? APIError)?.errorDescription, !description.isEmpty
        else { return fallback }
        return "\(fallback) \(description)"
    }

    /// Emoji reactions are a Nextcloud Social, Misskey and Pleroma extension;
    /// Mastodon has none, which is why the row only appears where detected.
    private static func react(
        _ status: Status, name: String, add: Bool, session: AccountSession
    ) async {
        let id = status.displayed.id
        let endpoint =
            add
            ? Endpoint.statuses.react(id, emoji: name)
            : Endpoint.statuses.unreact(id, emoji: name)
        do {
            let updated = try await session.client.decode(Status.self, from: endpoint)
            try await session.timelineStore.updateStatus(accountID: session.id, status: updated)
        } catch {
            await session.handle(error)
        }
    }

    private static func toggle(
        status: Status, session: AccountSession, on action: Endpoint.StatusAction
    ) async {
        let target = status.displayed
        do {
            let updated = try await session.client.decode(
                Status.self, from: Endpoint.statuses.action(target.id, action))
            // The server's answer is authoritative — counts move there too.
            try await session.timelineStore.updateStatus(accountID: session.id, status: updated)
        } catch {
            await session.handle(error)
        }
    }

    private static func vote(pollID: String, choices: [Int], session: AccountSession) async {
        do {
            _ = try await session.client.decode(
                Poll.self, from: Endpoint.statuses.vote(pollID: pollID, choices: choices))
        } catch {
            await session.handle(error)
        }
    }
}
