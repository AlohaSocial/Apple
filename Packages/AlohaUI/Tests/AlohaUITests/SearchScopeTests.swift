// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import Testing

@testable import AlohaUI

private func account(_ id: String) -> Account {
    Account(id: id, username: "user\(id)", acct: "user\(id)")
}

@Suite("Search scopes")
struct SearchScopeTests {
    @Test("Each scope narrows to its own kind; All narrows to none")
    func types() {
        #expect(SearchScope.all.resultType == nil)
        #expect(SearchScope.accounts.resultType == .accounts)
        #expect(SearchScope.all.shows(.statuses))
        #expect(!SearchScope.hashtags.shows(.accounts))
    }

    @Test("All offers See all when it holds results back")
    func seeAll() {
        // People and hashtags preview five.
        #expect(!SearchScope.hasMore(than: SearchScope.allPreview, of: .accounts))
        #expect(SearchScope.hasMore(than: SearchScope.allPreview + 1, of: .hashtags))
        // Posts show everything All received; only a full page hides more.
        #expect(!SearchScope.hasMore(than: SearchScope.allLimit - 1, of: .statuses))
        #expect(SearchScope.hasMore(than: SearchScope.allLimit, of: .statuses))
    }

    @Test("A full page may have more behind it; a short or empty one is the end")
    func end() {
        #expect(SearchPaging.mayHaveMore(received: SearchScope.pageSize))
        #expect(!SearchPaging.mayHaveMore(received: SearchScope.pageSize - 1))
        #expect(!SearchPaging.mayHaveMore(received: 0))
    }

    @Test("The next page adds what is new, under what is shown")
    func appending() {
        let shown = SearchResults(accounts: [account("1"), account("2")])
        let page = SearchResults(accounts: [account("2"), account("3")])
        let merged = SearchPaging.appending(page, to: shown, type: .accounts)
        #expect(merged.accounts.map(\.id) == ["1", "2", "3"])
        #expect(merged.count(of: .accounts) == 3)
        #expect(merged.count(of: .statuses) == 0)
    }
}
