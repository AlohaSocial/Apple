// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// One draft as it is kept in the account's own Nextcloud: a JSON file per
/// draft, `Aloha Social/Drafts/<id>.json` (docs/14 §7).
///
/// A deleted draft leaves a **tombstone** — the same file with `deletedAt`
/// and no content — so a device that was offline learns it was deleted
/// rather than putting it back. Tombstones are cleared after
/// `DraftMerge.tombstoneLifetime`.
///
/// Readable on purpose. It is the person's own file in their own Files, and
/// a draft somebody can open in a text editor when this app is gone is a
/// draft that was never locked in.
public struct DraftSyncFile: Codable, Sendable, Hashable {
    /// Bumped only by a change an older build would misread. A file in a
    /// newer format is left alone — neither imported nor written over, which
    /// would drop what this build does not know about.
    public static let currentFormat = 1

    public var format: Int
    public var id: UUID
    /// When the draft was last changed, on whichever device changed it.
    public var updatedAt: Date
    /// Set on a tombstone.
    public var deletedAt: Date?
    /// Nil on a tombstone.
    public var draft: Content?

    public init(
        format: Int = DraftSyncFile.currentFormat, id: UUID, updatedAt: Date,
        deletedAt: Date? = nil, draft: Content?
    ) {
        self.format = format
        self.id = id
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.draft = draft
    }

    public var isTombstone: Bool { deletedAt != nil || draft == nil }

    /// The moment this version stands for: the edit, or the deletion.
    public var stamp: Date { deletedAt ?? updatedAt }

    public static func tombstone(_ id: UUID, deletedAt: Date) -> DraftSyncFile {
        DraftSyncFile(id: id, updatedAt: deletedAt, deletedAt: deletedAt, draft: nil)
    }

    /// Everything about a draft that two devices could disagree on. Two
    /// equal contents are the same draft whatever their times say.
    ///
    /// The send-queue state is not here: whether a draft is waiting to send
    /// is the device's own business, and a draft that arrived queued could
    /// be sent by both. Nor are paths to files on the device, which mean
    /// nothing anywhere else; their number travels instead, so the other
    /// device can say they were left behind.
    ///
    /// Media already uploaded travels as its ids. They are the account's,
    /// on the account's own server, so the other device can attach them as
    /// they are — and where the server has since removed them, reopening
    /// the draft says so (`ComposerModel.restoreContext`).
    public struct Content: Codable, Sendable, Hashable {
        public var text: String
        public var spoilerText: String
        public var visibility: String
        public var sensitive: Bool
        public var language: String?
        public var inReplyToID: String?
        public var uploadedMediaIDs: [String]
        public var attachmentsLeftOnDevice: Int
        public var pollOptions: [String]
        public var pollExpiresIn: Int?
        public var pollMultiple: Bool
        public var pollHideTotals: Bool
        public var scheduledAt: Date?
        public var idempotencyKey: String
        public var threadSegments: [String]
        public var threadPosition: Int
        public var threadIndex: Int
        public var threadGroupID: UUID?
        public var quotedID: String?
        public var quotePolicy: String?
        public var replyPolicy: String?
        public var marksAsAIGenerated: Bool
        public var placeID: String?
        public var placeName: String?
        public var placeCountry: String?
        public var postAs: String?
        public var cardBackgroundID: String?
        public var videoTitle: String?
        public var videoCategory: String?
        public var videoLicence: String?
        public var isConflictCopy: Bool

        public init(_ draft: DraftSnapshot) {
            text = draft.text
            spoilerText = draft.spoilerText
            visibility = draft.visibility.rawValue
            sensitive = draft.sensitive
            language = draft.language
            inReplyToID = draft.inReplyToID
            uploadedMediaIDs = draft.uploadedMediaIDs
            attachmentsLeftOnDevice =
                draft.localMediaPaths.isEmpty
                ? draft.attachmentsLeftOnOtherDevice : draft.localMediaPaths.count
            pollOptions = draft.pollOptions
            pollExpiresIn = draft.pollExpiresIn
            pollMultiple = draft.pollMultiple
            pollHideTotals = draft.pollHideTotals
            scheduledAt = draft.scheduledAt
            idempotencyKey = draft.idempotencyKey
            threadSegments = draft.threadSegments
            threadPosition = draft.threadPosition
            threadIndex = draft.threadIndex
            threadGroupID = draft.threadGroupID
            quotedID = draft.quotedID
            quotePolicy = draft.quotePolicy
            replyPolicy = draft.replyPolicy
            marksAsAIGenerated = draft.marksAsAIGenerated
            placeID = draft.placeID
            placeName = draft.placeName
            placeCountry = draft.placeCountry
            postAs = draft.postAs
            cardBackgroundID = draft.cardBackgroundID
            videoTitle = draft.videoTitle
            videoCategory = draft.videoCategory
            videoLicence = draft.videoLicence
            isConflictCopy = draft.isSyncConflictCopy
        }

