// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaUI

/// What keeps reading steady: feeds that survive the shell being rebuilt (an
/// iPhone Duo folding), players that pick up where they were, and the reply
/// bar answering by the composer's rules.
@Suite("Smooth reading")
@MainActor
struct SmoothReadingTests {
    private final class Probe {}

    private let account = UUID()
    private let home = TimelineKey(mode: .home, source: .home)
    private let photos = TimelineKey(mode: .photos, source: .home)

    // MARK: - Kept feed models

    @Test("A screen built again gets the same model back")
    func modelIsKept() {
        let cache = KeyedModelCache<Probe>()
        let first = cache.model(for: home, accountID: account) { Probe() }
        let again = cache.model(for: home, accountID: account) { Probe() }
        #expect(first === again)
        #expect(cache.model(for: photos, accountID: account) { Probe() } !== first)
    }

    @Test("Another account starts afresh")
    func accountSwitchDropsModels() {
        let cache = KeyedModelCache<Probe>()
        let mine = cache.model(for: home, accountID: account) { Probe() }
        cache.shortsSource = .local
        let theirs = cache.model(for: home, accountID: UUID()) { Probe() }
        #expect(mine !== theirs)
        #expect(cache.shortsSource == nil)
        #expect(cache.existing(for: home, accountID: account) == nil)
    }

    @Test("Only the most recently used feeds are kept")
    func leastRecentlyUsedIsDropped() {
        let cache = KeyedModelCache<Probe>(capacity: 2)
        let first = cache.model(for: home, accountID: account) { Probe() }
        _ = cache.model(for: photos, accountID: account) { Probe() }
        // Home used again, so Photos is now the oldest.
        _ = cache.model(for: home, accountID: account) { Probe() }
        _ = cache.model(for: TimelineKey(mode: .video, source: .home), accountID: account) {
            Probe()
        }
        #expect(cache.existing(for: home, accountID: account) === first)
        #expect(cache.existing(for: photos, accountID: account) == nil)
    }

    // MARK: - Playback hand-over

    @Test("A player rebuilt a moment later starts where the last one was")
    func handOverWithinWindow() {
        var ledger = PlaybackHandover()
        let now = Date()
        ledger.record(42.5, wasPlaying: true, for: "v1", now: now)
        #expect(
            ledger.position(for: "v1", now: now.addingTimeInterval(2))
                == .init(seconds: 42.5, wasPlaying: true))
        #expect(ledger.position(for: "v2", now: now) == nil)
    }

    @Test("A video opened again later, or barely started, starts at the beginning")
    func noHandOverWhenStaleOrUnstarted() {
        var ledger = PlaybackHandover()
        let now = Date()
        ledger.record(42.5, wasPlaying: false, for: "v1", now: now)
        #expect(
            ledger.position(for: "v1", now: now.addingTimeInterval(PlaybackHandover.window + 1))
                == nil)
        ledger.record(0.3, wasPlaying: true, for: "v1", now: now)
        #expect(ledger.position(for: "v1", now: now) == nil)
        ledger.record(.nan, wasPlaying: true, for: "v3", now: now)
        #expect(ledger.position(for: "v3", now: now) == nil)
    }

    @Test("The ledger stays small")
    func handOverIsBounded() {
        var ledger = PlaybackHandover()
        let now = Date()
        for index in 0..<(PlaybackHandover.capacity + 5) {
            ledger.record(
                10, wasPlaying: true, for: "v\(index)", now: now.addingTimeInterval(Double(index)))
        }
        #expect(ledger.position(for: "v0", now: now) == nil)
        let last = PlaybackHandover.capacity + 4
        #expect(ledger.position(for: "v\(last)", now: now.addingTimeInterval(Double(last))) != nil)
    }

    // MARK: - Reply bar

    private let author = Account(id: "a", username: "alice", acct: "alice@remote.test")
    private let limits = ServerLimits.mastodonDefaults

    private func post(
        visibility: Visibility = .public, spoiler: String = "", mentions: [Status.Mention] = []
    ) -> Status {
        Status(
            id: "42", spoilerText: spoiler, visibility: visibility, account: author,
            mentions: mentions)
    }

    private func rules(for status: Status?, defaultVisibility: Visibility = .public) -> QuickReply {
        QuickReply(
            replyTo: status, viewerHandle: "me", defaultVisibility: defaultVisibility,
            limits: limits)
    }

    @Test("A reply addresses everyone the composer would, minus the writer")
    func replyMentions() {
        let rules = rules(
            for: post(mentions: [
                Status.Mention(id: "b", username: "bob", acct: "bob"),
                Status.Mention(id: "m", username: "me", acct: "me"),
            ]))
        #expect(rules.postText("  hi ") == "@alice@remote.test @bob hi")
        // Named already: not twice.
        #expect(rules.postText("@bob @alice@remote.test hi") == "@bob @alice@remote.test hi")
    }

    @Test("A reply is never less private than the post, nor than the reader's default")
    func replyVisibility() {
        #expect(rules(for: post(visibility: .private)).visibility == .private)
        #expect(rules(for: post(), defaultVisibility: .unlisted).visibility == .unlisted)
        #expect(rules(for: nil, defaultVisibility: .unlisted).visibility == .unlisted)
    }

    @Test("A reply to a post behind a warning goes behind the same warning")
    func replyKeepsWarning() {
        let sent = rules(for: post(spoiler: "spoilers")).post(
            "hi", language: "en", idempotencyKey: "k")
        #expect(sent.spoilerText == "spoilers")
        #expect(sent.inReplyToID == "42")
        #expect(sent.language == "en")
        #expect(sent.idempotencyKey == "k")
        let plain = rules(for: post()).post("hi", language: nil, idempotencyKey: "k")
        #expect(plain.spoilerText == nil)
    }

    @Test("The limit counts the mentions and the warning, and nothing over it is sent")
    func characterLimit() {
        let rules = rules(for: post(spoiler: "cw"))
        let prefix = "@alice@remote.test ".count + "cw".count
        let fits = String(repeating: "a", count: limits.maxStatusCharacters - prefix)
        #expect(rules.remaining(fits) == 0)
        #expect(rules.canSend(fits))
        #expect(!rules.canSend(fits + "a"))
        #expect(rules.remaining(fits + "a") == -1)
        #expect(!rules.canSend("   "))
        #expect(!rules.showsCount("hi"))
        #expect(rules.showsCount(fits))
    }

    @Test("Expanding to the composer carries the words, addressed; nothing typed carries nothing")
    func composerHandOff() {
        let rules = rules(for: post())
        #expect(rules.composerText("hi") == "@alice@remote.test hi")
        // Empty: the composer prefills the mentions itself.
        #expect(rules.composerText("  ") == "")
    }

    // MARK: - Translation scope

    @Test("Each post's translation state is its own")
    func translationStateIsPerPost() {
        let translator = Translator()
        #expect(translator.translation(for: "1") == nil)
        #expect(!translator.isTranslating("1"))
        translator.completeOnDevice(statusID: "1", content: "Hallo")
        #expect(translator.translation(for: "1")?.content == "Hallo")
        #expect(translator.translation(for: "2") == nil)
        // Distinct observables: reading post 2 never touches post 1's slot.
        #expect(translator.slot("1") !== translator.slot("2"))
        translator.clear("1")
        #expect(translator.translation(for: "1") == nil)
    }
}
