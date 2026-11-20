// SPDX-License-Identifier: MIT

import AlohaNetwork
import CryptoKit
import Foundation

/// Everything the snapshot-backed widgets and the countdown Live Activities
/// show for one account, as the app last fetched it.
///
/// Direct messages and photos (the widgets), and scheduled posts and the
/// account's own poll (the countdowns, docs/09 §9) are server queries rather
/// than cached timelines, and a widget never downloads (docs/09 §8). The app
/// writes this when it becomes active and on background refresh
/// (`WidgetSnapshotWriter`), and the widgets read nothing else.
///
/// Every section is optional: nil means "not fetched", which a widget says
/// differently from "none".
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public var accountID: UUID
    public var handle: String
    public var writtenAt: Date

    // A snapshot written by a build that still had the requests, reports,
    // statistics, trends and people widgets carries those sections too; the
    // decoder skips keys it does not know, so it reads as it is.
    public var messages: Messages?
    public var scheduled: [ScheduledPost]?
    /// The newest poll of the account's own, open or closed within a day.
    public var poll: Poll?
    public var photoSets: [PhotoSet]

    public init(
        accountID: UUID, handle: String, writtenAt: Date = Date(), messages: Messages? = nil,
        scheduled: [ScheduledPost]? = nil, poll: Poll? = nil, photoSets: [PhotoSet] = []
    ) {
        self.accountID = accountID
        self.handle = handle
        self.writtenAt = writtenAt
        self.messages = messages
        self.scheduled = scheduled
        self.poll = poll
        self.photoSets = photoSets
    }

    /// Every picture file the snapshot names.
    public var imageFiles: Set<String> {
        var files = Set<String>()
        for row in messages?.conversations ?? [] {
            if let file = row.avatarFile { files.insert(file) }
        }
        for set in photoSets { files.formUnion(set.photos.map(\.imageFile)) }
        return files
    }

    public func photoSet(for source: WidgetPhotoSource) -> PhotoSet? {
        photoSets.first { $0.sourceKey == source.key }
    }

    // MARK: - Sections

    public struct Messages: Codable, Sendable, Equatable {
        /// Conversations with something unread, counted across the page read.
        public var unread: Int
        public var conversations: [ConversationRow]

        public init(unread: Int, conversations: [ConversationRow]) {
            self.unread = unread
            self.conversations = conversations
        }
    }

    public struct ConversationRow: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        /// The other participants' names, joined.
        public var names: String
        public var text: String
        public var date: Date
        public var unread: Bool
        /// The newest message, which a tap opens as a thread.
        public var lastStatusID: String?
        public var avatarFile: String?

        public init(
            id: String, names: String, text: String, date: Date, unread: Bool,
            lastStatusID: String?, avatarFile: String?
        ) {
            self.id = id
            self.names = names
            self.text = text
            self.date = date
            self.unread = unread
            self.lastStatusID = lastStatusID
            self.avatarFile = avatarFile
        }
    }

    public struct ScheduledPost: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        /// The text, or the content warning where it has one.
        public var text: String
        public var at: Date
        public var mediaCount: Int

        public init(id: String, text: String, at: Date, mediaCount: Int) {
            self.id = id
            self.text = text
            self.at = at
            self.mediaCount = mediaCount
        }
    }

    public struct Poll: Codable, Sendable, Equatable {
        public struct Option: Codable, Sendable, Equatable {
            public var title: String
            public var votes: Int

            public init(title: String, votes: Int) {
                self.title = title
                self.votes = votes
            }
        }

        public var statusID: String
        public var question: String
        public var options: [Option]
        public var voters: Int
        public var expiresAt: Date?
        public var expired: Bool

        public init(
            statusID: String, question: String, options: [Option], voters: Int,
            expiresAt: Date?, expired: Bool
        ) {
            self.statusID = statusID
            self.question = question
            self.options = options
            self.voters = voters
            self.expiresAt = expiresAt
            self.expired = expired
        }

        public var totalVotes: Int { options.reduce(0) { $0 + $1.votes } }

        /// Closed by its date even where the snapshot was written while open.
        public func isClosed(at now: Date) -> Bool {
            expired || (expiresAt.map { $0 <= now } ?? false)
        }
    }

    public struct Photo: Codable, Sendable, Equatable, Identifiable {
        public var statusID: String
        public var author: String
        public var imageFile: String
        public var altText: String?
        public var id: String { imageFile }

        public init(statusID: String, author: String, imageFile: String, altText: String?) {
            self.statusID = statusID
            self.author = author
            self.imageFile = imageFile
            self.altText = altText
        }
    }

    public struct PhotoSet: Codable, Sendable, Equatable {
        public var sourceKey: String
        public var photos: [Photo]

        public init(sourceKey: String, photos: [Photo]) {
            self.sourceKey = sourceKey
            self.photos = photos
        }
    }
}

