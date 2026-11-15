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
/// Direct messages, requests, reports, scheduled posts, statistics, polls,
/// trends, people and photos are server queries, and a widget never
/// downloads (docs/09 §8). So the app asks once in a while — when it becomes
/// active, and on background refresh — and the widgets read only what is
/// written here (`WidgetSnapshotStore`).
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
    nonisolated static let trendLimit = 5
    nonisolated static let photosPerSource = 6
    nonisolated static let avatarPixels = 96
    nonisolated static let photoPixels = 720
    nonisolated static let linkPixels = 240
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
        let people = WidgetWants.people(for: session.id)
        let sources = WidgetWants.photoSources(for: session.id)
        if !force, let previous,
            !needsRefresh(previous, people: people, sources: sources, now: now)
        {
            return
        }

        let fetched = await fetch(
            client: session.client, capabilities: session.capabilities,
            serverAccountID: session.snapshot.serverAccountID, people: people, sources: sources)
        guard !Task.isCancelled else { return }

        var snapshot = merge(
            fetched, into: previous, accountID: session.id,
            handle: session.snapshot.qualifiedHandle,
            serverAccountID: session.snapshot.serverAccountID,
            aloha: session.capabilities.isNextcloudSocial, now: now)
        let images = await download(
            pictures(
                for: fetched, serverAccountID: session.snapshot.serverAccountID, in: &snapshot
            )
            .filter { !store.hasImage($0.name) })

        do {
            try store.write(snapshot, images: images)
            if publishesBadge, let messages = snapshot.messages {
                AppGroup.defaults.set(messages.unread, forKey: AppGroup.unreadConversationsKey)
            }
            for kind in WidgetSnapshotStore.widgetKinds { WidgetReloader.reload(kind: kind) }
        } catch {
            logger.error(
                "widget snapshot not written: \(String(describing: error), privacy: .public)")
        }
    }

    /// Stale by age, or missing a person or photo source a widget picked
    /// since it was written.
    nonisolated static func needsRefresh(
        _ previous: WidgetSnapshot, people: [String], sources: [WidgetPhotoSource], now: Date
    ) -> Bool {
        if now.timeIntervalSince(previous.writtenAt) >= minimumInterval { return true }
        let known = Set(previous.people.map(\.id))
        if people.contains(where: { !known.contains($0) }) { return true }
        return sources.contains { previous.photoSet(for: $0) == nil }
    }

    // MARK: - Fetching

    /// What the server answered, section by section; nil where it did not.
    struct Fetched: Sendable {
        var conversations: [Conversation]?
        var followRequests: Int?
        var policy: NotificationPolicy?
        var reports: ReportsAnswer = .notAsked
        var scheduled: [ScheduledStatus]?
        var me: Account?
        var weekStatistics: AccountStatistics?
        var fortnightStatistics: AccountStatistics?
        var ownPosts: [Status]?
        var trendingTags: [Tag]?
        var trendingLinks: [Card]?
        var people: [String: PersonAnswer] = [:]
        var unseenStoryAuthors: Set<String>?
        var photos: [String: [Status]] = [:]
        /// What the widgets asked for, so a failed request keeps its old row.
        var wantedPeople: [String] = []
        var wantedSources: [String] = []
    }

    enum ReportsAnswer: Sendable {
        /// Not an Aloha Social server, or a request that failed for a
        /// reason that says nothing about the account.
        case notAsked, failed
        /// The server refused: this account does not moderate.
        case refused
        case count(Int)
    }

    struct PersonAnswer: Sendable {
        var account: Account
        var latest: Status?
    }

    private static func fetch(
        client: APIClient, capabilities: ServerCapabilities, serverAccountID: String,
        people: [String], sources: [WidgetPhotoSource]
    ) async -> Fetched {
        let aloha = capabilities.isNextcloudSocial
        async let conversations = attempt {
            try await client.decode(
                LossyArray<Conversation>.self,
                from: Endpoint.timelines.conversations(limit: 20)
            ).elements
        }
        async let followRequests = attempt {
            try await client.decode(
                LossyArray<Account>.self, from: Endpoint.accounts.followRequests
            ).elements.count
        }
        async let policy = attempt {
            try await client.decode(
                NotificationPolicy.self, from: Endpoint.notifications.policy(v2: true))
        }
        async let reports = aloha ? reportCount(client) : ReportsAnswer.notAsked
        async let scheduled = attempt {
            try await client.decode(
                LossyArray<ScheduledStatus>.self, from: Endpoint.composing.scheduled
            ).elements
        }
        async let me = attempt {
            try await client.decode(Account.self, from: Endpoint.session.verifyCredentials)
        }
        async let week = aloha ? statistics(client, days: 7) : nil
        async let fortnight = aloha ? statistics(client, days: 14) : nil
        async let ownPosts = attempt {
            try await client.decode(
                LossyArray<Status>.self,
                from: Endpoint.timelines.timeline(
                    .account(id: serverAccountID, includeReplies: false, onlyMedia: false),
                    limit: 20)
            ).elements
        }
        async let tags = attempt {
            try await client.decode(
                LossyArray<Tag>.self, from: Endpoint.search.trendingTags(limit: trendLimit)
            ).elements
        }
        async let links = attempt {
            try await client.decode(
                LossyArray<Card>.self, from: Endpoint.search.trendingLinks(limit: trendLimit)
            ).elements
        }
        async let personAnswers = fetchPeople(client, ids: people)
        async let stories = capabilities.stories ? unseenStoryAuthors(client) : nil
        async let photos = fetchPhotos(client, sources: sources)

        return await Fetched(
            conversations: conversations, followRequests: followRequests, policy: policy,
            reports: reports, scheduled: scheduled, me: me, weekStatistics: week,
            fortnightStatistics: fortnight, ownPosts: ownPosts, trendingTags: tags,
            trendingLinks: links, people: personAnswers, unseenStoryAuthors: stories,
            photos: photos, wantedPeople: people, wantedSources: sources.map(\.key))
    }

    nonisolated private static func attempt<T: Sendable>(
        _ work: @Sendable () async throws -> T
    ) async -> T? {
        try? await work()
    }

    nonisolated private static func reportCount(_ client: APIClient) async -> ReportsAnswer {
        do {
            let reports = try await client.decode(
                LossyArray<AdminReport>.self,
                from: Endpoint.moderation.reports(resolved: false, limit: 40))
            return .count(reports.elements.count)
        } catch APIError.forbidden, APIError.unauthorised, APIError.notFound {
            return .refused
        } catch {
            return .failed
        }
    }

    nonisolated private static func statistics(
        _ client: APIClient, days: Int
    ) async -> AccountStatistics? {
        try? await client.decode(
            AccountStatistics.self, from: Endpoint.statistics.overview(days: days))
    }

    nonisolated private static func fetchPeople(
        _ client: APIClient, ids: [String]
    ) async -> [String: PersonAnswer] {
        await withTaskGroup(of: (String, PersonAnswer?).self) { group in
            for id in ids {
                group.addTask {
                    let latest = try? await client.decode(
                        LossyArray<Status>.self,
                        from: Endpoint.timelines.timeline(
                            .account(id: id, includeReplies: false, onlyMedia: false), limit: 1)
                    ).elements.first
                    if let latest {
                        return (id, PersonAnswer(account: latest.account, latest: latest))
                    }
                    // Nobody has posted yet: the account alone, for a name.
                    guard
                        let account = try? await client.decode(
                            Account.self, from: Endpoint.accounts.account(id))
                    else { return (id, nil) }
                    return (id, PersonAnswer(account: account, latest: nil))
                }
            }
            var answers: [String: PersonAnswer] = [:]
            for await (id, answer) in group { answers[id] = answer }
            return answers
        }
    }

    nonisolated private static func unseenStoryAuthors(_ client: APIClient) async -> Set<String>? {
        guard
            let carousel = try? await client.decode(
                StoryCarousel.self, from: Endpoint.stories.carousel)
        else { return nil }
        return Set(carousel.others.filter { !$0.seen }.map(\.account.id))
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
        serverAccountID: String, aloha: Bool, now: Date
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

        snapshot.followRequests = fetched.followRequests ?? previous?.followRequests
        snapshot.notificationRequests =
            fetched.policy?.summary?.pendingRequestsCount ?? previous?.notificationRequests

        switch fetched.reports {
        case .count(let count): snapshot.openReports = count
        case .refused, .notAsked: snapshot.openReports = nil
        case .failed: snapshot.openReports = aloha ? previous?.openReports : nil
        }

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

        snapshot.stats = stats(fetched, previous: previous?.stats, now: now)
        snapshot.poll =
            poll(in: fetched.ownPosts, now: now, text: text(of:))
            ?? previousPoll(previous, fetched: fetched, now: now)

        if fetched.trendingTags != nil || fetched.trendingLinks != nil {
            snapshot.trends = WidgetSnapshot.Trends(
                tags: fetched.trendingTags.map { tags in
                    tags.prefix(trendLimit).map { tag in
                        WidgetSnapshot.Trends.Tag(
                            name: tag.name, uses: tag.history.first?.usesCount ?? 0,
                            accounts: tag.history.first?.accountsCount ?? 0)
                    }
                } ?? previous?.trends?.tags ?? [],
                links: fetched.trendingLinks.map { cards in
                    cards.prefix(trendLimit).compactMap { card in
                        guard let url = card.url, !card.title.isEmpty else { return nil }
                        return WidgetSnapshot.Trends.Link(
                            url: url, title: card.title, provider: card.providerName,
                            imageFile: nil)
                    }
                } ?? previous?.trends?.links ?? [])
        } else {
            snapshot.trends = previous?.trends
        }

        // A person or source whose request failed keeps its last row.
        let previousPeople = Dictionary(
            (previous?.people ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        snapshot.people = fetched.wantedPeople.compactMap { id in
            guard let answer = fetched.people[id] else { return previousPeople[id] }
            return WidgetSnapshot.Person(
                id: id, name: answer.account.bestDisplayName, handle: answer.account.acct,
                avatarFile: nil, latestText: answer.latest.map(text(of:)),
                latestDate: answer.latest?.createdAt, latestStatusID: answer.latest?.id,
                hasNewStory: fetched.unseenStoryAuthors?.contains(id)
                    ?? previousPeople[id]?.hasNewStory ?? false)
        }

        let previousSets = Dictionary(
            (previous?.photoSets ?? []).map { ($0.sourceKey, $0) },
            uniquingKeysWith: { first, _ in first })
        snapshot.photoSets = fetched.wantedSources.compactMap { key in
            guard fetched.photos[key] != nil else { return previousSets[key] }
            return WidgetSnapshot.PhotoSet(sourceKey: key, photos: [])
        }
        return snapshot
    }

    nonisolated private static func stats(
        _ fetched: Fetched, previous: WidgetSnapshot.Stats?, now: Date
    ) -> WidgetSnapshot.Stats? {
        guard let followers = fetched.me?.followersCount ?? previous?.followers else { return nil }
        var stats = (previous ?? WidgetSnapshot.Stats(followers: followers, history: []))
            .recording(followers: followers, day: MemoriesSnapshot.dayKey(for: now))
        if let week = fetched.weekStatistics {
            let thisWeek = engagement(week)
            stats.engagementThisWeek = thisWeek
            stats.postsThisWeek = week.posts["count"].map { Int($0) }
            if let fortnight = fetched.fortnightStatistics {
                stats.engagementLastWeek = max(0, engagement(fortnight) - thisWeek)
            }
        }
        return stats
    }

    /// Favourites, boosts and replies, under the names either server uses.
    nonisolated static func engagement(_ statistics: AccountStatistics) -> Int {
        let e = statistics.engagement
        let total =
            (e["favourites"] ?? e["likes"] ?? 0) + (e["boosts"] ?? e["reblogs"] ?? 0)
            + (e["replies"] ?? 0)
        return Int(total)
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

        for index in snapshot.people.indices {
            guard let answer = fetched.people[snapshot.people[index].id] else { continue }
            snapshot.people[index].avatarFile = picture(
                answer.account.preferredAvatarURL, pixels: avatarPixels)
        }

        if let cards = fetched.trendingLinks, var trends = snapshot.trends {
            for index in trends.links.indices {
                let card = cards.first { $0.url == trends.links[index].url }
                trends.links[index].imageFile = picture(card?.image, pixels: linkPixels)
            }
            snapshot.trends = trends
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
