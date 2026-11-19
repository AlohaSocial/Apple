// SPDX-License-Identifier: MIT

import AlohaHTML
import AlohaModels
import AlohaNetwork
import AlohaStore
import CoreGraphics
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// Writes the snapshot-backed widgets' data into the app group.
///
/// Direct messages and photos (the widgets), and scheduled posts and the
/// account's own poll (the countdown Live Activities) are server queries, and
/// a widget never downloads (docs/09 §8). So the app asks once in a while —
/// when it becomes active, and on background refresh — and the widgets read
/// only what is written here (`WidgetSnapshotStore`).
///
/// Each section is fetched on its own and keeps its last answer when its
/// request fails: one server hiccup must not empty every widget.
@MainActor
public enum WidgetSnapshotWriter {
    /// How often a snapshot is fetched again at most, unless a widget asks
    /// for something it does not have yet.
    nonisolated static let minimumInterval: TimeInterval = 600
    nonisolated static let conversationLimit = 6
    nonisolated static let scheduledLimit = 3
    nonisolated static let photosPerSource = 6
    nonisolated static let avatarPixels = 96
    nonisolated static let photoPixels = 720
    /// A closed poll stays on the widget for a day, with its final result.
    nonisolated static let closedPollGrace: TimeInterval = 86_400

    private static let logger = Logger(subsystem: "social.aloha.app", category: "widgets")

    /// Refreshes the active account and every account a widget showed lately,
    /// within a time budget: a background refresh has only so long, and a
    /// widget is worth less than the sync that ran before it.
    public static func refreshAll(_ environment: AppEnvironment, budget: Duration) async {
        let wanted = WidgetWants.accounts()
        let activeID = environment.activeSession?.id
        let sessions = environment.sessions.filter { $0.id == activeID || wanted.contains($0.id) }
        guard !sessions.isEmpty else { return }
        let work = Task { @MainActor in
            for session in sessions {
                await refresh(session, publishesBadge: session.id == activeID)
            }
        }
        let timer = Task {
            try? await Task.sleep(for: budget)
            work.cancel()
        }
        await work.value
        timer.cancel()
    }

    /// Writes one account's snapshot unless a fresh one already answers what
    /// the widgets ask for.
    public static func refresh(
        _ session: AccountSession, publishesBadge: Bool = false, force: Bool = false,
        store: WidgetSnapshotStore? = .shared, now: Date = Date()
    ) async {
        guard let store, !session.needsReauthentication else { return }
        let previous = store.read(accountID: session.id)
        let sources = WidgetWants.photoSources(for: session.id)
        if !force, let previous, !needsRefresh(previous, sources: sources, now: now) {
            return
        }

        let fetched = await fetch(
            client: session.client, serverAccountID: session.snapshot.serverAccountID,
            sources: sources)
        guard !Task.isCancelled else { return }

        var snapshot = merge(
            fetched, into: previous, accountID: session.id,
            handle: session.snapshot.qualifiedHandle,
            serverAccountID: session.snapshot.serverAccountID, now: now)
        let images = await download(
            pictures(
                for: fetched, serverAccountID: session.snapshot.serverAccountID, in: &snapshot
            )
            .filter { !store.hasImage($0.name) })

        do {
            try store.write(snapshot, images: images)
            if publishesBadge, let messages = snapshot.messages {
                AppGroup.defaults.set(messages.unread, forKey: AppGroup.unreadConversationsKey)
                #if os(iOS)
                    WatchBridge.shared.sendConversationsChanged()
                #endif
            }
            for kind in WidgetSnapshotStore.widgetKinds { WidgetReloader.reload(kind: kind) }
        } catch {
            logger.error(
                "widget snapshot not written: \(String(describing: error), privacy: .public)")
        }
    }

    /// Stale by age, or missing a photo source a widget picked since it was
    /// written.
    nonisolated static func needsRefresh(
        _ previous: WidgetSnapshot, sources: [WidgetPhotoSource], now: Date
    ) -> Bool {
        if now.timeIntervalSince(previous.writtenAt) >= minimumInterval { return true }
        return sources.contains { previous.photoSet(for: $0) == nil }
    }

    // MARK: - Fetching

    /// What the server answered, section by section; nil where it did not.
    struct Fetched: Sendable {
        var conversations: [Conversation]?
        var scheduled: [ScheduledStatus]?
        var ownPosts: [Status]?
        var photos: [String: [Status]] = [:]
        /// What the widgets asked for, so a failed request keeps its old set.
        var wantedSources: [String] = []
    }

