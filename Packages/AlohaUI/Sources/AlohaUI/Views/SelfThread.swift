// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// A thread somebody wrote to themselves: one post, then their own reply to
/// it, then their reply to that — the way a long piece gets written on a
/// server with a character limit. Unrolled, it reads as one article.
///
/// Worked out from the context a thread screen already fetched, so offering
/// "Read as article" costs no request of its own.
nonisolated enum SelfThread {
    /// Two posts in a row is a post and an afterthought. Three is a thread
    /// somebody meant to write.
    static let minimumLength = 3

    /// The author's own run through a conversation, in reading order, with
    /// everybody else's replies left out.
    ///
    /// Two starting points are tried, and the longer run wins:
    /// - the top of the opened post's own run — walking up while each parent
    ///   is by the same author — for a post opened from the middle of a
    ///   thread;
    /// - the conversation's first post, for a thread opened at somebody
    ///   else's reply to it.
    ///
    /// Going down, the next post is the author's own reply to the current
    /// one. Where they replied to the same post twice (a correction, an
    /// aside), the earlier reply carries the thread on.
    static func unroll(
        ancestors: [Status], focused: Status, descendants: [Status]
    ) -> [Status] {
        var byID: [String: Status] = [:]
        for status in ancestors + [focused] + descendants where byID[status.id] == nil {
            byID[status.id] = status
        }
        var children: [String: [Status]] = [:]
        for status in byID.values {
            guard let parent = status.inReplyToID else { continue }
            children[parent, default: []].append(status)
        }

        var top = focused
        var climbed: Set<String> = [focused.id]
        while let parentID = top.inReplyToID, let parent = byID[parentID],
            parent.account.id == top.account.id, climbed.insert(parent.id).inserted
        {
            top = parent
        }

        var starts = [top]
        if let root = ancestors.first, root.id != top.id { starts.append(root) }

        var best: [Status] = []
        for start in starts {
            let run = chain(from: start, children: children)
            if run.count > best.count { best = run }
        }
        return best
    }

    /// Whether a conversation holds a thread worth offering as an article.
    static func isLongEnough(_ run: [Status]) -> Bool {
        run.count >= minimumLength
    }

    private static func chain(from start: Status, children: [String: [Status]]) -> [Status] {
        var run = [start]
        var seen: Set<String> = [start.id]
        var current = start
        while let next = (children[current.id] ?? [])
            .filter({ $0.account.id == start.account.id && !seen.contains($0.id) })
            .min(by: { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) })
        {
            run.append(next)
            seen.insert(next.id)
            current = next
        }
        return run
    }

    /// Whether a timeline post is the author answering themselves — the one
    /// sign a single row carries that it sits inside a self-thread. The
    /// thread's *first* post carries none: nothing in it says the author
    /// went on, and finding out is a context request per row.
    static func continuesOwnThread(_ status: Status) -> Bool {
        let post = status.displayed
        guard post.inReplyToID != nil, let parentAuthor = post.inReplyToAccountID else {
            return false
        }
        return parentAuthor == post.account.id
    }
}
