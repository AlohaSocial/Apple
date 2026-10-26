// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import MediaPlayer
import Testing

@testable import AlohaUI

@Suite("Audio mode lock-screen controls")
struct RemoteCommandTests {

    /// Stands in for `MPRemoteCommandCenter`, counting what is attached.
    private final class RecordingCentre: RemoteCommandCentre {
        var added: [RemoteCommand] = []
        var removed: [RemoteCommand] = []
        var attached: Int { added.count - removed.count }

        func addTarget(for command: RemoteCommand, handler: @escaping RemoteCommandHandler) -> Any {
            added.append(command)
            return command
        }

        func removeTarget(_ target: Any, for command: RemoteCommand) {
            removed.append(command)
        }
    }

    @Test("Playing a second track does not attach a second set of handlers")
    func registersOnce() {
        let centre = RecordingCentre()
        let registration = RemoteCommandRegistration(
            centre: centre, handlers: AudioPlayerCoordinator.remoteCommandHandlers())

        registration.register()
        registration.register()

        #expect(centre.added.count == RemoteCommand.allCases.count)
        #expect(Set(centre.added) == Set(RemoteCommand.allCases))
    }

    @Test("Stopping takes every handler off, and the next track puts one set back")
    func unregistersOnStop() {
        let centre = RecordingCentre()
        let registration = RemoteCommandRegistration(
            centre: centre, handlers: AudioPlayerCoordinator.remoteCommandHandlers())

        registration.register()
        registration.unregister()
        #expect(centre.attached == 0)
        #expect(registration.isRegistered == false)

        registration.register()
        #expect(centre.attached == RemoteCommand.allCases.count)
    }

    @Test("Play and Pause are separate commands, not two toggles")
    func playAndPauseAreDistinct() {
        let handlers = AudioPlayerCoordinator.remoteCommandHandlers()
        #expect(handlers[.play] != nil)
        #expect(handlers[.pause] != nil)
        #expect(handlers[.togglePlayPause] != nil)
    }

    /// The system calls these on a queue of its own. A handler inferred
    /// main-actor-isolated traps there (docs/14 §6); this one must not.
    @Test("Every lock-screen handler runs off the main thread without trapping")
    func handlersSurviveBackgroundQueue() async {
        let handlers = Array(AudioPlayerCoordinator.remoteCommandHandlers().values)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                #expect(Thread.isMainThread == false)
                for handler in handlers {
                    _ = handler()
                }
                continuation.resume()
            }
        }
    }
}

@Suite("Audio mode queue")
struct AudioQueueTests {

    private let account = Account(id: "a", username: "alice", acct: "alice")

    private func track(_ id: String) -> Status {
        Status(
            id: id, account: account,
            mediaAttachments: [
                MediaAttachment(
                    id: "m\(id)", type: .audio,
                    url: URL(string: "https://cloud.example/media/\(id).mp3"))
            ])
    }

    @Test("The end of a track is the start of the next one in the list")
    func advancesInOrder() {
        let queue = [track("1"), track("2"), track("3")]
        #expect(AudioPlayerCoordinator.track(after: queue[0], in: queue)?.id == "2")
        #expect(AudioPlayerCoordinator.track(after: queue[2], in: queue) == nil)
    }

    /// `nowPlaying` is the post a boost carries, while the queue holds the
    /// boost itself; matching on the row's own id ended the queue there.
    @Test("A boosted track is found in the queue and followed by the next")
    func boostedTrackAdvances() {
        let boost = Status(id: "boost", account: account, reblog: Box(track("1")))
        let queue = [boost, track("2")]
        #expect(AudioPlayerCoordinator.track(after: boost.displayed, in: queue)?.id == "2")
    }

    @Test("A post with nothing to play is skipped rather than ending the queue")
    func skipsSilentPosts() {
        let silent = Status(id: "text", account: account)
        let queue = [track("1"), silent, track("3")]
        #expect(AudioPlayerCoordinator.track(after: queue[0], in: queue)?.id == "3")
    }
}

@Suite("Audio session coordination")
struct AudioSessionCoordinatorTests {