        /// Field by field with a default for each, so a file written by a
        /// build that knew a field fewer, or one hand-edited, still reads.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
                (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
            }
            text = value(.text, "")
            spoilerText = value(.spoilerText, "")
            visibility = value(.visibility, Visibility.public.rawValue)
            sensitive = value(.sensitive, false)
            language = value(.language, nil)
            inReplyToID = value(.inReplyToID, nil)
            uploadedMediaIDs = value(.uploadedMediaIDs, [])
            attachmentsLeftOnDevice = value(.attachmentsLeftOnDevice, 0)
            pollOptions = value(.pollOptions, [])
            pollExpiresIn = value(.pollExpiresIn, nil)
            pollMultiple = value(.pollMultiple, false)
            pollHideTotals = value(.pollHideTotals, false)
            scheduledAt = value(.scheduledAt, nil)
            // A draft without a key gets one: two devices sending it with
            // none would each post a copy.
            idempotencyKey = value(.idempotencyKey, UUID().uuidString)
            threadSegments = value(.threadSegments, [])
            threadPosition = value(.threadPosition, 0)
            threadIndex = value(.threadIndex, 0)
            threadGroupID = value(.threadGroupID, nil)
            quotedID = value(.quotedID, nil)
            quotePolicy = value(.quotePolicy, nil)
            replyPolicy = value(.replyPolicy, nil)
            marksAsAIGenerated = value(.marksAsAIGenerated, false)
            placeID = value(.placeID, nil)
            placeName = value(.placeName, nil)
            placeCountry = value(.placeCountry, nil)
            postAs = value(.postAs, nil)
            cardBackgroundID = value(.cardBackgroundID, nil)
            videoTitle = value(.videoTitle, nil)
            videoCategory = value(.videoCategory, nil)
            videoLicence = value(.videoLicence, nil)
            isConflictCopy = value(.isConflictCopy, false)
        }

        /// The draft this content describes, as this device stores it.
        func snapshot(id: UUID, accountID: UUID, updatedAt: Date) -> DraftSnapshot {
            var draft = DraftSnapshot(
                id: id, accountID: accountID, text: text, spoilerText: spoilerText,
                visibility: Visibility(rawValue: visibility) ?? .public, sensitive: sensitive,
                language: language, inReplyToID: inReplyToID,
                uploadedMediaIDs: uploadedMediaIDs, pollOptions: pollOptions,
                pollExpiresIn: pollExpiresIn, pollMultiple: pollMultiple,
                scheduledAt: scheduledAt, idempotencyKey: idempotencyKey,
                threadIndex: threadIndex, threadGroupID: threadGroupID, quotedID: quotedID,
                quotePolicy: quotePolicy, threadSegments: threadSegments,
                updatedAt: updatedAt)
            draft.pollHideTotals = pollHideTotals
            draft.threadPosition = threadPosition
            draft.replyPolicy = replyPolicy
            draft.marksAsAIGenerated = marksAsAIGenerated
            draft.placeID = placeID
            draft.placeName = placeName
            draft.placeCountry = placeCountry
            draft.postAs = postAs
            draft.cardBackgroundID = cardBackgroundID
            draft.videoTitle = videoTitle
            draft.videoCategory = videoCategory
            draft.videoLicence = videoLicence
            draft.isSyncConflictCopy = isConflictCopy
            draft.attachmentsLeftOnOtherDevice = attachmentsLeftOnDevice
            return draft
        }
    }

    /// The file for a draft as this device has it.
    public init(_ draft: DraftSnapshot) {
        self.init(id: draft.id, updatedAt: draft.updatedAt, draft: Content(draft))
    }

    /// The draft in this file, for this device's account. Nil for a
    /// tombstone.
    public func snapshot(accountID: UUID) -> DraftSnapshot? {
        draft?.snapshot(id: id, accountID: accountID, updatedAt: updatedAt)
    }

    // MARK: - Coding

    /// ISO 8601 with milliseconds. Whole seconds would make two edits a
    /// moment apart the same time, and the merge compares times.
    public func encoded() throws -> Data {
        try Self.encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> DraftSyncFile {
        try decoder.decode(DraftSyncFile.self, from: data)
    }

    /// Sorted and indented: a person reading their own file, or a diff in
    /// Nextcloud's version history, should find it legible.
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Self.timestamp))
        }
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = try? Self.timestamp.parse(raw) { return date }
            if let date = try? Date.ISO8601FormatStyle().parse(raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Not an ISO 8601 date: \(raw)")
        }
        return decoder
    }()

    private static let timestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// The file name a draft is kept under, and the id read back from one.
    public static func fileName(for id: UUID) -> String { "\(id.uuidString).json" }

    public static func id(fromFileName name: String) -> UUID? {
        guard name.hasSuffix(".json") else { return nil }
        return UUID(uuidString: String(name.dropLast(".json".count)))
    }
}
