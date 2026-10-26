// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaUI

/// Every list of posts filters with `FilterVerdicts`, so a post reads the
/// same wherever it turns up; these are the parts that used to differ.
@Suite("Filter verdicts outside Home")
@MainActor
struct FilterVerdictsTests {
    private let alice = Account(id: "1", username: "alice", acct: "alice")

    private func post(_ id: String, _ text: String, quoting quoted: Status? = nil) -> Status {
        Status(
            id: id, content: "<p>\(text)</p>", account: alice,
            quote: quoted.map { Status.QuotedStatus(quotedStatus: $0) })
    }

    private func filter(
        _ keyword: String, action: FilterAction, contexts: [FilterContext]
    ) -> Filter {
        Filter(
            id: keyword, title: keyword.capitalized, context: contexts, filterAction: action,
            keywords: [Filter.Keyword(id: keyword, keyword: keyword)])
    }

    @Test("A list keeps what no hide filter matched, in its own context only")
    func keepsByContext() {
        let verdicts = FilterVerdicts(context: .thread)
        verdicts.filters = [
            filter("spoilers", action: .hide, contexts: [.thread]),
            filter("election", action: .hide, contexts: [.home]),
        ]
        let kept = verdicts.kept([
            post("1", "spoilers ahead"), post("2", "election news"), post("3", "cats"),
        ])
        #expect(kept.map(\.id) == ["2", "3"])
    }

    @Test("A warn filter gives the row its title rather than removing it")
    func warnTitles() {
        let verdicts = FilterVerdicts(context: .public)
        verdicts.filters = [filter("election", action: .warn, contexts: [.public])]
        let status = post("1", "election news")
        #expect(verdicts.kept([status]).count == 1)
        #expect(verdicts.warning(for: status) == "Election")
    }

    @Test("A quoted post is judged as a post of its own")
    func quotesAreJudged() async {
        let verdicts = FilterVerdicts(context: .home)
        verdicts.filters = [filter("spoilers", action: .hide, contexts: [.home])]
        let quoted = post("q", "spoilers inside")
        let quoting = post("1", "look at this", quoting: quoted)
        await verdicts.warm([quoting])
        // The quoting post is clean; what it quotes is not.
        #expect(verdicts.decision(for: quoting) == .show)
        #expect(verdicts.decision(for: quoted) == .hide)
    }

    @Test("Changing the filters drops the verdicts already decided")
    func filtersChangeVerdicts() {
        let verdicts = FilterVerdicts(context: .home)
        let status = post("1", "spoilers")
        #expect(verdicts.decision(for: status) == .show)
        verdicts.filters = [filter("spoilers", action: .hide, contexts: [.home])]
        #expect(verdicts.decision(for: status) == .hide)
    }

    @Test("Each timeline is read in the context Mastodon names for it")
    func timelineContexts() {
        #expect(FilterVerdicts.context(for: .home) == .home)
        #expect(FilterVerdicts.context(for: .list(id: "1")) == .home)
        #expect(FilterVerdicts.context(for: .local) == .public)
        #expect(FilterVerdicts.context(for: .hashtag(name: "cats")) == .public)
        #expect(FilterVerdicts.context(for: .interests) == .public)
        #expect(
            FilterVerdicts.context(for: .account(id: "1", includeReplies: false, onlyMedia: false))
                == .account)
    }

    @Test("A quote's picture follows its content warning and the media policy")
    func quoteMedia() {
        let plain = Status(id: "1", account: alice)
        let sensitive = Status(id: "2", sensitive: true, account: alice)
        let warned = Status(id: "3", spoilerText: "spiders", account: alice)

        #expect(QuotedStatusCard.showsMedia(of: plain, policy: .hideAll))
        // Covered under blur, but drawn; not drawn at all under hide_all.
        #expect(QuotedStatusCard.showsMedia(of: sensitive, policy: .blur))
        #expect(!QuotedStatusCard.showsMedia(of: sensitive, policy: .hideAll))
        // A content warning collapses the picture with the words, whatever
        // the policy says about media.
        #expect(!QuotedStatusCard.showsMedia(of: warned, policy: .showAll))
    }
}
