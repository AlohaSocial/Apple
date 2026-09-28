// SPDX-License-Identifier: MIT

import Foundation

#if os(iOS)
    import ActivityKit
#endif

/// Shared between the app and the widget extension that draws the Live Activity.
///
/// Live Activities are for work in progress, not for content — an upload and a
/// scheduled post's countdown, and nothing else (docs/09 §9).
public struct UploadActivityAttributes: Sendable, Hashable, Codable {
    public var fileCount: Int

    public struct ContentState: Sendable, Hashable, Codable {
        public var completed: Int
        public var total: Int
        public var fraction: Double
        public var currentFilename: String
        public var isFinished: Bool
        public var failed: Bool

        public init(
            completed: Int, total: Int, fraction: Double,
            currentFilename: String, isFinished: Bool, failed: Bool
        ) {
            self.completed = completed
            self.total = total
            self.fraction = fraction
            self.currentFilename = currentFilename
            self.isFinished = isFinished
            self.failed = failed
        }
    }

    public init(fileCount: Int) {
        self.fileCount = fileCount
    }
}

// ActivityKit exists on macOS as a module but `ActivityAttributes` does not,
// so the conformance is iOS-only rather than canImport-gated.
#if os(iOS)
    extension UploadActivityAttributes: ActivityAttributes {}
#endif

/// Starts, updates and ends the activity. Silently does nothing where Live
/// Activities are unavailable, which is every platform but iOS and iPadOS.
@MainActor
public final class UploadActivityController {
    public static let shared = UploadActivityController()

    /// Below this an upload finishes before a Live Activity would be useful.
    public static let minimumBytesToShow = 5 * 1024 * 1024

    private var isRunning = false

    private init() {}

    public static func isWorthShowing(totalBytes: Int, containsVideo: Bool) -> Bool {
        containsVideo || totalBytes >= minimumBytesToShow
    }

    public func start(fileCount: Int) {
        #if os(iOS)
            guard !isRunning, ActivityAuthorizationInfo().areActivitiesEnabled else { return }

            let state = UploadActivityAttributes.ContentState(
                completed: 0, total: fileCount, fraction: 0,
                currentFilename: "", isFinished: false, failed: false)

            isRunning =
                (try? Activity.request(
                    attributes: UploadActivityAttributes(fileCount: fileCount),
                    content: .init(state: state, staleDate: nil))) != nil
        #endif
    }

    public func update(_ progress: UploadProgress) {
        #if os(iOS)
            // The live `Activity` is looked up fresh inside the task rather
            // than held across the hop: it is not `Sendable`, so a stored one
            // cannot legally be handed to `update`, which runs off the actor.
            let completed = progress.items.filter(\.isFinished).count
            let state = UploadActivityAttributes.ContentState(
                completed: completed,
                total: progress.items.count,
                fraction: progress.overallFraction,
                currentFilename: progress.items.first { !$0.isFinished }?.filename ?? "",
                isFinished: progress.isFinished,
                failed: progress.items.contains(where: \.failed))

            Task {
                for activity in Activity<UploadActivityAttributes>.activities {
                    await activity.update(.init(state: state, staleDate: nil))
                }
            }
        #endif
    }

    /// The completion state persists briefly so the person sees it land.
    public func finish(failed: Bool) {
        #if os(iOS)
            let isRunning = self.isRunning
            self.isRunning = false
            guard isRunning else { return }

            Task {
                for activity in Activity<UploadActivityAttributes>.activities {
                    let total = activity.attributes.fileCount
                    let final = UploadActivityAttributes.ContentState(
                        completed: total, total: total, fraction: 1,
                        currentFilename: "", isFinished: true, failed: failed)
                    await activity.end(
                        .init(state: final, staleDate: nil),
                        dismissalPolicy: .after(.now.addingTimeInterval(8)))
                }
            }
        #endif
    }
}
