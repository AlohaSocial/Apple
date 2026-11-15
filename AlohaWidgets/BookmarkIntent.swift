// SPDX-License-Identifier: MIT

import AlohaStore
import AppIntents
import Foundation

/// The bookmark on a widget row: saves the post for later without opening
/// the app, as the heart beside it favourites (`FavouriteFromWidgetIntent`).
struct BookmarkFromWidgetIntent: AppIntent {
    static let title = LocalizedStringResource(
        "Bookmark a post", comment: "Widget intent title, not shown in the widget itself")
    static let isDiscoverable = false

    @Parameter(title: LocalizedStringResource("Account", comment: "Widget intent parameter"))
    var accountID: String

    @Parameter(title: LocalizedStringResource("Post", comment: "Widget intent parameter"))
    var statusID: String

    @Parameter(title: LocalizedStringResource("Bookmark", comment: "Widget intent parameter"))
    var bookmark: Bool

    init() {}

    init(accountID: UUID, statusID: String, bookmark: Bool) {
        self.accountID = accountID.uuidString
        self.statusID = statusID
        self.bookmark = bookmark
    }

    func perform() async throws -> some IntentResult {
        guard let account = UUID(uuidString: accountID) else { return .result() }
        WidgetBookmarks.set(bookmark, statusID: statusID, accountID: account)
        do {
            try await WidgetActions.setBookmark(bookmark, statusID: statusID, accountID: account)
        } catch {
            WidgetBookmarks.clear(statusID: statusID, accountID: account)
            throw error
        }
        return .result()
    }
}
