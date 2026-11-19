// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Synchronization

/// Parses status HTML once and remembers the answer by content.
///
/// A lock rather than an actor, so that a row can ask "is this post parsed?"
/// synchronously, in the middle of laying itself out, the way `ImageLoader`
/// answers `memoryImage`. As an actor every row's first layout drew a
/// regex-stripped stand-in, with its paragraphs run together, and grew when
/// the real text landed a frame later — which moved a list being scrolled
/// upwards by the difference (docs/05 §3). Pages are parsed off the main
/// actor as they arrive (`warm`), so a timeline row finds its text here.
///
/// The lock is held only to read or write the table, never while parsing:
/// two threads may parse the same post at once, and the second simply
/// stores the same answer.
public final class RichTextCache: Sendable {
    public static let shared = RichTextCache()

    /// A parse and its layout, worked out together so they cannot disagree
    /// and the renderer does neither on the main actor.
    public struct Entry: Sendable, Hashable {
        public let richText: RichText
        public let layout: RichTextLayout

        public init(_ richText: RichText) {
            self.richText = richText
            self.layout = RichTextLayout(richText)
        }
    }

    /// What a parse depends on, compared by value: keying on hash values
    /// alone let two posts whose hashes collided share one body.
    struct Key: Hashable, Sendable {
        let content: String
        let mentions: [Status.Mention]
        let tags: [Status.StatusTag]
        let emojis: [CustomEmoji]

        init(_ status: Status) {
            let target = status.displayed
            content = target.content
            mentions = target.mentions
            tags = target.tags
            emojis = target.emojis
        }
    }

    private struct Storage {
        var entries: [Key: Entry] = [:]
        /// Oldest first; the head is evicted when the table is full.
        var order: [Key] = []
    }

    private let parser = StatusHTMLParser()
    private let storage = Mutex(Storage())
    private let capacity: Int

    /// The largest body a view may parse in place when it finds no entry —
    /// a post that arrived by some path other than a timeline page (a
    /// notification, a quote, a thread). A Mastodon post is a few kilobytes
    /// of HTML at most and parses in well under a millisecond; anything
    /// larger is parsed off the main actor (`richText(for:)`).
    public static let inlineParseLimit = 8 * 1024

    public init(capacity: Int = 2000) {
        self.capacity = max(1, capacity)
    }

    // MARK: - Synchronous

    /// The entry for a post if it has been parsed, without parsing it.
    /// Cheap enough to call from a view's body.
    public func cachedEntry(for status: Status) -> Entry? {
        let key = Key(status)
        return storage.withLock { $0.entries[key] }
    }

    /// The entry for a post, parsed on the calling thread if needed. For
    /// callers already off the main actor; a view uses `immediateEntry`.
    public func entry(for status: Status) -> Entry {
        let key = Key(status)
        if let cached = storage.withLock({ $0.entries[key] }) { return cached }
        let target = status.displayed
        let parsed = Entry(
            parser.parse(
                target.content, mentions: target.mentions, tags: target.tags,
                emojis: target.emojis))
        insert(parsed, for: key)
        return parsed
    }

    /// What a view may draw on its first layout: the cached entry, or a parse
    /// made now when the body is small enough not to cost a frame. Nil only
    /// for an uncached body over `inlineParseLimit`.
    public func immediateEntry(for status: Status) -> Entry? {
        if let cached = cachedEntry(for: status) { return cached }
        guard status.displayed.content.utf8.count <= Self.inlineParseLimit else { return nil }
        return entry(for: status)
    }

    // MARK: - Off the caller's actor

    /// Parses a page of posts before its rows are handed to a list, so each
    /// row finds its final text on its first layout. Returns each post's web
    /// links by status id, from the same parse, for the links rotor.
    ///
    /// A cached timeline is up to five hundred posts at launch; those are
    /// parsed in slices side by side, so the first paint waits on a fraction
    /// of the work.
    @concurrent
    public func warm(_ statuses: [Status]) async -> [String: [URL]] {
        let slice = 40
        guard statuses.count > slice else { return links(in: statuses[...]) }
        return await withTaskGroup(of: [String: [URL]].self) { group in
            for start in stride(from: 0, to: statuses.count, by: slice) {
                let part = statuses[start..<min(start + slice, statuses.count)]
                group.addTask { self.links(in: part) }
            }
            var all: [String: [URL]] = [:]
            for await found in group { all.merge(found) { _, new in new } }
            return all
        }
    }

    private func links(in statuses: ArraySlice<Status>) -> [String: [URL]] {
        var links: [String: [URL]] = [:]
        for status in statuses {
            let found = entry(for: status).richText.webLinks
            if !found.isEmpty { links[status.id] = found }
        }
        return links
    }

    /// The entry for a post, parsed off the caller's actor if needed — for a
    /// body too large for `immediateEntry`.
    @concurrent
    public func parsedEntry(for status: Status) async -> Entry {
        entry(for: status)
    }

    @concurrent
    public func richText(for status: Status) async -> RichText {
        entry(for: status).richText
    }

    @concurrent
    public func plainText(for status: Status) async -> String {
        entry(for: status).richText.plainText
    }

    /// The content-warning line, which is plain text on the wire but can still
    /// carry custom emoji.
    @concurrent
    public func spoilerRichText(for status: Status) async -> RichText {
        let target = status.displayed
        guard !target.spoilerText.isEmpty else { return .empty }
        return parser.parse("<p>\(target.spoilerText)</p>", emojis: target.emojis)
    }

    public func removeAll() {
        storage.withLock {
            $0.entries.removeAll()
            $0.order.removeAll()
        }
    }

    private func insert(_ value: Entry, for key: Key) {
        let capacity = capacity
        storage.withLock { storage in
            guard storage.entries.updateValue(value, forKey: key) == nil else { return }
            storage.order.append(key)
            guard storage.order.count > capacity else { return }
            // A tenth at a time, so the shift of the array is not paid on
            // every insert once the table is full.
            let excess = min(storage.order.count, max(1, capacity / 10))
            for evicted in storage.order.prefix(excess) {
                storage.entries.removeValue(forKey: evicted)
            }
            storage.order.removeFirst(excess)
        }
    }
}
