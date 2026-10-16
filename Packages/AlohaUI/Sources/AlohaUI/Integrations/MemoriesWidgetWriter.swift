// SPDX-License-Identifier: MIT

import AlohaHTML
import AlohaModels
import AlohaNetwork
import AlohaStore
import CoreGraphics
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// Writes the Memories widget's day into the app group.
///
/// Memories are a server query rather than a cached timeline, and a widget
/// never downloads (docs/09 §8), so the app answers "on this day" once a day
/// per account — when it becomes active, and on background refresh — and
/// the widget reads only what is written here.
@MainActor
public enum MemoriesWidgetWriter {
    /// How many the largest widget shows; there is no reason to keep more.
    static let limit = 4
    /// Small enough for a widget's memory budget, sharp at the largest tile.
    nonisolated static let thumbnailPixels: CGFloat = 360

    private static let logger = Logger(subsystem: "social.aloha.app", category: "widgets")

    /// Writes today's snapshot for the session's account unless it is
    /// already there.
    public static func refreshIfStale(
        _ session: AccountSession, store: MemoriesSnapshotStore? = .shared, now: Date = Date()
    ) async {
        guard let store, !session.needsReauthentication else { return }
        let day = MemoriesSnapshot.dayKey(for: now)
        guard !store.isCurrent(accountID: session.id, day: day) else { return }

        // Only Aloha Social has memories; elsewhere the widget says there is
        // nothing, rather than showing another account's day.
        var statuses: [Status] = []
        if session.capabilities.isNextcloudSocial {
            do {
                statuses = try await session.client.decode(
                    LossyArray<Status>.self, from: Endpoint.memories.onThisDay
                ).elements
            } catch {
                // Tried again on the next activation; yesterday's snapshot is
                // already hidden by its date.
                logger.notice(
                    "memories not fetched: \(String(describing: error), privacy: .public)")
                return
            }
        }

        let memories = memories(from: statuses)
        var images: [String: Data] = [:]
        for status in statuses.map(\.displayed)
        where memories.contains(where: { $0.id == status.id }) {
            if let url = pictureURL(of: status), let data = await thumbnail(from: url) {
                images[status.id] = data
            }
        }

        do {
            try store.write(
                MemoriesSnapshot(accountID: session.id, day: day, memories: memories),
                images: images)
            WidgetReloader.reload(kind: MemoriesSnapshotStore.widgetKind)
        } catch {
            logger.error(
                "memories snapshot not written: \(String(describing: error), privacy: .public)")
        }
    }

    /// The newest few, as the widget shows them: the content warning in
    /// place of a post that has one, as the timeline would before it opens.
    static func memories(from statuses: [Status]) -> [MemoriesSnapshot.Memory] {
        let parser = StatusHTMLParser()
        return statuses.map(\.displayed)
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { status in
                MemoriesSnapshot.Memory(
                    id: status.id,
                    author: status.account.bestDisplayName,
                    text: status.spoilerText.isEmpty
                        ? parser.plainText(status.content) : status.spoilerText,
                    createdAt: status.createdAt,
                    imageFile: nil)
            }
    }

    /// The first picture, unless the post is behind a warning: a Home Screen
    /// is a more public place than the app.
    static func pictureURL(of status: Status) -> URL? {
        guard !status.sensitive, status.spoilerText.isEmpty else { return nil }
        let image = status.mediaAttachments.first { $0.type == .image }
        return image?.previewURL ?? image?.url
    }

    private static func thumbnail(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let fetched = try? await URLSession.shared.data(for: request),
            let http = fetched.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        return jpeg(from: fetched.0)
    }

    /// Shrunk once here, so the widget decodes a few kilobytes.
    nonisolated static func jpeg(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: thumbnailPixels,
                ] as CFDictionary)
        else { return nil }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
