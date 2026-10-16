// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaStore
import Foundation
import Testing

@testable import AlohaUI

@Suite("Notification delivery, here and on the server")
struct NotificationDeliveryMappingTests {
    @Test("The server's digest adopts as whole hours and quiet hours")
    func adopt() {
        var settings = AccountSettings()
        settings.adopt(
            NotificationDeliverySettings(
                mode: .digest, times: ["07:30", "19:00", "bad"], quietFrom: "23:00",
                quietTo: "06:00"))
        #expect(settings.notificationDeliveryMode == .digest)
        #expect(settings.digestTimes == [7, 19])
        #expect(settings.quietHoursStart == 23)
        #expect(settings.quietHoursEnd == 6)
    }

    @Test("No quiet hours on the server is none here, and no times keeps the default")
    func adoptEmpty() {
        var settings = AccountSettings(quietHoursStart: 22, quietHoursEnd: 7)
        settings.adopt(NotificationDeliverySettings(mode: .instant))
        #expect(settings.notificationDeliveryMode == .immediate)
        #expect(settings.digestTimes == [8])
        #expect(settings.quietHoursStart == nil)
        #expect(settings.quietHoursEnd == nil)
    }

    @Test("What goes back keeps the server's passthrough switches")
    func outgoing() {
        let settings = AccountSettings(
            quietHoursStart: 22, quietHoursEnd: 7, notificationDeliveryMode: .digest,
            digestTimes: [8, 18])
        let server = NotificationDeliverySettings(
            passthroughDirect: false, passthroughMentionsFromFollowed: false)
        let outgoing = settings.serverDelivery(keeping: server)
        #expect(outgoing.mode == .digest)
        #expect(outgoing.times == ["08:00", "18:00"])
        #expect(outgoing.quietFrom == "22:00")
        #expect(outgoing.quietTo == "07:00")
        #expect(!outgoing.passthroughDirect)
        #expect(!outgoing.passthroughMentionsFromFollowed)
    }

    @Test("Half a pair of quiet hours goes out as none")
    func halfQuiet() {
        let settings = AccountSettings(quietHoursStart: 22, quietHoursEnd: nil)
        let outgoing = settings.serverDelivery(keeping: NotificationDeliverySettings())
        #expect(outgoing.quietFrom.isEmpty)
        #expect(outgoing.quietTo.isEmpty)
    }
}

@Suite("Reading signals")
struct ReadingSignalsTests {
    @Test("A timeline's rows are read in the server's own context")
    func contexts() {
        #expect(InterestSignal.Context(key: .home()) == .home)
        #expect(InterestSignal.Context(key: .home(.local)) == .local)
        #expect(InterestSignal.Context(key: .home(.federated)) == .federated)
        #expect(InterestSignal.Context(key: .home(.hashtag(name: "x"))) == .tag)
        #expect(InterestSignal.Context(key: TimelineKey(mode: .photos, source: .home)) == .photos)
        #expect(InterestSignal.Context(key: TimelineKey(mode: .video, source: .home)) == .videos)
        #expect(InterestSignal.Context(key: TimelineKey(mode: .shorts, source: .home)) == .shorts)
    }

    @Test("Time on screen is counted in whole milliseconds")
    func milliseconds() {
        #expect(ReadingSignals.milliseconds(.milliseconds(1500)) == 1500)
        #expect(ReadingSignals.milliseconds(.seconds(2)) == 2000)
    }
}

@Suite("Search")
struct DomainHandleTests {
    @Test(
        "A bare Bluesky handle is resolved",
        arguments: ["alice.bsky.social", "bsky.app", "a-b.c.de"])
    func handles(_ text: String) {
        #expect(SearchView.looksLikeDomainHandle(text))
    }

    @Test(
        "Words, tags and sentences are not handles",
        arguments: ["alice", "#cats", "hello world.", "v1.2", "example.com/path", "a..b"])
    func notHandles(_ text: String) {
        #expect(!SearchView.looksLikeDomainHandle(text))
    }
}

@Suite("Made with AI")
struct AIGeneratedLabelTests {
    @Test("The switch adds the server's hashtag once, after the text")
    func appends() {
        #expect(
            ComposerModel.labelledAsAIGenerated("A sunset\n")
                == "A sunset\n\n#AIgenerated")
        #expect(ComposerModel.labelledAsAIGenerated("") == "#AIgenerated")
    }

    @Test(
        "A post that already says so is left alone",
        arguments: ["Look #AIgenerated", "#madewithai art", "drawn with #GenAI"])
    func alreadyLabelled(_ text: String) {
        #expect(ComposerModel.labelledAsAIGenerated(text) == text)
    }

    @Test("A word that only contains the tag is not the tag")
    func notATag() {
        #expect(
            ComposerModel.labelledAsAIGenerated("#aimless")
                == "#aimless\n\n#AIgenerated")
    }
}
