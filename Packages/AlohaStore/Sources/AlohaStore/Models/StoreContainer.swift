// SPDX-License-Identifier: MIT

import AlohaNetwork
import Foundation
import OSLog
import SwiftData
import Synchronization

/// The store, in the app group so the share extension and the widgets read
/// what the app wrote.
///
/// **It is not a disposable cache.** Accounts, drafts and the send queue live
/// in it next to the cached timelines, so a store that is deleted loses posts
/// somebody has not sent yet. Three rules follow:
///
/// - Only the app may create, move or rebuild the file. An extension that
///   finds no store, or one it cannot read, gets an empty in-memory container
///   for that call and leaves the file alone — the Lock Screen widget runs
///   before the first unlock, when the file is unreadable but very much there.
/// - Even the app never deletes a store: one it cannot open is moved aside to
///   `AlohaSocial.unopenable.store`, so it can still be recovered.
/// - Each process opens the store once. A widget timeline used to stand up
///   three or four containers on the same file.
public enum StoreContainer {
    public static let appGroupIdentifier = "group.social.aloha.app"

    public static let schema = Schema(versionedSchema: AlohaSchemaV1.self)

    /// Who is opening the store, which decides what it may do to the file.
    public enum Role: Hashable, Sendable {
        /// The app: creates, adopts and, as a last resort, rebuilds it.
        case app
        /// An extension or intent that writes — the share extension's drafts,
        /// the widget's favourite. Never creates or rebuilds.
        case writer
        /// A process that only shows what the app wrote. Opened read-only.
        case reader
    }

    /// Why a container is empty rather than the store.
    enum Fallback: Equatable {
        case noStoreYet
        case unreadable
        case unopenable
    }

    enum Opened {
        case store(ModelContainer)
        case fallback(ModelContainer, Fallback)

        var container: ModelContainer {
            switch self {
            case .store(let container), .fallback(let container, _): container
            }
        }

        var fallback: Fallback? {
            if case .fallback(_, let reason) = self { return reason }
            return nil
        }
    }

    private static let logger = Logger(subsystem: "social.aloha.app", category: "store")
    private static let opened = Mutex<[Role: ModelContainer]>([:])

    static var processIsApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// This process's store, opened once and shared by every caller.
    ///
    /// In the app it is the store everything is written to; in an extension a
    /// writer that never creates or rebuilds the file. `inMemory` builds a
    /// fresh, unshared container — for tests and the mock mode.
    public static func make(inMemory: Bool = false) -> ModelContainer {
        if inMemory { return memoryContainer() }
        return shared(role: processIsApp ? .app : .writer)
    }

    /// The store for reading only. In the app this is the same container
    /// `make()` returns; elsewhere it is opened read-only, so a widget or the
    /// notification service cannot write to — or migrate — the app's store.
    public static func reader() -> ModelContainer {
        shared(role: processIsApp ? .app : .reader)
    }

    private static func shared(role: Role) -> ModelContainer {
        opened.withLock { cache in
            if let container = cache[role] { return container }
            let result = open(at: storeURL(), role: role)
            // A fallback is not kept: the next call, after the first unlock or
            // once the app has made the store, should find the real one.
            if case .store(let container) = result { cache[role] = container }
            return result.container
        }
    }

    /// Opens the store at `url` as `role` may.
    static func open(at url: URL, role: Role) -> Opened {
        let manager = FileManager.default
        let exists = manager.fileExists(atPath: url.path)

        if role != .app, !exists {
            logger.notice("no store yet; this process does not create one")
            return .fallback(memoryContainer(), .noStoreYet)
        }
        if exists, !isReadable(url) {
            // Data protection before the first unlock, most likely. The file
            // is fine; it just cannot be read yet.
            logger.notice("the store cannot be read yet; leaving it as it is")
            return .fallback(memoryContainer(), .unreadable)
        }
        if role == .app {
            try? manager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        if let container = tryOpen(at: url, role: role) { return .store(container) }

        guard role == .app else {
            return .fallback(memoryContainer(), .unopenable)
        }
        // Readable and still unopenable: a model this build cannot read, or a
        // damaged file. The app moves it aside — not away — and starts again.
        logger.fault("the store cannot be opened; moving it aside and starting a new one")
        moveAside(url)
        if let container = tryOpen(at: url, role: role) { return .store(container) }
        logger.fault("a new store failed too; this session runs in memory")
        return .fallback(memoryContainer(), .unopenable)
    }

    /// The migration plan first, then SwiftData's own lightweight inference: a
    /// store written by a build from before the plan existed carries a model
    /// the plan does not name, and inference is what has always opened those.
    private static func tryOpen(at url: URL, role: Role) -> ModelContainer? {
        let configuration = ModelConfiguration(
            schema: schema, url: url, allowsSave: role != .reader, cloudKitDatabase: .none)
        do {
            return try ModelContainer(
                for: schema, migrationPlan: AlohaMigrationPlan.self,
                configurations: [configuration])
        } catch {
            logger.error(
                "store did not open with the migration plan: \(String(describing: error), privacy: .public)"
            )
        }
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            logger.error("store did not open: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private static func memoryContainer() -> ModelContainer {
        do {
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        } catch {
            // A memory-only container for a schema that already compiled can
            // only fail because the schema itself is wrong, which is
            // programmer error rather than a runtime condition — the one trap
            // docs/12 §1 sanctions, and a clearer crash than a force try.
            preconditionFailure("in-memory model container failed: \(error)")
        }
    }

    private static func storeURL() -> URL {
        if AppGroup.isEnabled,
            let groupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        {
            let shared = groupURL.appending(path: "AlohaSocial.store")
            adoptLocalStoreIfNeeded(into: shared)
            return shared
        }
        // No app group entitlement (an unsigned local build, say): fall back to
        // the app's own container rather than refusing to launch.
        logger.notice("app group container unavailable; using the local container")
        return localConfiguration.url
    }

    /// The app's own container, said explicitly: SwiftData's default
    /// `groupContainer: .automatic` moves into the first app group the binary
    /// is entitled to, which is not "local" at all.
    private static var localConfiguration: ModelConfiguration {
        ModelConfiguration(schema: schema, groupContainer: .none, cloudKitDatabase: .none)
    }

    /// Whether the file's bytes can be read at all — false before the first
    /// unlock, when data protection keeps the file closed.
    static func isReadable(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 16)) != nil
    }