    private static func fetch(
        client: APIClient, serverAccountID: String, sources: [WidgetPhotoSource]
    ) async -> Fetched {
        async let conversations = attempt {
            try await client.decode(
                LossyArray<Conversation>.self,
                from: Endpoint.timelines.conversations(limit: 20)
            ).elements
        }
        async let scheduled = attempt {
            try await client.decode(
                LossyArray<ScheduledStatus>.self, from: Endpoint.composing.scheduled
            ).elements
        }
        async let ownPosts = attempt {
            try await client.decode(
                LossyArray<Status>.self,
                from: Endpoint.timelines.timeline(
                    .account(id: serverAccountID, includeReplies: false, onlyMedia: false),
                    limit: 20)
            ).elements
        }
        async let photos = fetchPhotos(client, sources: sources)

        return await Fetched(
            conversations: conversations, scheduled: scheduled, ownPosts: ownPosts,
            photos: photos, wantedSources: sources.map(\.key))
    }

    nonisolated private static func attempt<T: Sendable>(
        _ work: @Sendable () async throws -> T
    ) async -> T? {
        try? await work()
    }

    nonisolated private static func fetchPhotos(
        _ client: APIClient, sources: [WidgetPhotoSource]
    ) async -> [String: [Status]] {
        await withTaskGroup(of: (String, [Status]?).self) { group in
            for source in sources {
                group.addTask {
                    let timeline: TimelineSource =
                        switch source {
                        case .home: .home
                        case .hashtag(let name): .hashtag(name: name)
                        case .account(let id):
                            .account(id: id, includeReplies: false, onlyMedia: true)
                        case .list(let id): .list(id: id)
                        }
                    // Asked with only_media where the server reads it; the
                    // rows are filtered for pictures below either way.
                    let statuses = try? await client.decode(
                        LossyArray<Status>.self,
                        from: Endpoint.timelines.timeline(
                            timeline, filters: TimelineFilters(onlyMedia: true), limit: 40)
                    ).elements
                    return (source.key, statuses)
                }
            }
            var answers: [String: [Status]] = [:]
            for await (key, statuses) in group { answers[key] = statuses }
            return answers
        }
    }

    // MARK: - Merging

    /// The new snapshot: every section the server answered, and the previous
    /// snapshot's for those it did not. Picture files are filled in later.
    nonisolated static func merge(
        _ fetched: Fetched, into previous: WidgetSnapshot?, accountID: UUID, handle: String,
        serverAccountID: String, now: Date
    ) -> WidgetSnapshot {
        let parser = StatusHTMLParser()
        func text(of status: Status) -> String {
            let shown = status.displayed
            return shown.spoilerText.isEmpty ? parser.plainText(shown.content) : shown.spoilerText
        }

        var snapshot = WidgetSnapshot(accountID: accountID, handle: handle, writtenAt: now)

        snapshot.messages =
            fetched.conversations.map { conversations in
                WidgetSnapshot.Messages(
                    unread: conversations.filter(\.unread).count,
                    conversations: conversations.prefix(conversationLimit).map { conversation in
                        let others = conversation.accounts.filter { $0.id != serverAccountID }
                        return WidgetSnapshot.ConversationRow(
                            id: conversation.id,
                            names: others.isEmpty
                                ? handle : others.map(\.bestDisplayName).joined(separator: ", "),
                            text: conversation.lastStatus.map(text(of:)) ?? "",
                            date: conversation.lastStatus?.createdAt ?? now,
                            unread: conversation.unread,
                            lastStatusID: conversation.lastStatus?.id,
                            avatarFile: nil)
                    })
            } ?? previous?.messages

        snapshot.scheduled =
            fetched.scheduled.map { scheduled in
                scheduled.filter { $0.scheduledAt > now }
                    .sorted { $0.scheduledAt < $1.scheduledAt }
                    .prefix(scheduledLimit)
                    .map { post in
                        let spoiler = post.params.spoilerText ?? ""
                        return WidgetSnapshot.ScheduledPost(
                            id: post.id,
                            text: spoiler.isEmpty ? (post.params.text ?? "") : spoiler,
                            at: post.scheduledAt,
                            mediaCount: post.mediaAttachments.count)
                    }
            } ?? previous?.scheduled.map { $0.filter { $0.at > now } }

        snapshot.poll =
            poll(in: fetched.ownPosts, now: now, text: text(of:))
            ?? previousPoll(previous, fetched: fetched, now: now)

        let previousSets = Dictionary(
            (previous?.photoSets ?? []).map { ($0.sourceKey, $0) },
            uniquingKeysWith: { first, _ in first })
        snapshot.photoSets = fetched.wantedSources.compactMap { key in
            guard fetched.photos[key] != nil else { return previousSets[key] }
            return WidgetSnapshot.PhotoSet(sourceKey: key, photos: [])
        }
        return snapshot
    }

