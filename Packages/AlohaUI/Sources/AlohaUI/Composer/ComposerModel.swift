// SPDX-License-Identifier: MIT

import AlohaHTML
import AlohaIntelligence
import AlohaMedia
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

    /// The post being quoted, when the composer opened for a quote. A
    /// reopened draft only knows the id, and fetches the post to show it.
    public private(set) var quoting: Status?
    /// Who may quote the new post: `public`, `followers` or `nobody`.
    public var quotePolicy: QuotePolicy = .public
    /// Who may reply to the new post (Aloha Social's `reply_policy`).
    public var replyPolicy: ReplyPolicy = .everyone
    /// Says the post was made with AI. There is no API field for it: the
    /// server reads it from a hashtag (`AiContentService::DEFAULT_TAGS`), so
    /// the switch adds one, which every other server can read too.
    public var marksAsAIGenerated = false
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
    /// Set after posting when the server took the post for later rather than
    /// making it now: the time it says the post will go out, which the
    /// composer confirms instead of closing as though it had posted.
    public private(set) var scheduledFor: Date?
    /// The last attempt failed in a way that says nothing about whether the
    /// server made the post — a timeout, a dropped connection, a 5xx. The
    /// server only stores the `Idempotency-Key` once the post exists
    /// (`StatusApiController::createPost`), so a retry that overtakes a slow
    /// first attempt is not caught there. Checked before the next send.
    private var previousAttemptMayHaveLanded = false
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
    /// Library pictures asked for and not yet back.
    private var libraryAttachmentsInFlight = 0

    /// Whether an attachment is still on its way — an upload, a video the
    /// server is processing, a library picture — or a reopened draft is still
    /// looking its uploads up. Posting now would leave it behind.
    public var isUploading: Bool {
        uploader.isBusy || libraryAttachmentsInFlight > 0 || !pendingMediaIDs.isEmpty
    }
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

    public private(set) var replyTo: Status?
    public let uploader: ComposerUploader
    /// Segments after the first, posted as a chain (docs/07 §5).
    public var threadSegments: [String] = []
    public let session: AccountSession
    private var idempotencyKey = UUID().uuidString
    private var postedSegmentCount = 0
    /// How far a thread got before something failed: how many of its posts
    /// are out, and the last one's id. Set, the next attempt — here or from
    /// the send queue — continues from there and never posts the first one
    /// again (docs/07 §5).
    private var threadProgress: (posted: Int, lastID: String)?
    /// Where the text in the box sits in its thread: 0 for a new post, more
    /// for a reopened thread whose first posts already went out.
    private var threadBasePosition = 0
    /// The team account a reopened draft posts as, matched once the teams
    /// have loaded.
    private var restoredPostAsHandle: String?
    private var draftID = UUID()
    /// Set once the post is out (or scheduled): from then on there is no
    /// draft to save, whatever the composer still shows.
    private var hasPosted = false
    /// Whether this composer has saved its draft, so emptying the box and
    /// leaving takes that draft away again.
    private var hasSavedDraft = false
    /// When the store recorded this composer's last save, to tell whether the
    /// draft has been saved, posted or deleted elsewhere since.
    private var savedAt: Date?
    /// The last attempt failed in a way the send queue will retry, and the
    /// draft was saved queued; saving it again keeps it so.
    private var isQueuedForSend = false
    private var completionTask: Task<Void, Never>?

    /// The status being edited, where this composer is editing one.
    public private(set) var editingStatus: Status?

    /// The post a delete & redraft started from. It is deleted only once the
    /// new one has posted, so a redraft that fails loses nothing (docs/07 §8).
    public private(set) var redrafting: Status?

    /// What a reopened draft or a redraft knows only by id. The ids are what
    /// the post needs; the statuses are fetched in `prepare()` for show.
    private var restoredReplyToID: String?
    private var restoredQuotedID: String?
    private var pendingMediaIDs: [String] = []
    /// Uploads a reopened draft could not look up, kept by id so they still
    /// go out with the post.
    private var unresolvedMediaIDs: [String] = []
    /// A reopened draft or a redraft already says what it wants; the account
    /// defaults that `prepare()` applies to a fresh post would overwrite it.
    private var isRestored = false
    private var isPrepared = false

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
        uploader.restore(status.mediaAttachments, attachedToPost: true)
    }

    /// Reopens a saved draft as it was left, under the same id — saving it
    /// again replaces it rather than adding a second copy.
    public init(session: AccountSession, draft: DraftSnapshot) {
        self.session = session
        self.replyTo = nil
        self.quoting = nil
        self.uploader = ComposerUploader(session: session)
        self.isRestored = true
        self.draftID = draft.id
        self.restoredReplyToID = draft.inReplyToID
        self.restoredQuotedID = draft.quotedID
        self.pendingMediaIDs = draft.uploadedMediaIDs
        self.text = draft.text
        self.spoilerText = draft.spoilerText
        self.showsContentWarningField = !draft.spoilerText.isEmpty
        self.visibility = draft.visibility
        self.language = draft.language
        self.scheduledAt = draft.scheduledAt
        self.pollOptions = draft.pollOptions
        self.pollMultiple = draft.pollMultiple
        self.threadSegments = draft.threadSegments
        self.quotePolicy = draft.quotePolicy.flatMap(QuotePolicy.init(rawValue:)) ?? .public
        self.replyPolicy = draft.replyPolicy.flatMap(ReplyPolicy.init(rawValue:)) ?? .everyone
        self.marksAsAIGenerated = draft.marksAsAIGenerated
        if let placeID = draft.placeID {
            self.place = .known(
                Place(id: placeID, name: draft.placeName ?? "", country: draft.placeCountry))
        } else if let name = draft.placeName {
            self.place = .new(name: name, country: draft.placeCountry ?? "")
        }
        self.restoredPostAsHandle = draft.postAs
        self.cardBackgroundID = draft.cardBackgroundID
        self.videoTitle = draft.videoTitle ?? ""
        self.videoCategory = draft.videoCategory ?? ""
        self.videoLicence = draft.videoLicence ?? ""
        // A thread that already went out in part: this draft is its next
        // segment, already replying to the last one that made it, and it
        // keeps its place in the thread for its key and its numbering.
        self.threadBasePosition = draft.threadPosition
        // After the text: the same words keep the same key, so a send that
        // may already have landed is recognised by the server, not repeated.
        self.idempotencyKey = draft.idempotencyKey
    }

    /// Delete & redraft: a fresh composer holding what the post said, from
    /// `/source` rather than the rendered HTML.
    public init(session: AccountSession, redrafting status: Status, source: StatusSource) {
        self.session = session
        self.replyTo = nil
        self.quoting = nil
        self.uploader = ComposerUploader(session: session)
        self.isRestored = true
        self.redrafting = status
        self.restoredReplyToID = status.inReplyToID
        self.restoredQuotedID = status.quoteID
        self.text = source.text
        self.spoilerText = source.spoilerText
        self.showsContentWarningField = !source.spoilerText.isEmpty
        self.visibility = status.visibility
        self.language = status.language
        if let poll = status.poll {
            self.pollOptions = poll.options.map(\.title)
            self.pollMultiple = poll.multiple
        }
        self.quotePolicy =
            status.quoteApprovalPolicy.flatMap(QuotePolicy.init(rawValue:)) ?? .public
        uploader.restore(status.mediaAttachments, attachedToPost: true)
    }
    public var title: String {
        if editingStatus != nil {
            return String(localized: "Edit post", comment: "Composer title")
        }
        if redrafting != nil {
            return String(localized: "Redraft", comment: "Composer title")
        }
        if replyTo != nil || restoredReplyToID != nil {
            return String(localized: "Reply", comment: "Composer title")
        }
        if quoting != nil || restoredQuotedID != nil {
            return String(localized: "Quote", comment: "Composer title")
        }
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
        libraryAttachmentsInFlight += 1
        defer { libraryAttachmentsInFlight -= 1 }
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
        if let handle = restoredPostAsHandle, postAs == nil {
            postAs = teams.first { $0.handle == handle }
        }
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
        guard editingStatus == nil, !isPrepared else { return }
        // Once: a full-screen cover such as the camera takes the composer off
        // screen and back, which starts its task again, and the defaults
        // below would undo what the person has chosen since.
        isPrepared = true
        if isRestored {
            await restoreContext()
            await loadTeams()
            return
        }

        visibility =
            replyTo.map {
                // A reply can never be less restrictive than what it answers.
                $0.replyVisibility(default: session.settings.defaultVisibility)
            } ?? session.settings.defaultVisibility

        showsContentWarningField = session.settings.alwaysShowContentWarningField
        language = session.settings.defaultLanguage

        // Before anything waits on the network, and only into an empty box:
        // by the time the teams answer the person may have started typing,
        // and the mentions must not land on top of that.
        if let replyTo, text.isEmpty {
            let handles = replyTo.replyMentions(excluding: session.snapshot.handle)
            if !handles.isEmpty {
                text = handles.map { "@\($0)" }.joined(separator: " ") + " "
            }
        }

        await loadTeams()
    }

    /// Fetches what a restored composer knows only by id: the post it
    /// answers, the post it quotes, and its uploads' previews.
    ///
    /// An upload that was never attached is swept by the server after a while
    /// (about a day on Mastodon), so a draft can outlive its media. Those are
    /// dropped with a word rather than sent: a post naming an id the server no
    /// longer has is refused whole.
    private func restoreContext() async {
        if replyTo == nil, let id = restoredReplyToID {
            replyTo = try? await session.client.decode(
                Status.self, from: Endpoint.statuses.status(id))
        }
        if quoting == nil, let id = restoredQuotedID {
            quoting = try? await session.client.decode(
                Status.self, from: Endpoint.statuses.status(id))
        }

        guard !pendingMediaIDs.isEmpty else { return }
        var restored: [MediaAttachment] = []
        for id in pendingMediaIDs {
            do {
                restored.append(
                    try await session.client.decode(
                        MediaAttachment.self, from: Endpoint.media.attachment(id)))
            } catch APIError.notFound {
                continue
            } catch {
                // Not known to be gone — offline, say. Keep the id: the post
                // will tell, and a draft that silently lost its pictures
                // because the network blinked would be worse.
                unresolvedMediaIDs.append(id)
            }
        }
        let expired = pendingMediaIDs.count - restored.count - unresolvedMediaIDs.count
        pendingMediaIDs = []
        uploader.restore(restored)
        if expired > 0 {
            errorMessage = String(
                localized:
                    "^[\(expired) attachment](inflect: true) expired on your server. Add it again to post it.",
                comment: "Reopened draft whose uploads the server has removed")
        }
    }

    // MARK: - Character counting

    /// Delegates to `CharacterCount`, which keeps the URL flat rate and the
    /// grapheme-vs-UTF-16 trap in one tested place.
    public var remainingCharacters: Int? {
        CharacterCount.remaining(text: text, spoilerText: spoilerText, limits: limits)
    }

    /// The one gate every way of posting goes through — the button, the
    /// keyboard shortcut, and `post()` itself.
    public var canPost: Bool {
        guard !isPosting, !isUploading else { return false }
        guard (remainingCharacters ?? 0) >= 0 else { return false }
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || !attachments.isEmpty || quoting != nil || restoredQuotedID != nil
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

    // MARK: - Posting

    /// Draws the card and uploads it, with the words as its description so a
    /// reader using a screen reader gets the post rather than "image".
    private func uploadCard(backgroundID: String) async -> String? {
        do {
            return try await Self.uploadCard(
                text: text, backgroundID: backgroundID, session: session)
        } catch {
            await session.handle(error)
            return nil
        }
    }

    /// The card for `text` on `backgroundID`, uploaded; nil where it cannot be
    /// drawn. Shared with the send queue, which draws a queued card the same
    /// way the composer would have.
    static func uploadCard(
        text: String, backgroundID: String, session: AccountSession
    ) async throws -> String? {
        #if canImport(ImageIO)
            let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let backgrounds = TextCard.backgrounds(
                accountHue: Monogram.hue(for: session.snapshot.qualifiedHandle))
            let background = backgrounds.first { $0.id == backgroundID } ?? backgrounds[0]
            guard let data = TextCard.render(text: words, background: background) else {
                return nil
            }
            let attachment = try await session.client.decode(
                MediaAttachment.self,
                from: Endpoint.media.upload(
                    data: data, filename: "card.png", mimeType: "image/png",
                    description: words, v2: true))
            return attachment.id
        #else
            return nil
        #endif
    }

    /// The hashtag the server reads as "made with AI", once. A post that
    /// already carries one of the server's own tags is left as it is.
    nonisolated static let aiGeneratedTag = "AIgenerated"

    nonisolated static func labelledAsAIGenerated(_ text: String) -> String {
        let known = ["#aigenerated", "#madewithai", "#ai", "#genai"]
        let words = text.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        if words.contains(where: { word in known.contains(String(word)) }) { return text }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "#\(aiGeneratedTag)" : "\(trimmed)\n\n#\(aiGeneratedTag)"
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

        if scheduledAt != nil, editingStatus == nil, hasThreadSegments {
            errorMessage = Self.threadCannotBeScheduled
            return false
        }

        isPosting = true
        defer { isPosting = false }

        // Sent from the queue while the composer stayed open: the post is
        // out, and Post only closes.
        if await sendQueueTookDraft() { return true }

        // The games are played here, once, and what travels is their result.
        // Rolling in the view would re-roll on every redraw; rolling on the
        // server would let the same post say two different things.
        let played = ComposerCommands.resolve(text)
        playedGames = played.results

        // The card is drawn from what was typed rather than from what the dice
        // said: a card is a short thought on colour, and a rolled die on one
        // would be a picture of a number. A thread whose first post is
        // already out has nothing left to draw.
        var cardAttachmentID: String?
        if threadProgress == nil, let backgroundID = cardBackgroundID, canBeCard {
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
            inReplyToID: replyTo?.id ?? restoredReplyToID,
            mediaIDs: cardAttachmentID.map { [$0] } ?? attachments.map(\.id) + unresolvedMediaIDs,
            pollOptions: pollOptions.filter { !$0.isEmpty },
            pollMultiple: pollMultiple,
            scheduledAt: scheduledAt,
            idempotencyKey: draftSnapshot.idempotencyKey(forPosition: threadBasePosition)
        )
        draft.quotedID = quoting?.id ?? restoredQuotedID
        if editingStatus != nil {
            draft.mediaAttributes = mediaAttributes
        }
        if canQuote, quotePolicy != .public {
            draft.quotePolicy = quotePolicy.rawValue
        }
        if isNextcloud, editingStatus == nil, replyPolicy != .everyone {
            draft.replyPolicy = replyPolicy
        }
        if isNextcloud, marksAsAIGenerated {
            draft.text = Self.labelledAsAIGenerated(draft.text)
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
        // Teams that did not load still leave the draft posting as the team
        // it was written for, never quietly as the person.
        draft.postAs = postAs?.handle ?? restoredPostAsHandle
        if hasVideoAttachment {
            draft.videoTitle = videoTitle.isEmpty ? nil : videoTitle
            draft.videoCategory = videoCategory.isEmpty ? nil : videoCategory
            draft.videoLicence = videoLicence.isEmpty ? nil : videoLicence
        }

        // The upload's Live Activity follows the post through to the end: an
        // upload that finished is not yet a post that went out.
        UploadActivityController.shared.posting()
        do {
            var parentID: String
            if let progress = threadProgress {
                // The first post went out on an earlier attempt; only the
                // rest of the thread is left.
                parentID = progress.lastID
            } else {
                let posted: Status
                if let editingStatus {
                    posted = try await session.client.decode(
                        Status.self, from: Endpoint.composing.edit(editingStatus.id, draft))
                } else {
                    if previousAttemptMayHaveLanded, draft.scheduledAt == nil,
                        let landed = await alreadyPosted(draft)
                    {
                        posted = landed
                    } else {
                        // One request, decoded twice: the status, and the one
                        // extra flag Nextcloud Social adds when a moderator
                        // must look first.
                        let response = try await session.client.send(
                            Endpoint.composing.post(draft))
                        switch try PostResponse(
                            decoding: response.data, scheduledAt: draft.scheduledAt)
                        {
                        case .scheduled(let scheduled):
                            // Nothing exists yet to show in a timeline or to
                            // hand to "posted": the server has the post and
                            // its time, and that is the whole of the success.
                            previousAttemptMayHaveLanded = false
                            scheduledFor = scheduled.scheduledAt
                            await finishPosting()
                            return true
                        case .posted(let status):
                            posted = status
                        }
                        let flags = try? AlohaJSON.decoder.decode(
                            ReviewFlags.self, from: response.data)
                        wasHeldForReview = flags?.heldForReview ?? false
                    }
                    previousAttemptMayHaveLanded = false
                    threadProgress = (threadBasePosition + 1, posted.id)
                }
                try? await session.timelineStore.updateStatus(
                    accountID: session.id, status: posted)
                if editingStatus == nil, !wasHeldForReview { session.notePosted(posted) }
                parentID = posted.id
            }

            // A failure part-way through a thread stops, keeps what posted, and
            // resumes from the failed segment — it must never double-post.
            if !threadSegments.isEmpty, editingStatus == nil {
                while let next = threadSegments.first {
                    let position = threadBasePosition + postedSegmentCount + 1
                    let segment = StatusPost(
                        text: ComposerCommands.resolve(
                            numbered(next, position: position)
                        ).text,
                        visibility: visibility,
                        spoilerText: spoilerText.isEmpty ? nil : spoilerText,
                        sensitive: !spoilerText.isEmpty,
                        language: language ?? session.settings.defaultLanguage,
                        inReplyToID: parentID,
                        idempotencyKey: draftSnapshot.idempotencyKey(forPosition: position))
                    let reply = try await session.client.decode(
                        Status.self, from: Endpoint.composing.post(segment))
                    parentID = reply.id
                    session.notePosted(reply)
                    threadSegments.removeFirst()
                    postedSegmentCount += 1
                    threadProgress = (position + 1, reply.id)
                }
            }
            await finishPosting()
            return true
        } catch {
            UploadActivityController.shared.postFailed()
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "Couldn't post that.", comment: "Post failed")
            // The composer keeps everything intact so the person can retry.
            let isTransient = (error as? APIError)?.isTransient ?? false
            if editingStatus == nil, isTransient { previousAttemptMayHaveLanded = true }
            isQueuedForSend = isTransient
            await saveDraftIfNeeded(queued: isTransient)
            return false
        }
    }

    /// What every success ends with, a post made or a post scheduled: the
    /// draft goes, and so does the post a redraft started from.
    private func finishPosting() async {
        hasPosted = true
        isQueuedForSend = false
        threadProgress = nil
        try? await session.supportStore.deleteDraft(id: draftID)
        // Only now: the original goes once its replacement exists — on the
        // server's schedule, for a scheduled one.
        if let redrafting {
            await StatusActions.delete(redrafting, session: session)
            self.redrafting = nil
        }
        UploadActivityController.shared.posted()
    }

    /// A scheduled post does not exist until its time, so the rest of a
    /// thread has nothing to reply to yet, and no server schedules a chain.
    /// Shared with the send queue, which refuses the same draft the same way.
    nonisolated static var threadCannotBeScheduled: String {
        String(
            localized: """
                A thread can't be scheduled. \
                Post it now, or schedule its first post on its own.
                """,
            comment: "Composer refusal: scheduled post with thread segments")
    }

    /// Whether any thread segment has words in it; empty ones are dropped.
    private var hasThreadSegments: Bool {
        threadSegments.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The post an attempt that timed out made after all, if it did: the same
    /// words, the same reply target and the same media, in the account's last
    /// few posts from the last quarter of an hour. Anything less certain than
    /// that posts again — a missing post is worse than a rare duplicate.
    private func alreadyPosted(_ draft: StatusPost) async -> Status? {
        let recent = try? await session.client.decode(
            LossyArray<Status>.self,
            from: Endpoint.timelines.timeline(
                .account(
                    id: session.snapshot.serverAccountID, includeReplies: true,
                    onlyMedia: false),
                limit: 5))
        let parser = StatusHTMLParser()
        let wanted = Self.normalised(draft.text)
        let cutoff = Date().addingTimeInterval(-15 * 60)
        return recent?.elements.first { status in
            status.createdAt >= cutoff
                && status.inReplyToID == draft.inReplyToID
                && Set(status.mediaAttachments.map(\.id)) == Set(draft.mediaIDs)
                && Self.normalised(parser.plainText(status.content)) == wanted
        }
    }

    /// Whitespace collapsed, because the server's HTML turns line breaks into
    /// paragraphs and the plain-text projection does not give them back as
    /// they were typed.
    private static func normalised(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The one field beyond the Status entity a post can come back with.
    private struct ReviewFlags: Decodable {
        var heldForReview: Bool?
        enum CodingKeys: String, CodingKey { case heldForReview = "held_for_review" }
    }

    /// Optional "2/5" numbering, appended at post time and off by default.
    private func numbered(_ text: String, position: Int) -> String {
        guard session.settings.appendThreadNumbering else { return text }
        let total = threadBasePosition + 1 + postedSegmentCount + threadSegments.count
        return Self.numbered(text, position: position, total: total)
    }

    /// The numbering the composer and the send queue both write, so a thread
    /// that finishes from the queue counts the way it started.
    nonisolated static func numbered(_ text: String, position: Int, total: Int) -> String {
        "\(text)\n\n\(position + 1)/\(total)"
    }

    /// Descriptions and focal points for the attachments an edit keeps. Sent
    /// for each of them, changed or not: the server rewrites what it is given
    /// and an unchanged description is the same description.
    private var mediaAttributes: [StatusPost.MediaAttribute] {
        uploader.attachments.map { attachment in
            StatusPost.MediaAttribute(
                id: attachment.id, description: attachment.description,
                // `String(format:)` is not localised, which is what the wire
                // needs: a decimal comma would read as a third coordinate.
                focus: focalPoints[attachment.id].map {
                    String(format: "%.2f,%.2f", Double($0.x), Double($0.y))
                })
        }
    }

    /// Everything the send queue needs to post this exactly as written, or a
    /// reopened composer needs to show it as it was left.
    ///
    /// For a thread that already went out in part, it is what is left: the
    /// next segment, replying to the last post that made it — never the first
    /// post again.
    public var draftSnapshot: DraftSnapshot {
        var snapshot = DraftSnapshot(
            id: draftID, accountID: session.id, text: text, spoilerText: spoilerText,
            visibility: visibility,
            sensitive: !spoilerText.isEmpty || session.settings.defaultSensitive,
            language: language ?? session.settings.defaultLanguage,
            inReplyToID: replyTo?.id ?? restoredReplyToID,
            // Library pictures are attachments like any other once made, so
            // their ids travel too.
            uploadedMediaIDs: attachments.map(\.id) + unresolvedMediaIDs,
            pollOptions: pollOptions.filter { !$0.isEmpty }, pollMultiple: pollMultiple,
            scheduledAt: scheduledAt, idempotencyKey: idempotencyKey,
            quotedID: quoting?.id ?? restoredQuotedID,
            quotePolicy: canQuote && quotePolicy != .public ? quotePolicy.rawValue : nil,
            threadSegments: threadSegments.filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        snapshot.threadPosition = threadBasePosition
        snapshot.replyPolicy =
            isNextcloud && replyPolicy != .everyone ? replyPolicy.rawValue : nil
        snapshot.marksAsAIGenerated = isNextcloud && marksAsAIGenerated
        switch place {
        case .known(let known):
            snapshot.placeID = known.id
            snapshot.placeName = known.name
            snapshot.placeCountry = known.country
        case .new(let name, let country):
            snapshot.placeName = name
            snapshot.placeCountry = country.isEmpty ? nil : country
        case nil:
            break
        }
        snapshot.postAs = postAs?.handle ?? restoredPostAsHandle
        snapshot.cardBackgroundID = canBeCard ? cardBackgroundID : nil
        if hasVideoAttachment {
            snapshot.videoTitle = videoTitle.isEmpty ? nil : videoTitle
            snapshot.videoCategory = videoCategory.isEmpty ? nil : videoCategory
            snapshot.videoLicence = videoLicence.isEmpty ? nil : videoLicence
        }
        if let progress = threadProgress {
            return snapshot.resuming(afterPosted: progress.posted, lastPostedID: progress.lastID)
        }
        return snapshot
    }

    /// Whether closing now would lose something — what a sheet asks before it
    /// lets a swipe take the composer away.
    public var hasUnsavedContent: Bool {
        editingStatus == nil ? !draftSnapshot.isEmpty : true
    }

    /// Saves the draft again once the uploads still going up have landed, so
    /// a file that finishes after the composer was closed joins the draft it
    /// was added to instead of going up for nothing. Saving is by the
    /// composer's draft id, so this replaces the save made on closing.
    public func saveDraftWhenUploadsSettle() async {
        guard uploader.activeUploads > 0 else { return }
        await uploader.uploadsSettled()
        // The draft may have been reopened from Drafts in the meantime, and
        // edited or posted there: that composer's version stands.
        guard await !draftChangedElsewhere() else { return }
        await saveDraftIfNeeded()
    }

    public func saveDraftIfNeeded(queued: Bool = false) async {
        // An edit is not a draft: the post exists, and a "draft" of it would
        // post a second copy when reopened. Nor is a post that went out.
        guard editingStatus == nil, !hasPosted else { return }
        guard await !sendQueueTookDraft() else { return }
        var snapshot = draftSnapshot
        snapshot.queuedForSend = queued

        guard !snapshot.isEmpty else {
            // Emptied since this composer saved it — on the way to the
            // background, say: the draft that save left goes too.
            if hasSavedDraft {
                try? await session.supportStore.deleteDraft(id: draftID)
                hasSavedDraft = false
            }
            return
        }
        guard (try? await session.supportStore.saveDraft(snapshot)) != nil else { return }
        hasSavedDraft = true
        savedAt = (try? await session.supportStore.draft(id: draftID))?.updatedAt
    }

    /// Whether the stored draft is no longer the one this composer last
    /// saved: gone — sent by the send queue, posted from another composer,
    /// deleted from Drafts — or saved since by something else, such as the
    /// queue keeping what is left of a thread or the same draft reopened and
    /// edited. This composer's copy is then out of date, and saving it would
    /// undo that.
    private func draftChangedElsewhere() async -> Bool {
        guard hasSavedDraft, let savedAt else { return false }
        // A store that cannot be read says nothing about the draft.
        let stored: DraftSnapshot?
        do { stored = try await session.supportStore.draft(id: draftID) } catch { return false }
        return stored?.updatedAt != savedAt
    }

    /// Whether the send queue has dealt with this composer's queued draft
    /// since it was saved: sent it, so the draft is gone, or sent the start
    /// of its thread, so the draft has moved on to what is left. Either way
    /// saving or posting the composer's copy would send again what already
    /// went out. From then on the queue's draft is the post, and this
    /// composer has nothing left to save.
    private func sendQueueTookDraft() async -> Bool {
        guard isQueuedForSend, await draftChangedElsewhere() else { return false }
        hasPosted = true
        isQueuedForSend = false
        return true
    }

    /// Saves what is in the composer as it stands, for when the app may get
    /// no other chance: iOS can end an app in the background without a word,
    /// and nothing after that runs. By the composer's own draft id, so the
    /// save made on closing later replaces this one rather than adding a
    /// second. A post that failed for want of a network stays queued, as the
    /// failure left it.
    ///
    /// Not while a post is on its way: it either lands, and must leave no
    /// draft, or fails, and saves its own.
    public func preserveDraft() async {
        guard !isPosting else { return }
        await saveDraftIfNeeded(queued: isQueuedForSend)
    }
}
