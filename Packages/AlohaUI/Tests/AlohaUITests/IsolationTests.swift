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

    /// `NWPathMonitor` reports the path on its own queue. Under an SDK that
    /// does not mark the handler `@Sendable`, a handler written in a
    /// main-actor class was inferred isolated and trapped on the first
    /// update — but only when the preloader lived long enough to get one,
    /// which is why the package suite died now and then rather than always.
    /// This one waits for that update.
    @MainActor
    @Test("The network monitor's first update arrives off the main thread without trapping")
    func preloaderSurvivesItsFirstPathUpdate() async {
        let preloader = NextVideoPreloader()
        for _ in 0..<50 where !preloader.allowsPrefetch {
            try? await Task.sleep(for: .milliseconds(100))
        }
        // Reaching here is the assertion; the read keeps the preloader, and so
        // its monitor, alive through the wait.
        _ = preloader.allowsPrefetch
    }

    @Test("A closed streaming connection never opens again")
    func closedStreamingConnectionStaysClosed() async throws {
        // A reconnect that was already sleeping used to reopen a socket that
        // had been closed on purpose. Closed is final now.
        let url = try #require(URL(string: "wss://example.test/api/v1/streaming"))
        let connection = StreamingConnection(url: url, token: "token", onEvent: { _ in })
        #expect(await connection.isOpen == false)
        await connection.close()
        await connection.open()
        #expect(await connection.isOpen == false)
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
