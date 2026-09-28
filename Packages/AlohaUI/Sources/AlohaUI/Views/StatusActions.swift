// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import Foundation

/// Actions that reach the server. Optimistic where the answer is predictable,
/// reconciled against what comes back, reverted with an explanation on failure
/// (docs/08 §8).
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

    public static func perform(_ action: StatusRowAction, session: AccountSession) async {
        // A cue for the three things a finger does to a post, and only while
        // they are being turned *on* — a tick for undoing a like reads as a
        // second like (docs/05 §3).
        await cue(for: action)

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

        // Answered by the shell, because each presents something or navigates.
        // Listed rather than left to a `default:` — a bare default is how six
        // actions silently did nothing, and an exhaustive switch makes the next
        // added case a compile error instead of a dead menu item.
        case .open, .watch, .reply, .openProfile, .openMedia, .openCard, .followLink,
            .report, .share, .translate, .edit, .delete, .block, .mute,
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

    public static func delete(_ status: Status, session: AccountSession) async {
        do {
            _ = try await session.client.send(Endpoint.statuses.delete(status.displayed.id))
            try await session.timelineStore.deleteStatus(
                accountID: session.id, serverID: status.displayed.id)
        } catch {
            await session.handle(error)
        }
    }

    /// Blocking and muting both take effect locally at once — a person who has
    /// just blocked somebody should not keep seeing them while a refresh
    /// happens (docs/11 §1.3).
    public static func moderate(
        _ request: ModerationRequest, session: AccountSession
    ) async {
        let endpoint: Endpoint
        switch request.kind {
        case .block:
            endpoint = Endpoint.accounts.simpleAction(request.account.id, "block")
        case .mute:
            endpoint = Endpoint.accounts.mute(
                request.account.id, notifications: true, duration: nil)
        }

        do {
            _ = try await session.client.decode(Relationship.self, from: endpoint)
            try await session.timelineStore.removeEverything(
                fromAccount: request.account.id, accountID: session.id)
        } catch {
            await session.handle(error)
        }
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
