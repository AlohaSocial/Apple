// SPDX-License-Identifier: MIT

import Foundation

/// Continuous backup of the account to its own Nextcloud Files
/// (`GET/PATCH /api/v1/social/backup`, `POST /api/v1/social/backup/run`).
///
/// The server does the work: on schedule it writes an export of the account
/// into `folder` and keeps the newest `keep` of them. The app only shows the
/// state and changes the two things a person chooses — whether it runs, and
/// how often.
public struct SocialBackup: Codable, Sendable, Hashable {
    public enum Frequency: String, Codable, Sendable, Hashable, CaseIterable {
        case daily, weekly
    }

    public var enabled: Bool
    public var frequency: Frequency
    /// Relative to the person's own Files.
    public var folder: String
    /// How many backups the server keeps before removing the oldest.
    public var keep: Int
    public var lastBackupAt: Date?
    /// Why the last backup failed, in the server's words; nil after one
    /// that worked.
    public var lastError: String?
    public var nextBackupAt: Date?
    /// A backup is being written now.
    public var running: Bool

    public init(
        enabled: Bool = false, frequency: Frequency = .weekly,
        folder: String = "Aloha Social Backup", keep: Int = 4, lastBackupAt: Date? = nil,
        lastError: String? = nil, nextBackupAt: Date? = nil, running: Bool = false
    ) {
        self.enabled = enabled
        self.frequency = frequency
        self.folder = folder
        self.keep = keep
        self.lastBackupAt = lastBackupAt
        self.lastError = lastError
        self.nextBackupAt = nextBackupAt
        self.running = running
    }

    /// Field by field, each with the server's own default, so one value this
    /// build cannot read — a frequency added later, an empty error string —
    /// costs that value and not the screen.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? nil
        }
        let defaults = SocialBackup()
        enabled = value(LenientBool.self, .enabled)?.wrappedValue ?? defaults.enabled
        frequency = value(Frequency.self, .frequency) ?? defaults.frequency
        folder = value(String.self, .folder).flatMap { $0.isEmpty ? nil : $0 } ?? defaults.folder
        keep = value(LenientInt.self, .keep)?.wrappedValue ?? defaults.keep
        lastBackupAt = value(Date.self, .lastBackupAt)
        lastError = value(String.self, .lastError).flatMap { $0.isEmpty ? nil : $0 }
        nextBackupAt = value(Date.self, .nextBackupAt)
        running = value(LenientBool.self, .running)?.wrappedValue ?? false
    }

    enum CodingKeys: String, CodingKey {
        case enabled, frequency, folder, keep, running
        case lastBackupAt = "last_backup_at"
        case lastError = "last_error"
        case nextBackupAt = "next_backup_at"
    }
}

/// What `PATCH /api/v1/social/backup` takes: any subset of the two settings
/// a person chooses. Fields left nil are not sent, and the server keeps them.
public struct SocialBackupChange: Encodable, Sendable, Hashable {
    public var enabled: Bool?
    public var frequency: SocialBackup.Frequency?

    public init(enabled: Bool? = nil, frequency: SocialBackup.Frequency? = nil) {
        self.enabled = enabled
        self.frequency = frequency
    }
}
