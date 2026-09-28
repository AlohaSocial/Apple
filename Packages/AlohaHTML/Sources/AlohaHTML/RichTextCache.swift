// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// Parses off the main actor and remembers the answer by content hash.
///
/// A row that scrolls into view with an uncached parse renders plain text for
/// one frame and upgrades — it never blocks (docs/05 §3).
public actor RichTextCache {
    public static let shared = RichTextCache()

    private let parser = StatusHTMLParser()
    private var storage: [Key: RichText] = [:]
    private var insertionOrder: [Key] = []
    private let capacity: Int

    public init(capacity: Int = 2000) {
        self.capacity = capacity
    }

    struct Key: Hashable, Sendable {
        let contentHash: Int
        let mentionsHash: Int
        let tagsHash: Int
        let emojisHash: Int
    }

    public func richText(for status: Status) -> RichText {
        let target = status.displayed
        let key = Key(
            contentHash: target.content.hashValue,
            mentionsHash: target.mentions.hashValue,
            tagsHash: target.tags.hashValue,
            emojisHash: target.emojis.hashValue
        )

        if let cached = storage[key] { return cached }

        let parsed = parser.parse(
            target.content,
            mentions: target.mentions,
            tags: target.tags,
            emojis: target.emojis
        )
        insert(parsed, for: key)
        return parsed
    }

    /// The content-warning line, which is plain text on the wire but can still
    /// carry custom emoji.
    public func spoilerRichText(for status: Status) -> RichText {
        let target = status.displayed
        guard !target.spoilerText.isEmpty else { return .empty }
        return parser.parse("<p>\(target.spoilerText)</p>", emojis: target.emojis)
    }

    public func plainText(for status: Status) -> String {
        richText(for: status).plainText
    }

    private func insert(_ value: RichText, for key: Key) {
        if storage[key] == nil {
            insertionOrder.append(key)
            if insertionOrder.count > capacity {
                let evicted = insertionOrder.removeFirst()
                storage.removeValue(forKey: evicted)
            }
        }
        storage[key] = value
    }

    public func removeAll() {
        storage.removeAll()
        insertionOrder.removeAll()
    }
}