    /// Copies the store a build without the app group kept in the app's own
    /// container into the group, the first time the group is there, and
    /// removes the original only once every file has arrived.
    ///
    /// Accounts and drafts live in it: a fresh group store would greet everyone
    /// who updates with the sign-in screen. Only the app does this — an
    /// extension's own container never held anything worth moving.
    static func adoptLocalStoreIfNeeded(
        into shared: URL,
        from local: URL = localConfiguration.url,
        isApp: Bool = processIsApp
    ) {
        let manager = FileManager.default
        guard isApp, local != shared,
            !manager.fileExists(atPath: shared.path),
            manager.fileExists(atPath: local.path)
        else { return }
        // The write-ahead log and its index go with the store, or the last
        // writes before the update are lost on the way.
        let suffixes = ["", "-wal", "-shm"].filter {
            manager.fileExists(atPath: local.path + $0)
        }
        var copied: [URL] = []
        do {
            try manager.createDirectory(
                at: shared.deletingLastPathComponent(), withIntermediateDirectories: true)
            // The log first and the store last: a store file in the group is
            // what says the adoption happened, so it has to be the final step.
            for suffix in suffixes.reversed() {
                let target = URL(fileURLWithPath: shared.path + suffix)
                try manager.copyItem(at: URL(fileURLWithPath: local.path + suffix), to: target)
                copied.append(target)
            }
        } catch {
            // Nothing is lost: the original is still where it was, and the
            // next launch tries again.
            logger.error(
                "could not copy the local store: \(String(describing: error), privacy: .public)")
            for target in copied { try? manager.removeItem(at: target) }
            return
        }
        for suffix in suffixes {
            try? manager.removeItem(at: URL(fileURLWithPath: local.path + suffix))
        }
        logger.notice("moved the local store into the app group")
    }

    /// Puts an unopenable store where a new one will not overwrite it. One
    /// generation is kept; the previous one is the one replaced.
    static func moveAside(_ url: URL) {
        let manager = FileManager.default
        let aside = url.deletingLastPathComponent()
            .appending(path: "AlohaSocial.unopenable.store")
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            let target = URL(fileURLWithPath: aside.path + suffix)
            try? manager.removeItem(at: target)
            guard manager.fileExists(atPath: source.path) else { continue }
            if (try? manager.moveItem(at: source, to: target)) == nil {
                // A store left in place would never open again; one that
                // cannot even be moved is not one anything could recover.
                try? manager.removeItem(at: source)
            }
        }
    }
}

/// Retention, from docs/04 §4. Sweeping is budgeted so it cannot stall a launch.
public enum CachePolicy {
    public static let homeTimelineLimit = 500
    public static let otherTimelineLimit = 200
    public static let notificationLimit = 500
    /// How long a timeline that ages keeps its rows after its last new post.
    public static let otherTimelineLifetime: TimeInterval = 7 * 86_400
    /// How many timelines that age each account keeps, newest first.
    public static let otherTimelineCount = 30
    public static let orphanStatusLifetime: TimeInterval = 7 * 86_400
    public static let relationshipLifetime: TimeInterval = 86_400
    public static let watchPositionLifetime: TimeInterval = 30 * 86_400
    public static let maximumDeletionsPerPass = 2_000

    public static func limit(forTimelineKey key: String) -> Int {
        key == "home:home" ? homeTimelineLimit : otherTimelineLimit
    }

    /// Whether a timeline's cache is dropped once it goes unused.
    ///
    /// Each mode's view of the home timeline is kept: there are six of them,
    /// they are what the app opens on, and the widgets read `home:home`.
    /// Everything else — a profile, a tag, a list, local and federated —
    /// ages, because the ones keyed by an id are made for every profile and
    /// tag somebody opens and would otherwise only ever grow. A key is the
    /// mode, a colon and the source; a source may contain colons of its own.
    public static func ages(timelineKey key: String) -> Bool {
        key.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).last != "home"
    }
}
