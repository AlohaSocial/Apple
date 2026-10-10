// SPDX-License-Identifier: MIT

import AlohaIntelligence
import AlohaModels
import AlohaNetwork
import AlohaStore
import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
public final class ComposerModel {
    public var text = "" {
        didSet {
            // The key is regenerated only when content changes, which is what
            // makes retry-on-timeout safe without blocking a genuine re-edit.
            if text != oldValue { idempotencyKey = UUID().uuidString }
            updateCompletions()
        }
    }
    public var spoilerText = ""
    public var visibility: Visibility = .public
    public var showsContentWarningField = false
    public var pollOptions: [String] = []
    public var pollMultiple = false
    public var scheduledAt: Date?
    public var isShowingAltTextFor: MediaAttachment?
    public var completions: [String] = []
    public var isShowingMediaPicker = false
    public var isShowingAltTextWarning = false
    public var editingAltTextFor: String?
    public private(set) var isPosting = false
    public private(set) var errorMessage: String?

    // MARK: Nextcloud Social extras

    /// The post being quoted, when the composer opened for a quote.
    public let quoting: Status?
    /// Who may quote the new post: `public`, `followers` or `nobody`.
    public var quotePolicy: QuotePolicy = .public
    /// The place this post is tagged with, if any.
    public var place: ComposerPlace?
    /// The language this post is written in. Defaults to the account's.
    public var language: String?
    /// Team accounts the viewer may post as, and the one chosen.
    public private(set) var teams: [TeamAccount] = []
    public var postAs: TeamAccount?
    /// PeerTube-style metadata, shown when a video is attached.
    public var videoTitle = ""
    public var videoCategory = ""
    public var videoLicence = ""
    /// Set after posting when a moderator must look at the post first.
    public private(set) var wasHeldForReview = false
    /// What `/dice`, `/flip` and `/pick` landed on, filled in as the post goes
    /// out. Shown once and then forgotten: the result is part of the post, not
    /// of the composer.
    public private(set) var playedGames: [ComposerCommands.Result] = []

    /// Which games this post has to play, for the hint under the box.
    public var pendingGames: [ComposerCommands.Result.Kind] {
        ComposerCommands.commands(in: text)
    }

    /// When set, a short post goes out drawn big on this background — the
    /// words as a picture, and the same words as the post and as the picture's
    /// description, so nothing is lost on a server that only sees the text.
    public var cardBackgroundID: String?
    /// Attachments that came from the server's GIF library rather than an
    /// upload; they never went through the uploader.
    public private(set) var libraryAttachments: [MediaAttachment] = []
    /// Focal points set here, by attachment id, so the strip can show a mark.
    public private(set) var focalPoints: [String: CGPoint] = [:]

    // MARK: - Describing every image at once

    /// How many images are still waiting for a description, out of the images
    /// that can carry one. Four pictures is the common case, and asking for
    /// each one separately is four round trips through the same sheet
    /// (docs/10 §5).
    public var imagesAwaitingDescription: Int {
        uploader.attachments.filter { $0.type == .image && !$0.hasAltText }.count
    }

    public private(set) var isDescribingAll = false
    public private(set) var describedCount = 0
    public private(set) var describeAllTotal = 0
    public private(set) var describeAllError: String?
    /// Set when the person stops the run early; the ones already done stay
    /// done, which is the only behaviour that makes Cancel worth pressing.
    private var describeAllCancelled = false

