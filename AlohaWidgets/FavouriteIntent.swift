// SPDX-License-Identifier: MIT

import AlohaStore
import AppIntents
import Foundation

/// The heart on a widget row.
///
/// It runs in the widget extension, never opening the app: the token comes
/// from the shared Keychain group and the post's new state goes back into
/// the shared store. The tap is written to `WidgetFavourites` first, so the
/// row that redraws when this returns already shows it, and is taken back if
/// the server refuses.
struct FavouriteFromWidgetIntent: AppIntent {
    static let title = LocalizedStringResource(
        "Favourite a post", comment: "Widget intent title, not shown in the widget itself")
    /// Only the widget offers it: in Shortcuts a post id typed by hand is not
    /// something anybody can use.
    static let isDiscoverable = false

    @Parameter(title: LocalizedStringResource("Account", comment: "Widget intent parameter"))
    var accountID: String

    @Parameter(title: LocalizedStringResource("Post", comment: "Widget intent parameter"))
    var statusID: String

    @Parameter(title: LocalizedStringResource("Favourite", comment: "Widget intent parameter"))
    var favourite: Bool

    init() {}

    init(accountID: UUID, statusID: String, favourite: Bool) {
        self.accountID = accountID.uuidString
        self.statusID = statusID
        self.favourite = favourite
    }

    func perform() async throws -> some IntentResult {
        guard let account = UUID(uuidString: accountID) else { return .result() }
        WidgetFavourites.set(favourite, statusID: statusID, accountID: account)
        do {
            try await WidgetActions.setFavourite(
                favourite, statusID: statusID, accountID: account)
        } catch {
            WidgetFavourites.clear(statusID: statusID, accountID: account)
            throw error
        }
        return .result()
    }
}
