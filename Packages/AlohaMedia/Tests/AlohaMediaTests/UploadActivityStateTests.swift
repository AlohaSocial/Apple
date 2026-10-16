// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaMedia

/// The Live Activity used to end on the first failed file while the others
/// were still going up, and said "finished" while the server was still
/// transcoding. These pin what each moment of a batch reads as.
@Suite("Upload activity phases")
struct UploadActivityStateTests {
    private typealias State = UploadActivityAttributes.ContentState

    @Test("A batch with files in flight is uploading, even after a failure")
    func failureDoesNotEndTheBatch() {
        let progress = UploadProgress()
        let first = progress.begin("a.jpg")
        _ = progress.begin("b.mov")
        progress.finish(first, failed: true)

        let state = State.of(progress, processing: 0)
        #expect(state.phase == .uploading)
        #expect(state.currentFilename == "b.mov")
    }

    @Test("A finished batch with a failure reads as failed")
    func finishedWithFailure() {
        let progress = UploadProgress()
        let first = progress.begin("a.jpg")
        let second = progress.begin("b.jpg")
        progress.finish(first)
        progress.finish(second, failed: true)
        #expect(State.of(progress, processing: 0).phase == .failed)
    }

    @Test("Uploaded but still transcoding is processing, not finished")
    func processingIsItsOwnPhase() {
        let progress = UploadProgress()
        progress.finish(progress.begin("clip.mov"))
        #expect(State.of(progress, processing: 1).phase == .processing)
        #expect(State.of(progress, processing: 0).phase == .ready)
    }
}