    /// Describes every image that has no description, one at a time.
    ///
    /// Sequential rather than concurrent on purpose: the language model is the
    /// scarce resource, four at once queues behind it anyway and reports a
    /// single failure for four attempts.
    public func describeAllImages(environment: AppEnvironment) async {
        guard !isDescribingAll else { return }
        let pending = uploader.attachments.filter { $0.type == .image && !$0.hasAltText }
        guard !pending.isEmpty else { return }

        isDescribingAll = true
        describedCount = 0
        describeAllTotal = pending.count
        describeAllError = nil
        describeAllCancelled = false
        defer { isDescribingAll = false }

        for attachment in pending {
            if describeAllCancelled { break }

            guard let url = attachment.displayImageURL,
                let (data, _) = try? await URLSession.shared.data(from: url)
            else {
                describeAllError = String(
                    localized: "Couldn't read that image.", comment: "Alt text generation failure")
                continue
            }

            do {
                let generated = try await environment.intelligence.describeImage(data)
                guard AltTextGuidance.looksAcceptable(generated) else {
                    describeAllError = String(
                        localized: "One description didn't come out usable.",
                        comment: "Alt text generation rejected")
                    continue
                }
                await uploader.updateDescription(generated, for: attachment.id)
            } catch {
                // One picture that could not be described does not undo the
                // ones that were: the run continues and says so at the end.
                describeAllError = String(
                    localized: "One description couldn't be generated.",
                    comment: "Alt text generation failure")
                continue
            }

            describedCount += 1
        }
    }

    /// Stops a run after the image it is on. Already-described images keep
    /// their descriptions.
    public func cancelDescribeAll() {
        describeAllCancelled = true
    }

    public enum QuotePolicy: String, CaseIterable, Identifiable, Sendable {
        case `public`, followers, nobody
        public var id: String { rawValue }
    }

    /// A place: one the server knows, or a new name to make one from.
    public enum ComposerPlace: Hashable, Sendable {
        case known(Place)
        case new(name: String, country: String)

        public var displayName: String {
            switch self {
            case .known(let place): place.displayName
            case .new(let name, let country):
                country.isEmpty ? name : "\(name), \(country)"
            }
        }
    }

    public let replyTo: Status?
    public let uploader: ComposerUploader
    /// Segments after the first, posted as a chain (docs/07 §5).
    public var threadSegments: [String] = []
    public let session: AccountSession
    private var idempotencyKey = UUID().uuidString
    private var postedSegmentCount = 0
    private var draftID = UUID()
    private var completionTask: Task<Void, Never>?

    /// The status being edited, where this composer is editing one.
    public private(set) var editingStatus: Status?

    public init(session: AccountSession, replyTo: Status? = nil, quoting: Status? = nil) {
        self.session = session
        self.replyTo = replyTo
        self.quoting = quoting
        self.uploader = ComposerUploader(session: session)
    }

    public init(session: AccountSession, editing status: Status, source: StatusSource) {
        self.session = session
        self.replyTo = nil
        self.quoting = nil
        self.language = status.language
        self.uploader = ComposerUploader(session: session)
        self.editingStatus = status
        self.text = source.text
        self.spoilerText = source.spoilerText
        self.showsContentWarningField = !source.spoilerText.isEmpty
        self.visibility = status.visibility
        uploader.restore(status.mediaAttachments)
    }

    public var title: String {
        if editingStatus != nil {
            return String(localized: "Edit post", comment: "Composer title")
        }
        if replyTo != nil { return String(localized: "Reply", comment: "Composer title") }
        if quoting != nil { return String(localized: "Quote", comment: "Composer title") }
        return String(localized: "New post", comment: "Composer title")
    }

    /// Uploads first, then library pictures, in the order they were added.
    public var attachments: [MediaAttachment] { uploader.attachments + libraryAttachments }

    public var limits: ServerLimits { session.capabilities.limits }

    public var capabilities: ServerCapabilities { session.capabilities }

    public var isNextcloud: Bool { session.capabilities.isNextcloudSocial }

    /// The account's default language, offered first in the picker.
    public var defaultLanguage: String? { session.settings.defaultLanguage }

    /// Quote posts, where the server has them.
    public var canQuote: Bool { capabilities.quotePosts || isNextcloud }

    public var hasPoll: Bool { !pollOptions.isEmpty }

    /// Whether these words are short enough, and alone enough, to be a card.
    public var canBeCard: Bool {
        editingStatus == nil
            && TextCard.fits(text, attachments: attachments.count, hasPoll: hasPoll)
    }

    public var canAddMedia: Bool {
        attachments.count < limits.maxMediaAttachments && !hasPoll
    }

    public var hasVideoAttachment: Bool {
        attachments.contains { $0.type.isPlayable }
    }

    /// The composer's own removal, since a library picture is not the
    /// uploader's to forget.
    public func removeAttachment(_ id: String) {
        uploader.remove(id)
        libraryAttachments.removeAll { $0.id == id }
        focalPoints[id] = nil
    }