    /// The newest poll of the account's own, while open or for a day after.
    nonisolated static func poll(
        in posts: [Status]?, now: Date, text: (Status) -> String
    ) -> WidgetSnapshot.Poll? {
        guard let posts else { return nil }
        for status in posts where status.reblog == nil {
            guard let poll = status.poll else { continue }
            let closedAt = poll.expiresAt ?? (poll.expired ? status.createdAt : .distantFuture)
            if poll.expired || closedAt <= now {
                guard now.timeIntervalSince(closedAt) < closedPollGrace else { return nil }
            }
            return WidgetSnapshot.Poll(
                statusID: status.id, question: text(status),
                options: poll.options.map {
                    WidgetSnapshot.Poll.Option(title: $0.title, votes: $0.votesCount ?? 0)
                },
                voters: poll.votersCount ?? poll.votesCount, expiresAt: poll.expiresAt,
                expired: poll.expired)
        }
        return nil
    }

    /// A poll answer that failed keeps the last one, unless it closed more
    /// than a day ago.
    nonisolated private static func previousPoll(
        _ previous: WidgetSnapshot?, fetched: Fetched, now: Date
    ) -> WidgetSnapshot.Poll? {
        guard fetched.ownPosts == nil, let poll = previous?.poll else { return nil }
        if let closes = poll.expiresAt, now.timeIntervalSince(closes) >= closedPollGrace {
            return nil
        }
        return poll
    }

    // MARK: - Pictures

    struct Picture: Sendable {
        var name: String
        var url: URL
        var pixels: Int
    }

    /// Names the pictures in the snapshot and returns what each needs; the
    /// ones already on disk are skipped by the caller.
    nonisolated static func pictures(
        for fetched: Fetched, serverAccountID: String, in snapshot: inout WidgetSnapshot
    ) -> [Picture] {
        var wanted: [Picture] = []
        func picture(_ url: URL?, pixels: Int) -> String? {
            guard let url else { return nil }
            let name = WidgetSnapshotStore.imageName(for: url, pixels: pixels)
            if !wanted.contains(where: { $0.name == name }) {
                wanted.append(Picture(name: name, url: url, pixels: pixels))
            }
            return name
        }

        if let conversations = fetched.conversations, var messages = snapshot.messages {
            let byID = Dictionary(
                conversations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for index in messages.conversations.indices {
                let conversation = byID[messages.conversations[index].id]
                let other =
                    conversation?.accounts.first { $0.id != serverAccountID }
                    ?? conversation?.accounts.first
                messages.conversations[index].avatarFile = picture(
                    other?.preferredAvatarURL, pixels: avatarPixels)
            }
            snapshot.messages = messages
        }

        for index in snapshot.photoSets.indices {
            guard let statuses = fetched.photos[snapshot.photoSets[index].sourceKey] else {
                continue
            }
            var photos: [WidgetSnapshot.Photo] = []
            var seen = Set<String>()
            for status in statuses.map(\.displayed) where seen.insert(status.id).inserted {
                guard let image = Self.picture(of: status),
                    let file = picture(image.previewURL ?? image.url, pixels: photoPixels)
                else { continue }
                photos.append(
                    WidgetSnapshot.Photo(
                        statusID: status.id, author: status.account.bestDisplayName,
                        imageFile: file, altText: image.description))
                if photos.count == photosPerSource { break }
            }
            snapshot.photoSets[index].photos = photos
        }
        return wanted
    }

    /// The first picture of a post, unless it is behind a warning: a Home
    /// Screen is a more public place than the app.
    nonisolated static func picture(of status: Status) -> MediaAttachment? {
        guard !status.sensitive, status.spoilerText.isEmpty else { return nil }
        return status.mediaAttachments.first { $0.type == .image }
    }

    /// Downloads and shrinks the pictures, a few at a time, off the main actor.
    @concurrent
    nonisolated private static func download(_ pictures: [Picture]) async -> [String: Data] {
        await withTaskGroup(of: (String, Data?).self) { group in
            var pending = pictures[...]
            var results: [String: Data] = [:]
            func addNext() {
                guard let next = pending.popFirst() else { return }
                group.addTask { (next.name, await fetchPicture(next)) }
            }
            for _ in 0..<4 { addNext() }
            for await (name, data) in group {
                if let data { results[name] = data }
                addNext()
            }
            return results
        }
    }

    nonisolated private static func fetchPicture(_ picture: Picture) async -> Data? {
        var request = URLRequest(url: picture.url)
        request.timeoutInterval = 15
        guard let fetched = try? await URLSession.shared.data(for: request),
            let http = fetched.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        return jpeg(from: fetched.0, pixels: picture.pixels)
    }

    /// Shrunk once here, so the widget decodes a few kilobytes.
    nonisolated static func jpeg(from data: Data, pixels: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixels,
                ] as CFDictionary)
        else { return nil }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
