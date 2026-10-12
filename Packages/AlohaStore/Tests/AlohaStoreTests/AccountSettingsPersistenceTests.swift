// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import SwiftData
import Testing

@testable import AlohaStore

@Suite("Account settings persistence")
struct AccountSettingsPersistenceTests {
    @Test("Chosen feeds survive opening a fresh container on the saved store")
    func feedsSurviveReopening() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = directory.appending(path: "accounts.sqlite")
        let configuration = ModelConfiguration(schema: StoreContainer.schema, url: location)
        let container = try ModelContainer(for: StoreContainer.schema, configurations: configuration)
        let writer = AccountStore(modelContainer: container)
        let base = try #require(URL(string: "https://example.test"))
        let account = try await writer.addAccount(
            instanceHost: "example.test", apiBase: base,
            account: Account(id: "alice", username: "alice", acct: "alice"),
            capabilities: .minimal(apiBase: base))
        var settings = account.settings
        settings.enabledModes = [.photos, .audio]
        try await writer.updateSettings(settings, for: account.id)

        let reopened = try ModelContainer(for: StoreContainer.schema, configurations: configuration)
        let reader = AccountStore(modelContainer: reopened)
        let restored = try #require(await reader.account(id: account.id))
        #expect(restored.settings.enabledModes == [.photos, .audio])
    }
}