/// Where a Photo frame widget takes its pictures from.
public enum WidgetPhotoSource: Hashable, Sendable {
    case home
    case hashtag(String)
    case account(String)
    case list(String)

    /// A string that survives the shared defaults and the snapshot file.
    public var key: String {
        switch self {
        case .home: "home"
        case .hashtag(let name): "tag:\(name.lowercased())"
        case .account(let id): "account:\(id)"
        case .list(let id): "list:\(id)"
        }
    }

    public init?(key: String) {
        if key == "home" {
            self = .home
            return
        }
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else { return nil }
        switch parts[0] {
        case "tag": self = .hashtag(parts[1])
        case "account": self = .account(parts[1])
        case "list": self = .list(parts[1])
        default: return nil
        }
    }
}

/// Where the snapshots and their pictures live: the app group's widget
/// folder, one file per account.
public struct WidgetSnapshotStore: Sendable {
    /// Every widget that reads a snapshot, reloaded after one is written.
    public static let widgetKinds = ["DirectMessages", "PhotoFrame"]

    /// What the retired "On this day" widget left in the same folder: its
    /// snapshot and its pictures, which nothing reads any more.
    static let retiredFiles = ["memories.json"]
    static let retiredImagePrefix = "memory-"

    public let directory: URL

    static let filePrefix = "snapshot-"
    static let imagePrefix = "wimg-"

    public init(directory: URL) {
        self.directory = directory
    }

    /// The app group's folder, or nil where the group is off.
    public static var shared: WidgetSnapshotStore? {
        guard AppGroup.isEnabled,
            let group = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppGroup.identifier)
        else { return nil }
        return WidgetSnapshotStore(directory: group.appending(path: "Widgets"))
    }

    public func read(accountID: UUID) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL(accountID)) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Writes the snapshot and the pictures it brought, then removes the
    /// pictures no snapshot names any more.
    public func write(_ snapshot: WidgetSnapshot, images: [String: Data]) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, data) in images where name.hasPrefix(Self.imagePrefix) {
            try data.write(to: directory.appending(path: name), options: .atomic)
        }
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL(snapshot.accountID), options: .atomic)
        pruneImages()
    }

    /// Whether a picture is already on disk, so it is not downloaded again.
    public func hasImage(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appending(path: name).path)
    }

    public func imageURL(_ name: String?) -> URL? {
        name.map { directory.appending(path: $0) }
    }

    /// Removes one account's snapshot and the pictures only it named.
    public func remove(accountID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(accountID))
        pruneImages()
    }

    /// The file name a picture is kept under: a hash of its address and the
    /// size it was shrunk to, so the same picture at two sizes is two files.
    public static func imageName(for url: URL, pixels: Int) -> String {
        let digest = SHA256.hash(data: Data("\(url.absoluteString)#\(pixels)".utf8))
        let hex = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return "\(imagePrefix)\(hex).jpg"
    }

    private func fileURL(_ accountID: UUID) -> URL {
        directory.appending(path: "\(Self.filePrefix)\(accountID.uuidString).json")
    }

    private func pruneImages() {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
        var kept = Set<String>()
        for name in names where name.hasPrefix(Self.filePrefix) {
            guard let data = try? Data(contentsOf: directory.appending(path: name)),
                let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
            else { continue }
            kept.formUnion(snapshot.imageFiles)
        }
        for name in names where name.hasPrefix(Self.imagePrefix) && !kept.contains(name) {
            try? manager.removeItem(at: directory.appending(path: name))
        }
        // An account's posts must not outlive the widget that showed them:
        // this runs on every write and on signing out, so the leftovers go
        // the first time either happens after an update.
        for name in names
        where Self.retiredFiles.contains(name) || name.hasPrefix(Self.retiredImagePrefix) {
            try? manager.removeItem(at: directory.appending(path: name))
        }
    }
}

