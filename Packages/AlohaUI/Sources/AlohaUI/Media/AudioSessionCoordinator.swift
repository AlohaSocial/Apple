// SPDX-License-Identifier: MIT

import AVFoundation

/// What a claim on the speaker is for; it picks the session's mode.
nonisolated enum AudibleKind: Sendable, Hashable {
    /// The Audio mode's tracks.
    case audio
    /// A video with its sound on.
    case video
}

/// How the app's one audio session is set up.
nonisolated enum AudioSessionConfiguration: Sendable, Hashable {
    /// Nothing audible: `.playback` mixed with others, and not activated by
    /// the app. A muted video in a feed then plays alongside the person's own
    /// music instead of stopping it, and can still go to Picture in Picture,
    /// which `.ambient` would not allow.
    case silent
    /// Sound is playing: `.playback` on its own, active, so it keeps going
    /// with the screen locked and other apps pause for it.
    case audible(AudibleKind)
}

/// Where the coordinator's decisions are carried out: the system's session on
/// iOS, tvOS and visionOS, nothing on the Mac, a recorder in the tests.
protocol AudioSessionBackend: AnyObject {
    func apply(_ configuration: AudioSessionConfiguration)
    /// Hands the speaker back, telling whichever app was interrupted that it
    /// may carry on.
    func deactivate()
}

/// A hold on the speaker, returned by `claim` and given back to `release`.
nonisolated struct AudibleClaim: Hashable, Sendable {
    fileprivate let id: Int
}

/// The one place the app's audio session is configured.
///
/// It used to be set from two places that never undid anything: the Audio
/// mode and every video surface switched to `.playback` and activated it, and
/// nothing ever deactivated it. A muted video in a feed stopped the person's
/// music; turning a video's sound on stopped it for good, because the session
/// was never handed back with `notifyOthersOnDeactivation`.
///
/// Every player that makes sound now holds a claim while it does. With no
/// claims the session is mixable; the first claim makes it exclusive and
/// active; the last release deactivates it and lets the other app resume.
/// Only one owner is audible at a time: a new claim pauses whoever held the
/// speaker before, so starting a track stops a video with its sound on and
/// the other way round.
@MainActor
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator(backend: SystemAudioSession())

    private struct Holder {
        let owner: ObjectIdentifier
        let kind: AudibleKind
        let preempt: () -> Void
    }

    private let backend: any AudioSessionBackend
    private var holders: [AudibleClaim: Holder] = [:]
    private var nextID = 0
    /// What the backend was last told, so nothing is set twice.
    private(set) var configuration: AudioSessionConfiguration?

    init(backend: any AudioSessionBackend) {
        self.backend = backend
    }

    /// How many claims are held: what keeps the session active.
    var audibleCount: Int { holders.count }

    func holds(_ claim: AudibleClaim) -> Bool { holders[claim] != nil }

    /// Called before a player starts, muted or not. With nobody audible the
    /// session is made mixable first, so a silent video never interrupts
    /// anything — the system's default category would.
    func prepareForSilentPlayback() {
        guard holders.isEmpty else { return }
        apply(.silent)
    }

    /// Takes the speaker for `owner`. Anyone else holding it is preempted:
    /// their claim ends here and `onPreempt` is called so they pause.
    func claim(
        owner: ObjectIdentifier, kind: AudibleKind, onPreempt: @escaping () -> Void
    ) -> AudibleClaim {
        let rivals = holders.filter { $0.value.owner != owner }
        for claim in rivals.keys { holders[claim] = nil }

        let claim = AudibleClaim(id: nextID)
        nextID += 1
        holders[claim] = Holder(owner: owner, kind: kind, preempt: onPreempt)
        apply(.audible(kind))

        // Last, so a rival that releases from inside its callback finds its
        // claim already gone.
        for rival in rivals.values { rival.preempt() }
        return claim
    }

    /// Gives a claim back. The last one out deactivates the session.
    func release(_ claim: AudibleClaim) {
        guard holders.removeValue(forKey: claim) != nil, holders.isEmpty else { return }
        backend.deactivate()
        configuration = .silent
    }

    private func apply(_ configuration: AudioSessionConfiguration) {
        guard configuration != self.configuration else { return }
        self.configuration = configuration
        backend.apply(configuration)
    }
}

/// The system's audio session. A no-op on the Mac, which has none.
final class SystemAudioSession: AudioSessionBackend {
    func apply(_ configuration: AudioSessionConfiguration) {
        #if os(iOS) || os(tvOS) || os(visionOS)
            let session = AVAudioSession.sharedInstance()
            do {
                switch configuration {
                case .silent:
                    try session.setCategory(
                        .playback, mode: .moviePlayback, options: [.mixWithOthers])
                case .audible(let kind):
                    try session.setCategory(
                        .playback, mode: kind == .video ? .moviePlayback : .default)
                    try session.setActive(true)
                }
            } catch {
                PlaybackLog.logger.error(
                    "Audio session setup failed: \(error.localizedDescription, privacy: .public)")
            }
        #endif
    }

    func deactivate() {
        #if os(iOS) || os(tvOS) || os(visionOS)
            let session = AVAudioSession.sharedInstance()
            do {
                // Mixable first: a muted video still on screen that starts the
                // session again must not interrupt the music just handed back.
                try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                PlaybackLog.logger.error(
                    "Audio session deactivation failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        #endif
    }
}
