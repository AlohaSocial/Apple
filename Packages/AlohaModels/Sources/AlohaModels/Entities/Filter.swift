// SPDX-License-Identifier: MIT

import Foundation

/// Mastodon 4.x v2 filter. Nextcloud Social applies these server-side; the app
/// applies them again locally so a filter takes effect over cached content
/// immediately, and stops applying the moment it expires (docs/04 §6).
public struct Filter: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var title: String
    public var context: [FilterContext]
    public var expiresAt: Date?
    public var filterAction: FilterAction
    public var keywords: [Keyword]
    public var statuses: [StatusRef]

    public struct Keyword: Codable, Sendable, Hashable, Identifiable {
        @FlexibleID public var id: String
        public var keyword: String
        @LenientBool public var wholeWord: Bool

        enum CodingKeys: String, CodingKey {
            case id, keyword
            case wholeWord = "whole_word"
        }

        public init(id: String, keyword: String, wholeWord: Bool = false) {
            _id = .init(wrappedValue: id)
            self.keyword = keyword
            _wholeWord = .init(wrappedValue: wholeWord)
        }
    }

    public struct StatusRef: Codable, Sendable, Hashable, Identifiable {
        @FlexibleID public var id: String
        @FlexibleID public var statusID: String

        enum CodingKeys: String, CodingKey {
            case id
            case statusID = "status_id"
        }

        public init(id: String, statusID: String) {
            _id = .init(wrappedValue: id)
            _statusID = .init(wrappedValue: statusID)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, context, keywords, statuses
        case expiresAt = "expires_at"
        case filterAction = "filter_action"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        context = (try? c.decode(LossyArray<FilterContext>.self, forKey: .context))?.elements ?? []
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        filterAction = try c.decodeIfPresent(FilterAction.self, forKey: .filterAction) ?? .warn
        keywords = (try? c.decode(LossyArray<Keyword>.self, forKey: .keywords))?.elements ?? []
        statuses = (try? c.decode(LossyArray<StatusRef>.self, forKey: .statuses))?.elements ?? []
    }

    public init(
        id: String, title: String, context: [FilterContext] = [], expiresAt: Date? = nil,
        filterAction: FilterAction = .warn, keywords: [Keyword] = [], statuses: [StatusRef] = []
    ) {
        _id = .init(wrappedValue: id)
        self.title = title
        self.context = context
        self.expiresAt = expiresAt
        self.filterAction = filterAction
        self.keywords = keywords
        self.statuses = statuses
    }

    public func isExpired(at now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}
