// SPDX-License-Identifier: MIT

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
