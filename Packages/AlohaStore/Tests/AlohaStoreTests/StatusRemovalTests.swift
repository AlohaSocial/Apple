// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Synchronization
import Testing

@testable import AlohaStore

/// What the store removes, it says it removed: lists on screen only heard
/// about updates, so a deleted or blocked post stayed until a refresh.
@Suite("Timeline store removals")
struct TimelineStoreRemovalTests {
    /// Every removal posted for one account while `body` runs. Posted
    /// synchronously on the store's own executor, so all of them have
    /// arrived once its call returns.
    private func removals(
        for accountID: UUID, during body: () async throws -> Void
    ) async rethrows -> [TimelineStatusRemoval] {
        let heard = Heard()
        let token = NotificationCenter.default.addObserver(
            forName: TimelineStatusRemoval.notification, object: nil, queue: nil
        ) { notification in
            guard let removal = notification.object as? TimelineStatusRemoval,
                removal.accountID == accountID
            else { return }
            heard.removals.withLock { $0.append(removal) }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        try await body()
        return heard.removals.withLock { $0 }
    }

    private final class Heard: Sendable {
        let removals = Mutex<[TimelineStatusRemoval]>([])
    }

    private func status(_ id: String, by author: String, boosting: Status? = nil) -> Status {
        Status(
            id: id, content: "<p>Post \(id)</p>",
            account: Account(id: author, username: author, acct: author),
            reblog: boosting.map(Box.init))
    }

    @Test("Deleting a post says which post went")
    func deletionIsAnnounced() async throws {
        let timelines = TimelineStore(modelContainer: StoreContainer.make(inMemory: true))
        let accountID = UUID()
        _ = try await timelines.apply(
            page: [status("1", by: "a")], accountID: accountID, timelineKey: "home:home",
            direction: .cold, pageWasFull: false)

        let heard = try await removals(for: accountID) {
            try await timelines.deleteStatus(accountID: accountID, serverID: "1")
        }
        #expect(heard == [TimelineStatusRemoval(accountID: accountID, statusIDs: ["1"])])
    }

    @Test("A block says whose posts went, and which of them the cache held")
    func blockIsAnnounced() async throws {
        let timelines = TimelineStore(modelContainer: StoreContainer.make(inMemory: true))
        let accountID = UUID()
        let page = [
            status("3", by: "b"),
            status("2", by: "a", boosting: status("x", by: "b")),
            status("1", by: "a"),
        ]
        _ = try await timelines.apply(
            page: page, accountID: accountID, timelineKey: "home:home",
            direction: .cold, pageWasFull: false)

        let heard = try await removals(for: accountID) {
            try await timelines.removeEverything(fromAccount: "b", accountID: accountID)
        }
        #expect(heard.count == 1)
        #expect(heard.first?.authorID == "b")
        #expect(heard.first?.statusIDs == ["3", "2"])
    }
}
