// SPDX-License-Identifier: MIT

import AlohaNetwork
import Foundation

/// "On this day", as the app last fetched it, for the Memories widget.
///
/// Memories are not in the SwiftData cache — they are a server query, not a
/// timeline — and a widget never downloads (docs/09 §8). So the app writes
/// the day's few posts here, with a small picture each, and the widget reads
/// nothing else.
public struct MemoriesSnapshot: Codable, Sendable, Equatable {
    public struct Memory: Codable, Sendable, Equatable, Identifiable {
        /// The post's id on the account's server.
        public var id: String
        public var author: String
        /// Plain text, or the content warning where the post has one: the
        /// widget shows what the timeline would before it is opened.
        public var text: String
        public var createdAt: Date
        /// A file in the snapshot's directory, when the post had a picture
        /// that is not behind a warning.
        public var imageFile: String?

        public init(id: String, author: String, text: String, createdAt: Date, imageFile: String?) {
            self.id = id
            self.author = author
            self.text = text
            self.createdAt = createdAt
            self.imageFile = imageFile
        }
    }

    public var accountID: UUID
    /// The local day the snapshot answers for, as `yyyy-MM-dd`: a snapshot
    /// from yesterday is somebody else's "on this day".
    public var day: String
    public var memories: [Memory]

    public init(accountID: UUID, day: String, memories: [Memory]) {
        self.accountID = accountID
        self.day = day
        self.memories = memories
    }

    /// `yyyy-MM-dd` in the given calendar's time zone.
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Where the snapshot and its pictures live: a folder of the app group.
public struct MemoriesSnapshotStore: Sendable {
    /// The widget's kind, which the app reloads after writing a snapshot.
    public static let widgetKind = "Memories"

    public let directory: URL

    static let fileName = "memories.json"
    static let imagePrefix = "memory-"

    public init(directory: URL) {
        self.directory = directory
    }

    /// The app group's folder, or nil where the group is off — then there is
    /// no widget that could read it, and nothing is written.
    public static var shared: MemoriesSnapshotStore? {
        guard AppGroup.isEnabled,
            let group = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppGroup.identifier)
        else { return nil }
        return MemoriesSnapshotStore(directory: group.appending(path: "Widgets"))
    }

    public func read() -> MemoriesSnapshot? {
        guard let data = try? Data(contentsOf: directory.appending(path: Self.fileName)) else {
            return nil
        }
        return try? JSONDecoder().decode(MemoriesSnapshot.self, from: data)
    }

    /// Whether what is stored already answers for this account on this day.
    public func isCurrent(accountID: UUID, day: String) -> Bool {
        guard let snapshot = read() else { return false }
        return snapshot.accountID == accountID && snapshot.day == day
    }

    /// Writes the snapshot and its pictures, keyed by memory id, and removes
    /// pictures no memory names any more.
    public func write(_ snapshot: MemoriesSnapshot, images: [String: Data]) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)

        var stored = snapshot
        for index in stored.memories.indices {
            let memory = stored.memories[index]
            guard let data = images[memory.id] else {
                stored.memories[index].imageFile = nil
                continue
            }
            let name = Self.imageName(for: memory.id)
            try data.write(to: directory.appending(path: name), options: .atomic)
            stored.memories[index].imageFile = name
        }

        let kept = Set(stored.memories.compactMap(\.imageFile))
        let existing = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in existing where name.hasPrefix(Self.imagePrefix) && !kept.contains(name) {
            try? manager.removeItem(at: directory.appending(path: name))
        }

        let data = try JSONEncoder().encode(stored)
        try data.write(to: directory.appending(path: Self.fileName), options: .atomic)
    }

    public func imageURL(for memory: MemoriesSnapshot.Memory) -> URL? {
        memory.imageFile.map { directory.appending(path: $0) }
    }

    /// A post id is the server's and may hold anything; the file name keeps
    /// only what a file name can.
    static func imageName(for id: String) -> String {
        let safe = id.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return "\(imagePrefix)\(String(String.UnicodeScalarView(safe))).jpg"
    }
}
