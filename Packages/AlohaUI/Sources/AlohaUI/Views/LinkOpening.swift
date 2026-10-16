// SPDX-License-Identifier: MIT

import Foundation
import SwiftUI

/// Where a link in a post opens.
///
/// A web page opens over the app, in the system's in-app browser, so
/// reading it is a detour rather than leaving the timeline behind; the
/// reader can ask for the browser instead. Anything the in-app browser
/// cannot show — mail, phone, another app's link — goes to the system as
/// before. On the Mac every link opens in the browser, which is what a Mac
/// reader expects.
enum LinkOpening {
    /// Device-wide rather than per account: it is about this reader's
    /// browser, not about any one server.
    static let externalKey = "aloha.opensLinksExternally"

    static func prefersInApp(_ url: URL, externally: Bool) -> Bool {
        guard !externally, let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }

    @MainActor
    static func open(_ url: URL, with action: OpenURLAction) {
        let externally = UserDefaults.standard.bool(forKey: externalKey)
        action(url, prefersInApp: prefersInApp(url, externally: externally))
    }
}
