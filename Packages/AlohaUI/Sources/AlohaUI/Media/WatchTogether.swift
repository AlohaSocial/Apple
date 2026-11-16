// SPDX-License-Identifier: MIT

import AVFoundation
import AlohaModels
// Only to read a session's state as it changes: GroupSession publishes it
// with `@Published` and nothing else (docs/12 §1 otherwise keeps Combine out).
import Combine
import CoreTransferable
import Foundation
import GroupActivities
import OSLog
import Observation

/// One video, as everybody on the call can play it.
///
/// The people on a FaceTime call are on different servers, under different
/// accounts, so a post id means nothing to anybody but the one who shared
/// it. What travels is the media file's own public address, which plays
/// anywhere, and the post's address for whoever wants to open it.
nonisolated struct SharedVideo: Codable, Hashable, Sendable, Identifiable {
    let mediaURL: URL
    let postURL: URL?
    let previewURL: URL?
    let author: String
    let text: String

    var id: URL { mediaURL }

    /// The first video in a post, or nil when it has none a stranger could
    /// play: a file only the account's own token opens is no use on a call.
    init?(_ status: Status, attachmentID: String? = nil) {
        let target = status.displayed
        let videos = target.mediaAttachments.filter(\.isVideo)
        guard
            let attachment = attachmentID.flatMap({ id in videos.first { $0.id == id } })
                ?? videos.first,
            let url = attachment.url ?? attachment.remoteURL
        else { return nil }
        self.mediaURL = url
        self.postURL = target.url ?? URL(string: target.uri)
        self.previewURL = attachment.previewURL
        self.author = target.account.bestDisplayName
        self.text = IntentText.plain(target.content)
    }

    /// A video known only as an attachment — the media viewer's, which is
    /// handed the attachments and not their post.
    init?(_ attachment: MediaAttachment) {
        guard attachment.isVideo, let url = attachment.url ?? attachment.remoteURL else {
            return nil
        }
        self.mediaURL = url
        self.postURL = nil
        self.previewURL = attachment.previewURL
        self.author = ""
        self.text = attachment.description ?? ""
    }
}

/// Watching a video post, or a run of shorts, together on a FaceTime call
/// (SharePlay). The playback itself is kept in step by
/// `AVPlayerPlaybackCoordinator`; which video of the run is on is kept in
/// step by a message each time somebody moves on.
nonisolated struct WatchTogetherActivity: GroupActivity, Transferable {
    static let activityIdentifier = "social.aloha.app.watch-together"

    enum Kind: String, Codable, Sendable {
        case video, shorts
    }

    let kind: Kind
    let videos: [SharedVideo]
    let startIndex: Int

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.type = .watchTogether
        metadata.title =
            kind == .shorts
            ? String(localized: "Shorts together", comment: "SharePlay activity title")
            : String(localized: "Watch together", comment: "SharePlay activity title")
        if videos.indices.contains(startIndex) {
            let first = videos[startIndex]
            if !first.author.isEmpty { metadata.subtitle = first.author }
            metadata.fallbackURL = first.postURL
        }
        return metadata
    }

    /// Offered in the share sheet as "SharePlay" when there is no call yet,
    /// so the person can start one with the people they pick.
    static var transferRepresentation: some TransferRepresentation {
        GroupActivityTransferRepresentation { $0 }
    }
}

/// Which video of the run everybody is on, sent when somebody moves.
private nonisolated struct WatchTogetherPosition: Codable, Sendable {
    let index: Int
}

/// The one SharePlay session the app takes part in, and the switch that
/// says whether it can take part at all.
///
/// SharePlay needs the Group Activities entitlement, which needs the
/// capability on the App ID: only a team that has enabled it can sign a
/// build that carries it. `ALOHA_SHAREPLAY` (`Supporting/Aloha.xcconfig`)
/// picks the entitlements and writes `AlohaSharePlayEnabled` into the
/// Info.plist, so a build without the entitlement never shows a "Watch
/// together" button that would do nothing.
@MainActor
@Observable
final class WatchTogether {
    static let shared = WatchTogether()

    private let logger = Logger(subsystem: "social.aloha.app", category: "shareplay")

    /// Whether this build is entitled to SharePlay.
    static var isEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "AlohaSharePlayEnabled") as? String) == "YES"
    }

    /// The session being watched, while there is one.
    private(set) var session: GroupSession<WatchTogetherActivity>?
    private(set) var videos: [SharedVideo] = []
    private(set) var kind: WatchTogetherActivity.Kind = .video
    /// Which of `videos` is on, the same for everybody.
    private(set) var index = 0
    /// What the shell presents the shared player from.
    var isPresenting = false

    @ObservationIgnored private var messenger: GroupSessionMessenger?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var isListening = false

    private init() {}

    var current: SharedVideo? { videos[safe: index] }

    /// Waits for sessions for as long as the app runs: one this device
    /// starts, and one somebody else on the call starts and this person
    /// joins from the system's banner.
    func listen() async {
        guard Self.isEnabled, !isListening else { return }
        isListening = true
        defer { isListening = false }
        for await session in WatchTogetherActivity.sessions() {
            join(session)
        }
    }

    /// "Watch together". On a call, the system starts it at once — or asks
    /// whether to share it or watch alone, as it does for every app. With
    /// no call, `prepareForActivation` says so and the caller offers the
    /// share sheet instead (`WatchTogetherButton`).
    func start(_ activity: WatchTogetherActivity) async {
        switch await activity.prepareForActivation() {
        case .activationPreferred:
            do {
                _ = try await activity.activate()
            } catch {
                logger.error(
                    "SharePlay did not start: \(error.localizedDescription, privacy: .public)")
            }
        case .activationDisabled, .cancelled:
            break
        @unknown default:
            break
        }
    }

    /// Moves everybody to another video of the run.
    func move(to newIndex: Int) {
        guard videos.indices.contains(newIndex), newIndex != index else { return }
        index = newIndex
        guard let messenger else { return }
        Task {
            try? await messenger.send(WatchTogetherPosition(index: newIndex))
        }
    }

    /// Leaves the session; the others carry on without this person.
    func leave() {
        session?.leave()
        reset()
    }

    private func join(_ newSession: GroupSession<WatchTogetherActivity>) {
        session?.leave()
        reset()
        session = newSession
        videos = newSession.activity.videos
        kind = newSession.activity.kind
        index = min(max(newSession.activity.startIndex, 0), max(videos.count - 1, 0))
        let messenger = GroupSessionMessenger(session: newSession)
        self.messenger = messenger
        newSession.join()
        isPresenting = true

        tasks.append(
            Task { [weak self] in
                for await (message, _) in messenger.messages(of: WatchTogetherPosition.self) {
                    guard let self, self.videos.indices.contains(message.index) else { continue }
                    self.index = message.index
                }
            })
        tasks.append(
            Task { [weak self] in
                for await state in newSession.$state.values {
                    if case .invalidated = state {
                        self?.reset()
                        return
                    }
                }
            })
    }

    private func reset() {
        for task in tasks { task.cancel() }
        tasks = []
        messenger = nil
        session = nil
        videos = []
        index = 0
        isPresenting = false
    }
}
