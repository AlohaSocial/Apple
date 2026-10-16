// SPDX-License-Identifier: MIT

import AlohaNetwork
import Foundation
import OSLog
import SwiftData

/// The one model container, in the app group so the share extension and the
/// widgets read what the app wrote.
public enum StoreContainer {
    public static let appGroupIdentifier = "group.social.aloha.app"

    public static let schema = Schema([
        AccountRecord.self,
        StatusRecord.self,
        TimelineEntry.self,
        NotificationRecord.self,
        DraftRecord.self,
        MarkerRecord.self,
        WatchPositionRecord.self,
        FilterRecord.self,
        RelationshipRecord.self,
    ])

    private static let logger = Logger(subsystem: "social.aloha.app", category: "store")

    /// Builds the container, and rebuilds it from scratch if that fails.
    ///
    /// **The cache is disposable** (docs/04 §5): a store this build cannot open
    /// is deleted and recreated rather than crashing the app. Accounts, drafts
    /// and settings live behind the Keychain and are re-derived on next sign-in,
    /// which is why this is survivable — and it replaces the seed project's
    /// `fatalError`, which would have made a schema change a dead app.
    public static func make(inMemory: Bool = false) -> ModelContainer {
        let configuration = makeConfiguration(inMemory: inMemory)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            logger.error(
                "model container failed to open: \(String(describing: error), privacy: .public)")
            destroyStore(at: configuration.url)

            do {
                return try ModelContainer(
                    for: schema, configurations: [makeConfiguration(inMemory: inMemory)])
            } catch {
                logger.fault("rebuilt container also failed; falling back to memory")
                // An in-memory store means the app launches and works for this
                // session with no cache, which is far better than not launching.
                do {
                    return try ModelContainer(
                        for: schema,
                        configurations: [
                            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                        ]
                    )
                } catch {
                    // A memory-only container for a schema that already
                    // compiled can only fail because the schema itself is
                    // wrong, which is programmer error rather than a runtime
                    // condition — the one trap docs/12 §1 sanctions, and a
                    // clearer crash than a force try.
                    preconditionFailure("in-memory model container failed: \(error)")
                }
            }
        }
    }

    private static func makeConfiguration(inMemory: Bool) -> ModelConfiguration {
        if inMemory {
            return ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }
        if AppGroup.isEnabled,
            let groupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        {
            let shared = groupURL.appending(path: "AlohaSocial.store")
            adoptLocalStoreIfNeeded(into: shared)
            return ModelConfiguration(schema: schema, url: shared, cloudKitDatabase: .none)
        }
        // No app group entitlement (an unsigned local build, say): fall back to
        // the app's own container rather than refusing to launch.
        logger.notice("app group container unavailable; using the local container")
        return localConfiguration
    }

    /// The app's own container, said explicitly: SwiftData's default
    /// `groupContainer: .automatic` moves into the first app group the binary
    /// is entitled to, which is not "local" at all.
    private static var localConfiguration: ModelConfiguration {
        ModelConfiguration(schema: schema, groupContainer: .none, cloudKitDatabase: .none)
    }

    /// Moves the store a build without the app group kept in the app's own
    /// container into the group, the first time the group is there.
    ///
    /// The cache is disposable, but accounts and drafts live in it too: a
    /// fresh group store would greet everyone who updates with the sign-in
    /// screen. Only the app does this — an extension's own container never
    /// held anything worth moving.
    static func adoptLocalStoreIfNeeded(
        into shared: URL,
        from local: URL = localConfiguration.url,
        isApp: Bool = Bundle.main.bundleURL.pathExtension == "app"
    ) {
        let manager = FileManager.default
        guard isApp, local != shared,
            !manager.fileExists(atPath: shared.path),
            manager.fileExists(atPath: local.path)
        else { return }
        do {
            try manager.createDirectory(
                at: shared.deletingLastPathComponent(), withIntermediateDirectories: true)
            // The write-ahead log and its index go with the store, or the
            // last writes before the update are lost on the way.
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: local.path + suffix)
                guard manager.fileExists(atPath: source.path) else { continue }
                try manager.moveItem(at: source, to: URL(fileURLWithPath: shared.path + suffix))
            }
            logger.notice("moved the local store into the app group")
        } catch {
            // Half a store is worse than none: whatever arrived is removed and
            // the group starts empty, which the rebuild path already handles.
            logger.error(
                "could not move the local store: \(String(describing: error), privacy: .public)")
            destroyStore(at: shared)
        }
    }

    private static func destroyStore(at url: URL) {
        let manager = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            let target = URL(fileURLWithPath: url.path + suffix)
            try? manager.removeItem(at: target)
        }
    }
}

/// Retention, from docs/04 §4. Sweeping is budgeted so it cannot stall a launch.
public enum CachePolicy {
    public static let homeTimelineLimit = 500
    public static let otherTimelineLimit = 200
    public static let notificationLimit = 500
    public static let orphanStatusLifetime: TimeInterval = 7 * 86_400
    public static let relationshipLifetime: TimeInterval = 86_400
    public static let watchPositionLifetime: TimeInterval = 30 * 86_400
    public static let maximumDeletionsPerPass = 2_000

    public static func limit(forTimelineKey key: String) -> Int {
        key == "home:home" ? homeTimelineLimit : otherTimelineLimit
    }
}
