// SPDX-License-Identifier: MIT

import Foundation

public struct Poll: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var expiresAt: Date?
    @LenientBool public var expired: Bool
    @LenientBool public var multiple: Bool
    @LenientInt public var votesCount: Int
    public var votersCount: Int?
    @LenientBool public var voted: Bool
    public var ownVotes: [Int]
    public var options: [Option]
    public var emojis: [CustomEmoji]

    public struct Option: Codable, Sendable, Hashable {
        public var title: String
        public var votesCount: Int?

        enum CodingKeys: String, CodingKey {
            case title
            case votesCount = "votes_count"
        }

        public init(title: String, votesCount: Int? = nil) {
            self.title = title
            self.votesCount = votesCount
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, expired, multiple, voted, options, emojis
        case expiresAt = "expires_at"
        case votesCount = "votes_count"
        case votersCount = "voters_count"
        case ownVotes = "own_votes"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        _expired = try c.decode(LenientBool.self, forKey: .expired)
        _multiple = try c.decode(LenientBool.self, forKey: .multiple)
        _votesCount = try c.decode(LenientInt.self, forKey: .votesCount)
        votersCount = try c.decodeIfPresent(Int.self, forKey: .votersCount)
        _voted = try c.decode(LenientBool.self, forKey: .voted)
        ownVotes = try c.decodeIfPresent([Int].self, forKey: .ownVotes) ?? []
        options = (try? c.decode(LossyArray<Option>.self, forKey: .options))?.elements ?? []
        emojis = (try? c.decode(LossyArray<CustomEmoji>.self, forKey: .emojis))?.elements ?? []
    }

    public init(
        id: String, expiresAt: Date? = nil, expired: Bool = false, multiple: Bool = false,
        votesCount: Int = 0, votersCount: Int? = nil, voted: Bool = false,
        ownVotes: [Int] = [], options: [Option] = [], emojis: [CustomEmoji] = []
    ) {
        _id = .init(wrappedValue: id)
        self.expiresAt = expiresAt
        _expired = .init(wrappedValue: expired)
        _multiple = .init(wrappedValue: multiple)
        _votesCount = .init(wrappedValue: votesCount)
        self.votersCount = votersCount
        _voted = .init(wrappedValue: voted)
        self.ownVotes = ownVotes
        self.options = options
        self.emojis = emojis
    }

    /// The denominator for a percentage. Mastodon counts voters for a
    /// multiple-choice poll and votes for a single-choice one.
    public var participantCount: Int {
        if multiple, let votersCount { return votersCount }
        return votesCount
    }

    public func share(ofOptionAt index: Int) -> Double {
        guard participantCount > 0, options.indices.contains(index),
            let votes = options[index].votesCount
        else { return 0 }
        return Double(votes) / Double(participantCount)
    }

    /// Results are shown once the poll is closed or the reader has voted;
    /// before that, showing them would tell people how to vote.
    public var showsResults: Bool { expired || voted }
}
