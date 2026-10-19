// SPDX-License-Identifier: MIT

import Foundation

/// Aloha Social's switch that adds a reply to a post carrying a file from
/// the reader's Nextcloud as a comment on that file too
/// (`/api/v1/social/files_comments`, `FileCommentsService`).
public struct FilesCommentsSetting: Codable, Sendable, Hashable {
    @LenientBool public var enabled: Bool

    public init(enabled: Bool) { _enabled = .init(wrappedValue: enabled) }

    enum CodingKeys: String, CodingKey { case enabled }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _enabled = (try? c.decode(LenientBool.self, forKey: .enabled)) ?? .init(wrappedValue: false)
    }
}