    // MARK: - Nextcloud extras

    /// Attaches a picture from the instance's GIF library.
    public func attachLibraryPicture(_ entry: GIFEntry) async {
        guard canAddMedia else { return }
        do {
            let attachment = try await session.client.decode(
                MediaAttachment.self,
                from: Endpoint.gifs.attach(slug: entry.slug, description: entry.title))
            libraryAttachments.append(attachment)
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "Couldn't attach that picture.", comment: "GIF attach failed")
        }
    }

    /// Saves the point a cropped preview keeps in frame, in −1…1.
    public func setFocalPoint(_ point: CGPoint, for attachment: MediaAttachment) async {
        focalPoints[attachment.id] = point
        do {
            _ = try await session.client.send(
                Endpoint.mediaExtra.updateFocus(
                    attachment.id, x: point.x, y: point.y, description: attachment.description))
        } catch {
            await session.handle(error)
        }
    }

    /// Inserts a custom emoji as `:shortcode:` at the end of the text.
    public func insert(emoji: CustomEmoji) {
        let needsSpace = !(text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n"))
        text += (needsSpace ? " " : "") + ":\(emoji.shortcode): "
    }

    public func insert(snippet: String) {
        let needsSpace = !(text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n"))
        text += (needsSpace ? " " : "") + snippet
    }

    private func loadTeams() async {
        guard isNextcloud else { return }
        teams =
            (try? await session.client.decode(TeamList.self, from: Endpoint.teams.all))?.teams ?? []
    }

    public var isThread: Bool { !threadSegments.isEmpty }

    public func addThreadSegment() { threadSegments.append("") }

    public func removeThreadSegment(at index: Int) {
        guard threadSegments.indices.contains(index) else { return }
        threadSegments.remove(at: index)
    }

    public func prepare() async {
        // An edit already carries everything from `/source`; re-deriving the
        // defaults here would overwrite what the person wrote.
        guard editingStatus == nil else { return }

        visibility =
            replyTo.map {
                // A reply can never be less restrictive than what it answers.
                $0.replyVisibility(default: session.settings.defaultVisibility)
            } ?? session.settings.defaultVisibility

        showsContentWarningField = session.settings.alwaysShowContentWarningField
        language = session.settings.defaultLanguage
        await loadTeams()

        if let replyTo {
            let handles = replyTo.replyMentions(excluding: session.snapshot.handle)
            if !handles.isEmpty {
                text = handles.map { "@\($0)" }.joined(separator: " ") + " "
            }
        }
    }

    // MARK: - Character counting

    /// Delegates to `CharacterCount`, which keeps the URL flat rate and the
    /// grapheme-vs-UTF-16 trap in one tested place.
    public var remainingCharacters: Int? {
        CharacterCount.remaining(text: text, spoilerText: spoilerText, limits: limits)
    }

    public var canPost: Bool {
        guard !isPosting else { return false }
        guard (remainingCharacters ?? 0) >= 0 else { return false }
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || !attachments.isEmpty || quoting != nil
    }

    public var visibilitySymbol: String {
        switch visibility {
        case .public: "globe"
        case .unlisted: "eye.slash"
        case .private: "lock"
        case .direct: "envelope"
        case .unknownCase: "questionmark"
        }
    }

    // MARK: - Poll

    public func togglePoll() {
        if hasPoll {
            pollOptions = []
        } else {
            pollOptions = ["", ""]
        }
    }

    public func addPollOption() {
        guard pollOptions.count < limits.maxPollOptions else { return }
        pollOptions.append("")
    }

    // MARK: - Autocomplete

    private func updateCompletions() {
        completionTask?.cancel()
        guard let token = currentToken else {
            completions = []
            return
        }

        completionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            await self.fetchCompletions(for: token)
        }
    }

    private var currentToken: (prefix: Character, query: String)? {
        guard let last = text.split(separator: " ", omittingEmptySubsequences: false).last,
            let first = last.first, first == "@" || first == "#"
        else { return nil }
        let query = String(last.dropFirst())
        guard query.count >= 2 else { return nil }
        return (first, query)
    }

    private func fetchCompletions(for token: (prefix: Character, query: String)) async {
        do {
            if token.prefix == "@" {
                // This route specifically: no client substitutes /api/v2/search
                // for it, and Nextcloud Social serves it because a composer
                // needs it (docs/07 §2).
                let accounts = try await session.client.decode(
                    LossyArray<Account>.self,
                    from: Endpoint.accounts.search(token.query, limit: 6))
                completions = accounts.elements.map { "@\($0.acct)" }
            } else {
                let results = try await session.client.decode(
                    SearchResults.self,
                    from: Endpoint.search.search(token.query, type: "hashtags", limit: 6))
                completions = results.hashtags.map { "#\($0.name)" }
            }
        } catch {
            completions = []
        }
    }

    public func apply(completion: String) {
        var pieces = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard !pieces.isEmpty else { return }
        pieces[pieces.count - 1] = completion
        text = pieces.joined(separator: " ") + " "
        completions = []
    }

    // MARK: - Intelligence

    public func rewrite(_ style: RewriteStyle, using intelligence: any IntelligenceProviding) async
    {
        do {
            // Presented for review, never applied in place.
            let proposal = try await intelligence.rewrite(
                text, style: style, maximumCharacters: limits.maxStatusCharacters)
            text = proposal
        } catch IntelligenceError.refused {
            errorMessage = String(
                localized: "Apple Intelligence didn't want to rewrite that.",
                comment: "Rewrite refused")
        } catch IntelligenceError.tooLong {
            errorMessage = String(
                localized: "That didn't fit.", comment: "Rewrite too long")
        } catch {
            errorMessage = String(
                localized: "Couldn't rewrite that.", comment: "Rewrite failed")
        }
    }

    // MARK: - Posting

    /// Draws the card and uploads it, with the words as its description so a
    /// reader using a screen reader gets the post rather than "image".
    private func uploadCard(backgroundID: String) async -> String? {
        #if canImport(ImageIO)
            let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let backgrounds = TextCard.backgrounds(
                accountHue: Monogram.hue(for: session.snapshot.qualifiedHandle))
            let background = backgrounds.first { $0.id == backgroundID } ?? backgrounds[0]
            guard let data = TextCard.render(text: words, background: background) else {
                return nil
            }

            do {
                let attachment = try await session.client.decode(
                    MediaAttachment.self,
                    from: Endpoint.media.upload(
                        data: data, filename: "card.png", mimeType: "image/png",
                        description: words, v2: true))
                return attachment.id
            } catch {
                await session.handle(error)
                return nil
            }
        #else
            return nil
        #endif
    }

    @discardableResult
    public func post(skippingAltTextCheck: Bool = false) async -> Bool {
        guard canPost else { return false }

        if !skippingAltTextCheck,
            session.settings.warnAboutMissingAltText,
            attachments.contains(where: { !$0.hasAltText })
        {
            isShowingAltTextWarning = true
            return false
        }

        isPosting = true
        defer { isPosting = false }

        // The games are played here, once, and what travels is their result.
        // Rolling in the view would re-roll on every redraw; rolling on the
        // server would let the same post say two different things.
        let played = ComposerCommands.resolve(text)
        playedGames = played.results

        // The card is drawn from what was typed rather than from what the dice
        // said: a card is a short thought on colour, and a rolled die on one
        // would be a picture of a number.
        var cardAttachmentID: String?
        if let backgroundID = cardBackgroundID, canBeCard {
            guard let id = await uploadCard(backgroundID: backgroundID) else {
                // The web refuses too. A card that could not be drawn must not
                // quietly become a plain post the writer did not choose.
                errorMessage = String(
                    localized: "The card couldn't be drawn, so nothing was posted.",
                    comment: "Composer card failure")
                return false
            }
            cardAttachmentID = id
        }

        var draft = StatusPost(
            text: played.text,
            visibility: visibility,
            spoilerText: spoilerText.isEmpty ? nil : spoilerText,
            sensitive: !spoilerText.isEmpty || session.settings.defaultSensitive,
            language: language ?? session.settings.defaultLanguage,
            inReplyToID: replyTo?.id,
            mediaIDs: cardAttachmentID.map { [$0] } ?? attachments.map(\.id),
            pollOptions: pollOptions.filter { !$0.isEmpty },
            pollMultiple: pollMultiple,
            scheduledAt: scheduledAt,
            idempotencyKey: idempotencyKey
        )
        if let quoting {
            draft.quotedID = quoting.id
        }
        if canQuote, quotePolicy != .public {
            draft.quotePolicy = quotePolicy.rawValue
        }
        switch place {
        case .known(let known):
            draft.placeID = known.id
        case .new(let name, let country):
            draft.placeName = name
            draft.placeCountry = country.isEmpty ? nil : country
        case nil:
            break
        }
        draft.postAs = postAs?.handle
        if hasVideoAttachment {
            draft.videoTitle = videoTitle.isEmpty ? nil : videoTitle
            draft.videoCategory = videoCategory.isEmpty ? nil : videoCategory
            draft.videoLicence = videoLicence.isEmpty ? nil : videoLicence
        }

        do {
            let posted: Status
            if let editingStatus {
                posted = try await session.client.decode(
                    Status.self, from: Endpoint.composing.edit(editingStatus.id, draft))
            } else {
                // One request, decoded twice: the status, and the one extra
                // flag Nextcloud Social adds when a moderator must look first.
                let response = try await session.client.send(Endpoint.composing.post(draft))
                posted = try AlohaJSON.decoder.decode(Status.self, from: response.data)
                let flags = try? AlohaJSON.decoder.decode(ReviewFlags.self, from: response.data)
                wasHeldForReview = flags?.heldForReview ?? false
            }
            try? await session.timelineStore.updateStatus(accountID: session.id, status: posted)
            if editingStatus == nil, !wasHeldForReview { session.notePosted(posted) }

            // A failure part-way through a thread stops, keeps what posted, and
            // resumes from the failed segment — it must never double-post.
            if !threadSegments.isEmpty, editingStatus == nil {
                var parentID = posted.id
                while let next = threadSegments.first {
                    let segment = StatusPost(
                        text: ComposerCommands.resolve(
                            numbered(next, index: postedSegmentCount + 1)
                        ).text,
                        visibility: visibility,
                        spoilerText: spoilerText.isEmpty ? nil : spoilerText,
                        sensitive: !spoilerText.isEmpty,
                        language: language ?? session.settings.defaultLanguage,
                        inReplyToID: parentID)
                    let reply = try await session.client.decode(
                        Status.self, from: Endpoint.composing.post(segment))
                    parentID = reply.id
                    session.notePosted(reply)
                    threadSegments.removeFirst()
                    postedSegmentCount += 1
                }
            }

            try? await session.supportStore.deleteDraft(id: draftID)
            return true
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "Couldn't post that.", comment: "Post failed")
            // The composer keeps everything intact so the person can retry.
            await saveDraftIfNeeded(queued: (error as? APIError)?.isTransient ?? false)
            return false
        }
    }

    /// The one field beyond the Status entity a post can come back with.
    private struct ReviewFlags: Decodable {
        var heldForReview: Bool?
        enum CodingKeys: String, CodingKey { case heldForReview = "held_for_review" }
    }

    /// Optional "1/5" numbering, appended at post time and off by default.
    private func numbered(_ text: String, index: Int) -> String {
        guard session.settings.appendThreadNumbering else { return text }
        let total = threadSegments.count + postedSegmentCount + 1
        return "\(text)\n\n\(index + 1)/\(total)"
    }

    public func saveDraftIfNeeded(queued: Bool = false) async {
        let snapshot = DraftSnapshot(
            id: draftID, accountID: session.id, text: text, spoilerText: spoilerText,
            visibility: visibility, inReplyToID: replyTo?.id,
            uploadedMediaIDs: attachments.map(\.id),
            pollOptions: pollOptions.filter { !$0.isEmpty }, pollMultiple: pollMultiple,
            idempotencyKey: idempotencyKey, queuedForSend: queued)

        guard !snapshot.isEmpty else { return }
        _ = try? await session.supportStore.saveDraft(snapshot)
    }
}
