// SPDX-License-Identifier: MIT

import AlohaNetwork
import CryptoKit
import Foundation

/// Everything the snapshot-backed widgets show for one account, as the app
/// last fetched it.
///
/// Direct messages, requests, reports, scheduled posts, statistics, polls,
/// trends, people and photos are server queries rather than cached
/// timelines, and a widget never downloads (docs/09 §8). The app writes this
/// when it becomes active and on background refresh
/// (`WidgetSnapshotWriter`), and the widgets read nothing else.
///
/// Every section is optional: nil means "not fetched", which a widget says
/// differently from "none".
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public var accountID: UUID
    public var handle: String
    public var writtenAt: Date

    public var messages: Messages?
    public var followRequests: Int?
    public var notificationRequests: Int?
    /// Unresolved reports; nil where the account cannot moderate.
    public var openReports: Int?
    public var scheduled: [ScheduledPost]?
    public var stats: Stats?
    /// The newest poll of the account's own, open or closed within a day.
    public var poll: Poll?
    public var trends: Trends?
    public var people: [Person]
    public var photoSets: [PhotoSet]

    public init(
        accountID: UUID, handle: String, writtenAt: Date = Date(), messages: Messages? = nil,
        followRequests: Int? = nil, notificationRequests: Int? = nil, openReports: Int? = nil,
        scheduled: [ScheduledPost]? = nil, stats: Stats? = nil, poll: Poll? = nil,
        trends: Trends? = nil, people: [Person] = [], photoSets: [PhotoSet] = []
    ) {
        self.accountID = accountID
        self.handle = handle
        self.writtenAt = writtenAt
        self.messages = messages
        self.followRequests = followRequests
        self.notificationRequests = notificationRequests
        self.openReports = openReports
        self.scheduled = scheduled
        self.stats = stats
        self.poll = poll
        self.trends = trends
        self.people = people
        self.photoSets = photoSets
    }

    /// Every picture file the snapshot names.
    public var imageFiles: Set<String> {
        var files = Set<String>()
        for row in messages?.conversations ?? [] {
            if let file = row.avatarFile { files.insert(file) }
        }
        for person in people { if let file = person.avatarFile { files.insert(file) } }
        for set in photoSets { files.formUnion(set.photos.map(\.imageFile)) }
        for link in trends?.links ?? [] { if let file = link.imageFile { files.insert(file) } }
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

    public struct Stats: Codable, Sendable, Equatable {
        /// One follower count per day the app looked, oldest first.
        public struct Sample: Codable, Sendable, Equatable {
            public var day: String
            public var followers: Int

            public init(day: String, followers: Int) {
                self.day = day
                self.followers = followers
            }
        }

        public var followers: Int
        public var history: [Sample]
        /// Favourites, boosts and replies over the last seven days and the
        /// seven before; Aloha Social servers only.
        public var engagementThisWeek: Int?
        public var engagementLastWeek: Int?
        public var postsThisWeek: Int?

        /// How many days of follower history are kept: enough for a week's
        /// change and a month's line.
        public static let historyDays = 35

        public init(
            followers: Int, history: [Sample], engagementThisWeek: Int? = nil,
            engagementLastWeek: Int? = nil, postsThisWeek: Int? = nil
        ) {
            self.followers = followers
            self.history = history
            self.engagementThisWeek = engagementThisWeek
            self.engagementLastWeek = engagementLastWeek
            self.postsThisWeek = postsThisWeek
        }

        /// New followers since the sample a week back, or since the oldest
        /// one where the history is younger than a week.
        public func followerChange(today: String) -> (change: Int, days: Int)? {
            guard let oldest = history.first, oldest.day != today else { return nil }
            let weekAgo = history.last { Self.days(from: $0.day, to: today) ?? 0 >= 7 } ?? oldest
            guard let span = Self.days(from: weekAgo.day, to: today), span > 0 else { return nil }
            return (followers - weekAgo.followers, min(span, 7))
        }

        /// Today's count added to the history, which is trimmed to its length.
        public func recording(followers: Int, day: String) -> Stats {
            var copy = self
            copy.followers = followers
            copy.history.removeAll { $0.day == day }
            copy.history.append(Sample(day: day, followers: followers))
            copy.history.sort { $0.day < $1.day }
            if copy.history.count > Self.historyDays {
                copy.history.removeFirst(copy.history.count - Self.historyDays)
            }
            return copy
        }

        static func days(from start: String, to end: String) -> Int? {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd"
            guard let a = formatter.date(from: start), let b = formatter.date(from: end) else {
                return nil
            }
            return Int((b.timeIntervalSince(a) / 86_400).rounded())
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

    public struct Trends: Codable, Sendable, Equatable {
        public struct Tag: Codable, Sendable, Equatable, Identifiable {
            public var name: String
            /// Posts today, and the people who wrote them.
            public var uses: Int
            public var accounts: Int
            public var id: String { name.lowercased() }

            public init(name: String, uses: Int, accounts: Int) {
                self.name = name
                self.uses = uses
                self.accounts = accounts
            }
        }

        public struct Link: Codable, Sendable, Equatable, Identifiable {
            public var url: URL
            public var title: String
            public var provider: String?
            public var imageFile: String?
            public var id: String { url.absoluteString }

            public init(url: URL, title: String, provider: String?, imageFile: String?) {
                self.url = url
                self.title = title
                self.provider = provider
                self.imageFile = imageFile
            }
        }

        public var tags: [Tag]
        public var links: [Link]

        public init(tags: [Tag], links: [Link]) {
            self.tags = tags
            self.links = links
        }
    }

    public struct Person: Codable, Sendable, Equatable, Identifiable {
        /// The account's id on this account's server.
        public var id: String
        public var name: String
        public var handle: String
        public var avatarFile: String?
        public var latestText: String?
        public var latestDate: Date?
        public var latestStatusID: String?
        /// A story the reader has not seen yet, where the server has stories.
        public var hasNewStory: Bool

        public init(
            id: String, name: String, handle: String, avatarFile: String?, latestText: String?,
            latestDate: Date?, latestStatusID: String?, hasNewStory: Bool
        ) {
            self.id = id
            self.name = name
            self.handle = handle
            self.avatarFile = avatarFile
            self.latestText = latestText
            self.latestDate = latestDate
            self.latestStatusID = latestStatusID
            self.hasNewStory = hasNewStory
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
    public static let widgetKinds = [
        "DirectMessages", "Conversations", "NextScheduledPost", "Requests", "OpenReports",
        "WeeklyStats", "PhotoFrame", "People", "LivePoll", "CreatorDashboard", "ServerTrends",
    ]

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
    }
}

/// What the configured widgets ask for, so the app knows what to fetch.
///
/// A widget cannot tell the app it exists, and its configuration type lives
/// in the extension. So each provider records here what it is showing — the
/// account, and for People and Photo frame the people and sources picked —
/// and the app's writer reads it. A want not renewed for three days belongs
/// to a widget that was removed, and is dropped.
public enum WidgetWants {
    public static let lifetime: TimeInterval = 3 * 86_400

    static let key = "aloha.widgetWants"

    struct Stored: Codable, Equatable {
        var accounts: [String: Date] = [:]
        var people: [String: Date] = [:]
        var photoSources: [String: Date] = [:]
    }

    /// Records one widget's wants. Writes only when something is new or a
    /// day old, since every timeline reload calls this.
    public static func record(
        accountID: UUID, people: [String] = [], photoSources: [WidgetPhotoSource] = [],
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
        for person in people { touch(&stored.people, "\(prefix)/\(person)") }
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

    /// The people the People widgets picked for one account, sorted.
    public static func people(
        for accountID: UUID, now: Date = Date(), in defaults: UserDefaults = AppGroup.defaults
    ) -> [String] {
        values(read(in: defaults, now: now).people, accountID).sorted()
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
        stored.people = stored.people.filter { !$0.key.hasPrefix("\(prefix)/") }
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
        stored.people = stored.people.filter { fresh($0.value) }
        stored.photoSources = stored.photoSources.filter { fresh($0.value) }
        return stored
    }
}
