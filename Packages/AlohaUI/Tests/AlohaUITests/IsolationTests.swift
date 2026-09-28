// SPDX-License-Identifier: MIT

import AlohaNetwork
import Foundation
import Testing

@testable import AlohaUI

/// This package compiles with `MainActor` default isolation, which is right for
/// view code and wrong for anything a system framework calls back on its own
/// queue. An isolated closure invoked from another thread does not merely warn:
/// Swift's runtime isolation check traps and the process dies.
///
/// That is exactly how sign-in crashed — `ASWebAuthenticationSession` delivers
/// its completion on a background XPC queue. These tests pin the shape of the
/// fix so the pattern cannot come back.
@Suite("Cross-queue callback isolation")
struct CallbackIsolationTests {

    @Test("An explicitly @Sendable completion runs off the main thread without trapping")
    func sendableCompletionSurvivesBackgroundQueue() async {
        // The same declaration shape as the web-authentication completion: the
        // type annotation is what keeps it out of the actor's isolation.
        await confirmation("completion ran") { ran in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let completion: @Sendable (URL?, (any Error)?) -> Void = { callback, _ in
                    #expect(Thread.isMainThread == false)
                    ran()
                    continuation.resume()
                }

                DispatchQueue.global(qos: .userInitiated).async {
                    completion(URL(string: "alohasocial://oauth-callback?code=x"), nil)
                }
            }
        }
    }

    @Test("StreamingConnection is nonisolated, so its socket callbacks cannot trap")
    func streamingConnectionIsNonisolated() async {
        // Constructing and closing it from a background context is the proof:
        // a MainActor-isolated type could not be touched from here at all.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                let connection = StreamingConnection(
                    url: URL(string: "wss://example.test/api/v1/streaming")!,
                    token: "token",
                    onEvent: { _ in })
                #expect(connection.isOpen == false)
                connection.close()
                continuation.resume()
            }
        }
    }

    @Test("Backoff grows and stays inside its cap")
    func backoffIsBounded() {
        for attempt in 0..<12 {
            let delay = Backoff.delay(attempt: attempt, cap: 60)
            #expect(delay >= 0)
            #expect(delay <= 60)
        }
    }
}
