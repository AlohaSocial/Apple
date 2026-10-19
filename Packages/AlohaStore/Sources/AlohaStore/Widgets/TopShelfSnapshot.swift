// SPDX-License-Identifier: MIT

import AlohaHTML
import AlohaModels
import AlohaNetwork
import Foundation

/// What the Apple TV's Top Shelf shows for Aloha Social: the videos the TV app
/// last loaded, written by the app and read by the Top Shelf extension.
///
/// The system asks the extension for content whenever the app's icon is in the
/// top row, which is far more often than the app runs. Reading a file the app
/// already wrote makes that instant and works offline; the extension only goes
/// to the network when the snapshot is missing or stale.
public struct TopShelfSnapshot: Codable, Sendable, Equatable {
    public enum SectionKind: String, Codable, Sendable, CaseIterable {
        /// `GET /api/v1/social/video/continue_watching` — where a video was
        /// left off, with its position.
        case continueWatching
        /// The newest videos from the home timeline.
        case following
    }

    public struct Item: Codable, Sendable, Equatable, Identifiable {
        /// The post's id on the account's server.
        public var id: String
        public var title: String
        /// The video's still. Top Shelf downloads it itself; a post whose
        /// media is marked sensitive never gets here (see `make`).
        public var imageURL: URL?
        /// 0…1, for videos that were started; nil otherwise.
        public var progress: Double?
        /// Seconds into the video where playback resumes.
        public var position: Double?

        public init(
            id: String, title: String, imageURL: URL?, progress: Double? = nil,
            position: Double? = nil
        ) {
            self.id = id
            self.title = title
            self.imageURL = imageURL
            self.progress = progress
            self.position = position
        }
    }

    public struct Section: Codable, Sendable, Equatable {
        public var kind: SectionKind
        public var items: [Item]

        public init(kind: SectionKind, items: [Item]) {
            self.kind = kind
            self.items = items
        }
    }

    public var accountID: UUID
    public var createdAt: Date
    public var sections: [Section]

    public init(accountID: UUID, createdAt: Date, sections: [Section]) {
        self.accountID = accountID
        self.createdAt = createdAt
        self.sections = sections
    }

    /// Whether `other` shows the same thing: the time it was written does
    /// not count, so the app only tells the system about real changes.
    public func hasSameContent(as other: TopShelfSnapshot?) -> Bool {
        guard let other else { return false }
        return accountID == other.accountID && sections == other.sections
    }

    /// How many items a section offers. Top Shelf shows one row per section
    /// and scrolls it; more than this is a list nobody reaches with a remote.
    public static let itemsPerSection = 10

    /// Builds the snapshot from what the TV app loads anyway.
    ///
    /// A post whose media is marked sensitive, or that carries a content
    /// warning, is left out: Top Shelf draws the still full size on the home
    /// screen, with no blur and no tap-to-reveal, in a room other people are
    /// in.
    public static func make(
        accountID: UUID, continueWatching: [ContinueWatchingItem], following: [Status],
        now: Date = Date()
    ) -> TopShelfSnapshot {
        let resumed = continueWatching.compactMap { entry -> Item? in
            guard let status = entry.status, var item = item(for: status) else { return nil }
            if entry.duration > 0 {
                item.progress = min(max(entry.position / entry.duration, 0), 1)
            }
            item.position = entry.position > 0 ? entry.position : nil
            return item
        }
        let resumedIDs = Set(resumed.map(\.id))
        let newest = following.compactMap(item(for:)).filter { !resumedIDs.contains($0.id) }

        let sections = [
            Section(kind: .continueWatching, items: Array(resumed.prefix(itemsPerSection))),
            Section(kind: .following, items: Array(newest.prefix(itemsPerSection))),
        ]
        return TopShelfSnapshot(
            accountID: accountID, createdAt: now, sections: sections.filter { !$0.items.isEmpty })
    }

    static func item(for status: Status) -> Item? {
        let post = status.displayed
        guard !post.sensitive, post.spoilerText.isEmpty,
            let video = post.mediaAttachments.first(where: { $0.type == .video || $0.type == .gifv }
            )
        else { return nil }
        return Item(id: post.id, title: title(for: post), imageURL: video.previewURL)
    }

    /// The first line of the post, or who posted it when the post is only a
    /// video: Top Shelf shows a single line under the still.
    static func title(for post: Status) -> String {
        let text = StatusHTMLParser().plainText(post.content)
        let firstLine =
            text.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !firstLine.isEmpty else { return post.account.bestDisplayName }
        guard firstLine.count > 80 else { return firstLine }
        return String(firstLine.prefix(79)) + "…"
    }
}

/// Where the Top Shelf snapshot lives: a file in the app group.
public struct TopShelfSnapshotStore: Sendable {
    public let directory: URL

    static let fileName = "topshelf.json"

    public init(directory: URL) {
        self.directory = directory
    }

    /// The app group's folder, or nil where the group is off — then the
    /// extension could not read it, and nothing is written.
    public static var shared: TopShelfSnapshotStore? {
        guard AppGroup.isEnabled,
            let group = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppGroup.identifier)
        else { return nil }
        return TopShelfSnapshotStore(directory: group.appending(path: "TopShelf"))
    }

    public func read() -> TopShelfSnapshot? {
        guard let data = try? Data(contentsOf: directory.appending(path: Self.fileName)) else {
            return nil
        }
        return try? JSONDecoder().decode(TopShelfSnapshot.self, from: data)
    }

    /// Writes the snapshot, and says whether its content changed, which is
    /// when the system should be asked to reload the shelf.
    @discardableResult
    public func write(_ snapshot: TopShelfSnapshot) throws -> Bool {
        let changed = !snapshot.hasSameContent(as: read())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: directory.appending(path: Self.fileName), options: .atomic)
        return changed
    }

    public func remove() {
        try? FileManager.default.removeItem(at: directory.appending(path: Self.fileName))
    }
}

/// The links a Top Shelf item opens the TV app with:
/// `alohasocial://tv/play/<id>` and `alohasocial://tv/show/<id>`, plus
/// `?t=<seconds>` where playback resumes.
public enum TopShelfLink: Equatable, Sendable {
    case play(statusID: String, position: Double?)
    case show(statusID: String, position: Double?)

    public static let scheme = "alohasocial"

    public var statusID: String {
        switch self {
        case .play(let id, _), .show(let id, _): id
        }
    }

    public var position: Double? {
        switch self {
        case .play(_, let position), .show(_, let position): position
        }
    }

    public var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "tv"
        let verb =
            switch self {
            case .play: "play"
            case .show: "show"
            }
        // The id is the server's and may hold anything; as one path segment
        // it has to be escaped like one.
        let id =
            statusID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?
            .replacingOccurrences(of: "/", with: "%2F") ?? statusID
        components.percentEncodedPath = "/\(verb)/\(id)"
        if let position, position > 0 {
            components.queryItems = [URLQueryItem(name: "t", value: String(Int(position)))]
        }
        return components.url
    }

    public init?(url: URL) {
        guard url.scheme == Self.scheme, url.host() == "tv" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, !parts[1].isEmpty else { return nil }
        let position =
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "t" }?.value.flatMap(Double.init)
        switch parts[0] {
        case "play": self = .play(statusID: parts[1], position: position)
        case "show": self = .show(statusID: parts[1], position: position)
        default: return nil
        }
    }
}