    /// Stands in for `AVAudioSession`, recording what it was told.
    private final class RecordingBackend: AudioSessionBackend {
        enum Event: Equatable {
            case apply(AudioSessionConfiguration)
            case deactivate
        }
        var events: [Event] = []

        func apply(_ configuration: AudioSessionConfiguration) {
            events.append(.apply(configuration))
        }

        func deactivate() { events.append(.deactivate) }
    }

    /// Owners are object identities; any two distinct objects will do.
    private final class Owner {}

    @Test("A muted video makes the session mixable and never activates it")
    func silentPlaybackMixes() {
        let backend = RecordingBackend()
        let sessions = AudioSessionCoordinator(backend: backend)

        sessions.prepareForSilentPlayback()
        sessions.prepareForSilentPlayback()

        #expect(backend.events == [.apply(.silent)])
        #expect(sessions.audibleCount == 0)
    }

    @Test("Sound takes the session, and the last one out hands it back")
    func lastReleaseDeactivates() {
        let backend = RecordingBackend()
        let sessions = AudioSessionCoordinator(backend: backend)
        let owner = Owner()

        sessions.prepareForSilentPlayback()
        let claim = sessions.claim(owner: ObjectIdentifier(owner), kind: .video) {}
        #expect(backend.events.last == .apply(.audible(.video)))

        sessions.release(claim)
        #expect(backend.events.last == .deactivate)
        #expect(sessions.configuration == .silent)

        // Already mixable after the hand-back: nothing more to set.
        sessions.prepareForSilentPlayback()
        #expect(backend.events.count == 3)
    }

    @Test("The session stays active until every claim on it is given back")
    func countsClaims() {
        let backend = RecordingBackend()
        let sessions = AudioSessionCoordinator(backend: backend)
        let player = Owner()

        // The same player on two surfaces at once.
        let first = sessions.claim(owner: ObjectIdentifier(player), kind: .video) {}
        let second = sessions.claim(owner: ObjectIdentifier(player), kind: .video) {}
        #expect(sessions.audibleCount == 2)

        sessions.release(first)
        #expect(backend.events.contains(.deactivate) == false)
        sessions.release(first)
        #expect(backend.events.contains(.deactivate) == false)

        sessions.release(second)
        #expect(backend.events.filter { $0 == .deactivate }.count == 1)
    }

    @Test("Starting a track pauses a video playing with sound, and the other way round")
    func newClaimPreemptsOthers() {
        let backend = RecordingBackend()
        let sessions = AudioSessionCoordinator(backend: backend)
        let video = Owner()
        let audio = Owner()
        var videoPaused = false
        var audioPaused = false

        let videoClaim = sessions.claim(owner: ObjectIdentifier(video), kind: .video) {
            videoPaused = true
        }
        let audioClaim = sessions.claim(owner: ObjectIdentifier(audio), kind: .audio) {
            audioPaused = true
        }
        #expect(videoPaused)
        #expect(sessions.holds(videoClaim) == false)
        #expect(sessions.holds(audioClaim))
        #expect(sessions.configuration == .audible(.audio))
        // Switching owners is not a hand-back: other apps stay paused.
        #expect(backend.events.contains(.deactivate) == false)

        let again = sessions.claim(owner: ObjectIdentifier(video), kind: .video) {}
        #expect(audioPaused)
        #expect(sessions.configuration == .audible(.video))

        // The preempted claim is already gone; giving it back changes nothing.
        sessions.release(videoClaim)
        #expect(backend.events.contains(.deactivate) == false)
        sessions.release(again)
        #expect(backend.events.last == .deactivate)
    }

    @Test("A muted video starting while sound plays leaves the session alone")
    func silentPlaybackDoesNotDowngrade() {
        let backend = RecordingBackend()
        let sessions = AudioSessionCoordinator(backend: backend)
        let audio = Owner()

        _ = sessions.claim(owner: ObjectIdentifier(audio), kind: .audio) {}
        sessions.prepareForSilentPlayback()

        #expect(backend.events == [.apply(.audible(.audio))])
    }
}
