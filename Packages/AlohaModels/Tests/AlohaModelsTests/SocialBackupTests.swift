// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaModels

/// The shapes `api/v1/social/backup` answers in, from the server contract.
@Suite("Backup to Nextcloud")
struct SocialBackupDecodingTests {

    private func decode(_ json: String) throws -> SocialBackup {
        try AlohaJSON.decoder.decode(SocialBackup.self, from: Data(json.utf8))
    }

    @Test("The contract's default answer decodes")
    func contractDefault() throws {
        let backup = try decode(
            """
            {"enabled": false, "frequency": "weekly", "folder": "Aloha Social Backup", "keep": 4,
             "last_backup_at": null, "last_error": null, "next_backup_at": null, "running": false}
            """)
        #expect(backup == SocialBackup())
        #expect(backup.folder == "Aloha Social Backup")
        #expect(backup.keep == 4)
    }

    @Test("A running daily backup with dates and an error decodes")
    func running() throws {
        let backup = try decode(
            """
            {"enabled": true, "frequency": "daily", "folder": "Backups/Social", "keep": 7,
             "last_backup_at": "2026-11-14T03:00:12+00:00",
             "last_error": "Not enough free space in your Nextcloud.",
             "next_backup_at": "2026-11-15T03:00:00.000Z", "running": true}
            """)
        #expect(backup.enabled)
        #expect(backup.frequency == .daily)
        #expect(backup.folder == "Backups/Social")
        #expect(backup.keep == 7)
        #expect(backup.running)
        #expect(backup.lastError == "Not enough free space in your Nextcloud.")
        let last = try #require(backup.lastBackupAt)
        #expect(last == Date(timeIntervalSince1970: 1_794_625_212))
        #expect(backup.nextBackupAt == Date(timeIntervalSince1970: 1_794_711_600))
    }

    @Test("A frequency this build does not know, or a missing field, costs only that field")
    func lenient() throws {
        let backup = try decode(#"{"enabled": 1, "frequency": "hourly", "last_error": ""}"#)
        #expect(backup.enabled)
        #expect(backup.frequency == .weekly)
        #expect(backup.folder == "Aloha Social Backup")
        #expect(backup.lastError == nil)
        #expect(backup.running == false)
    }

    @Test("A change sends only what changed")
    func change() throws {
        let onlyEnabled =
            try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(SocialBackupChange(enabled: true))) as? [String: Any]
        #expect(onlyEnabled?.count == 1)
        #expect(onlyEnabled?["enabled"] as? Bool == true)

        let onlyFrequency =
            try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(SocialBackupChange(frequency: .daily))) as? [String: Any]
        #expect(onlyFrequency?.count == 1)
        #expect(onlyFrequency?["frequency"] as? String == "daily")
    }
}
