// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaModels

/// Whether the reader is learned from decides whether the app collects any
/// reading signal at all, so a missing or partial answer must read as "no".
@Suite struct ReadingLearningTests {
    private func settings(_ json: String) throws -> InterestsState.Settings {
        try JSONDecoder().decode(InterestsState.Settings.self, from: Data(json.utf8))
    }

    @Test func theServersOwnAnswerWins() throws {
        #expect(try settings(#"{"learning":true,"active":false}"#).isLearning == false)
        #expect(try settings(#"{"learning":false,"active":true}"#).isLearning == true)
    }

    @Test func withoutAnAnswerEverySwitchAndTheNoticeMustAgree() throws {
        let all =
            #"{"enabled":true,"learning":true,"paused":false,"instancePaused":false,"noticeAcknowledged":true}"#
        #expect(try settings(all).isLearning)
        #expect(
            try settings(all.replacingOccurrences(of: #""paused":false"#, with: #""paused":true"#))
                .isLearning == false)
        #expect(
            try settings(
                all.replacingOccurrences(
                    of: #""instancePaused":false"#, with: #""instancePaused":true"#)
            ).isLearning == false)
        #expect(
            try settings(
                all.replacingOccurrences(of: #""enabled":true"#, with: #""enabled":false"#)
            ).isLearning == false)
        #expect(
            try settings(
                all.replacingOccurrences(
                    of: #""noticeAcknowledged":true"#, with: #""noticeAcknowledged":false"#)
            ).isLearning == false)
    }

    @Test func anOlderServerThatNeverToldTheNoticeIsNotLearnedFrom() throws {
        #expect(try settings(#"{"learning":true,"paused":false}"#).isLearning == false)
    }

    @Test func theNoticeIsDueOnlyWhileLearningIsOnAndUnseen() throws {
        #expect(try settings(#"{"learning":true,"noticeAcknowledged":false}"#).needsNotice)
        #expect(
            try settings(#"{"learning":false,"noticeAcknowledged":false}"#).needsNotice == false)
        #expect(try settings(#"{"learning":true,"noticeAcknowledged":true}"#).needsNotice == false)
        #expect(try settings(#"{"enabled":false,"learning":true}"#).needsNotice == false)
    }

    @Test func preferencesCarryTheLearningAnswerWhereTheServerHasIt() throws {
        let decoder = JSONDecoder()
        let with = try decoder.decode(Preferences.self, from: Data(#"{"reading:learn":true}"#.utf8))
        let without = try decoder.decode(Preferences.self, from: Data("{}".utf8))
        #expect(with.learnsFromReading == true)
        #expect(without.learnsFromReading == nil)
    }
}
