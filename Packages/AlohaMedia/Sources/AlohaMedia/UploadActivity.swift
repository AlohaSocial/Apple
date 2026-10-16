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
        /// Where the post is. An upload is only the first part of it: a video
        /// is then transcoded by the server, and the post is not out until it
        /// has been sent.
        public enum Phase: String, Sendable, Hashable, Codable {
            /// Bytes are going up.
            case uploading
            /// Everything is up and the server is still transcoding a file.
            case processing
            /// Everything is up and processed, waiting for the person to post.
            case ready
            /// The post is being sent.
            case posting
            /// The post is out.
            case posted
            /// Something did not make it.
            case failed
        }

        public var completed: Int
        public var total: Int
        public var fraction: Double
        public var currentFilename: String
        public var phase: Phase

        public var isFinished: Bool { phase != .uploading }
        public var failed: Bool { phase == .failed }

        public init(
            completed: Int, total: Int, fraction: Double,
            currentFilename: String, phase: Phase
        ) {
            self.completed = completed
            self.total = total
            self.fraction = fraction
            self.currentFilename = currentFilename
            self.phase = phase
        }

        /// The state a batch of uploads is in, as a pure function of it.
        ///
        /// One failed file does not end the batch: the others are still going
        /// up, and the activity says the upload failed only once nothing else
        /// is in flight.
        public static func of(_ progress: UploadProgress, processing: Int) -> ContentState {
            let items = progress.items
            let phase: Phase
            if !progress.isFinished {
                phase = .uploading
            } else if items.contains(where: \.failed) {
                phase = .failed
            } else if processing > 0 {
                phase = .processing
            } else {
                phase = .ready
            }
            return ContentState(
                completed: items.filter(\.isFinished).count,
                total: items.count,
                fraction: progress.overallFraction,
                currentFilename: items.first { !$0.isFinished }?.filename ?? "",
                phase: phase)
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

    /// How long an activity waiting for the person to post stays current. A
    /// composer left open in the background is not still "about to post"
    /// hours later.
    static let readyStaleInterval: TimeInterval = 60 * 60

    private var isRunning = false
    private var last: UploadActivityAttributes.ContentState?

    private init() {}

    public static func isWorthShowing(totalBytes: Int, containsVideo: Bool) -> Bool {
        containsVideo || totalBytes >= minimumBytesToShow
    }

    public func start(fileCount: Int) {
        #if os(iOS)
            guard !isRunning, ActivityAuthorizationInfo().areActivitiesEnabled else { return }

            let state = UploadActivityAttributes.ContentState(
                completed: 0, total: fileCount, fraction: 0, currentFilename: "",
                phase: .uploading)

            isRunning =
                (try? Activity.request(
                    attributes: UploadActivityAttributes(fileCount: fileCount),
                    content: .init(state: state, staleDate: nil))) != nil
        #endif
    }

    /// The batch changed: a file finished, failed, or finished processing.
    public func update(_ progress: UploadProgress, processing: Int = 0) {
        let state = UploadActivityAttributes.ContentState.of(progress, processing: processing)
        // Everything failed: nothing is left to post, so the activity ends.
        if state.failed, progress.items.allSatisfy(\.failed) {
            end(with: state, dismissAfter: 8)
            return
        }
        push(state)
    }

    /// The post is on its way.
    public func posting() {
        guard var state = last else { return }
        state.phase = .posting
        push(state)
    }

    /// The post is out: say so briefly, then go.
    public func posted() {
        guard var state = last else { return }
        state.phase = .posted
        state.fraction = 1
        end(with: state, dismissAfter: 8)
    }

    /// Posting failed after the uploads succeeded: back to waiting.
    public func postFailed() {
        guard var state = last, state.phase == .posting else { return }
        state.phase = .ready
        push(state)
    }

    /// The composer closed without posting; nothing is in progress any more.
    public func cancel() {
        if let state = last {
            end(with: state, dismissAfter: 0)
        } else {
            endAll()
        }
    }

    // MARK: - Private

    private func push(_ state: UploadActivityAttributes.ContentState) {
        guard isRunning else { return }
        last = state
        #if os(iOS)
            let stale: Date? =
                state.phase == .ready ? Date().addingTimeInterval(Self.readyStaleInterval) : nil
            // The live `Activity` is looked up fresh inside the task rather
            // than held across the hop: it is not `Sendable`, so a stored one
            // cannot legally be handed to `update`, which runs off the actor.
            Task {
                for activity in Activity<UploadActivityAttributes>.activities {
                    await activity.update(.init(state: state, staleDate: stale))
                }
            }
        #endif
    }

    private func end(with state: UploadActivityAttributes.ContentState, dismissAfter: TimeInterval)
    {
        let wasRunning = isRunning
        isRunning = false
        last = nil
        guard wasRunning else { return }
        #if os(iOS)
            Task {
                for activity in Activity<UploadActivityAttributes>.activities {
                    await activity.end(
                        .init(state: state, staleDate: nil),
                        dismissalPolicy: dismissAfter > 0
                            ? .after(.now.addingTimeInterval(dismissAfter)) : .immediate)
                }
            }
        #endif
    }

    private func endAll() {
        let wasRunning = isRunning
        isRunning = false
        last = nil
        guard wasRunning else { return }
        #if os(iOS)
            Task {
                for activity in Activity<UploadActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        #endif
    }
}