/// What the configured widgets ask for, so the app knows what to fetch.
///
/// A widget cannot tell the app it exists, and its configuration type lives
/// in the extension. So each provider records here what it is showing — the
/// account, and for Photo frame the source picked — and the app's writer
/// reads it. A want not renewed for three days belongs to a widget that was
/// removed, and is dropped.
public enum WidgetWants {
    public static let lifetime: TimeInterval = 3 * 86_400

    static let key = "aloha.widgetWants"

    struct Stored: Codable, Equatable {
        var accounts: [String: Date] = [:]
        var photoSources: [String: Date] = [:]
    }

    /// Records one widget's wants. Writes only when something is new or a
    /// day old, since every timeline reload calls this.
    public static func record(
        accountID: UUID, photoSources: [WidgetPhotoSource] = [],
        now: Date = Date(), in defaults: UserDefaults = AppGroup.defaults
    ) {
        var stored = read(in: defaults, now: now)
        let before = stored
        func touch(_ dictionary: inout [String: Date], _ key: String) {
            if let seen = dictionary[key], now.timeIntervalSince(seen) < 86_400 { return }
            dictionary[key] = now
        }
        let prefix = accountID.uuidString
        touch(&stored.accounts, prefix)
        for source in photoSources { touch(&stored.photoSources, "\(prefix)/\(source.key)") }
        guard stored != before, let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: key)
    }

    /// The accounts any widget showed lately.
    public static func accounts(
        now: Date = Date(), in defaults: UserDefaults = AppGroup.defaults
    ) -> Set<UUID> {
        Set(read(in: defaults, now: now).accounts.keys.compactMap(UUID.init(uuidString:)))
    }

    /// The sources the Photo frame widgets picked for one account.
    public static func photoSources(
        for accountID: UUID, now: Date = Date(), in defaults: UserDefaults = AppGroup.defaults
    ) -> [WidgetPhotoSource] {
        values(read(in: defaults, now: now).photoSources, accountID).sorted()
            .compactMap(WidgetPhotoSource.init(key:))
    }

    /// Forgets one account, which has signed out.
    public static func removeAll(accountID: UUID, in defaults: UserDefaults = AppGroup.defaults) {
        var stored = read(in: defaults, now: Date())
        let prefix = accountID.uuidString
        stored.accounts.removeValue(forKey: prefix)
        stored.photoSources = stored.photoSources.filter { !$0.key.hasPrefix("\(prefix)/") }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: key)
    }

    private static func values(_ dictionary: [String: Date], _ accountID: UUID) -> [String] {
        let prefix = "\(accountID.uuidString)/"
        return dictionary.keys.filter { $0.hasPrefix(prefix) }.map {
            String($0.dropFirst(prefix.count))
        }
    }

    private static func read(in defaults: UserDefaults, now: Date) -> Stored {
        guard let data = defaults.data(forKey: key),
            var stored = try? JSONDecoder().decode(Stored.self, from: data)
        else { return Stored() }
        let fresh = { (seen: Date) in now.timeIntervalSince(seen) < lifetime }
        stored.accounts = stored.accounts.filter { fresh($0.value) }
        stored.photoSources = stored.photoSources.filter { fresh($0.value) }
        return stored
    }
}
