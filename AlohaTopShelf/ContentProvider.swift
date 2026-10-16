// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation
import TVServices

/// The Apple TV's Top Shelf for Aloha Social: Continue watching, then the
/// newest videos from the people you follow (docs/09 §5).
///
/// The TV app writes what it last loaded into the app group, and this reads
/// it — the system asks for content every time the icon reaches the top row,
/// far more often than the app runs. Only a missing or stale snapshot sends
/// this to the network, with the account the app shares.
final class ContentProvider: TVTopShelfContentProvider {
    /// Older than this, and the shelf asks the server instead — Continue
    /// watching changes on other devices too.
    private static let freshness: TimeInterval = 30 * 60

    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        guard let account = TVAccountStore().load() else { return nil }
        let store = TopShelfSnapshotStore.shared
        var snapshot = store?.read().flatMap { $0.accountID == account.id ? $0 : nil }

        if snapshot.map({ Date().timeIntervalSince($0.createdAt) > Self.freshness }) ?? true,
            let fetched = await Self.fetch(account)
        {
            _ = try? store?.write(fetched)
            snapshot = fetched
        }
        guard let snapshot, !snapshot.sections.isEmpty else { return nil }
        return Self.content(for: snapshot)
    }

    /// What the TV app's Video tab loads, fetched the same way. A failure is
    /// nil, and the stale snapshot is shown rather than nothing.
    private static func fetch(_ account: TVAccount) async -> TopShelfSnapshot? {
        let client = APIClient(
            accountID: account.id, apiBase: account.apiBase, accessToken: account.token)
        let resumed =
            try? await client.decode(
                LossyArray<ContinueWatchingItem>.self, from: Endpoint.video.continueWatching())
        let following =
            try? await client.decode(
                LossyArray<Status>.self,
                from: Endpoint.timelines.timeline(
                    .home, filters: TimelineFilters(onlyVideo: true), limit: 20))
        guard resumed != nil || following != nil else { return nil }
        return TopShelfSnapshot.make(
            accountID: account.id, continueWatching: resumed?.elements ?? [],
            following: following?.elements ?? [])
    }

    private static func content(for snapshot: TopShelfSnapshot) -> TVTopShelfSectionedContent {
        let sections = snapshot.sections.map { section in
            let collection = TVTopShelfItemCollection(items: section.items.map(item(for:)))
            collection.title = title(for: section.kind)
            return collection
        }
        return TVTopShelfSectionedContent(sections: sections)
    }

    private static func item(for entry: TopShelfSnapshot.Item) -> TVTopShelfSectionedItem {
        let item = TVTopShelfSectionedItem(identifier: entry.id)
        item.title = entry.title
        // Video stills are 16:9, which is what `hdtv` draws.
        item.imageShape = .hdtv
        if let imageURL = entry.imageURL {
            item.setImageURL(imageURL, for: [.screenScale1x, .screenScale2x])
        }
        if let progress = entry.progress {
            item.playbackProgress = progress
        }
        // Select opens the video; Play on the remote starts it. The app has no
        // separate detail screen, so both go to the player — Play from where it
        // was left, select from the same place, so neither loses the position.
        if let url = TopShelfLink.play(statusID: entry.id, position: entry.position).url {
            item.playAction = TVTopShelfAction(url: url)
        }
        if let url = TopShelfLink.show(statusID: entry.id, position: entry.position).url {
            item.displayAction = TVTopShelfAction(url: url)
        }
        return item
    }

    private static func title(for kind: TopShelfSnapshot.SectionKind) -> String {
        switch kind {
        case .continueWatching:
            String(localized: "Continue watching", comment: "Top Shelf section")
        case .following:
            String(localized: "Following", comment: "Top Shelf section")
        }
    }
}
