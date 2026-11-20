// SPDX-License-Identifier: MIT

import AlohaHTML
import AlohaModels
import Foundation

#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

/// A post's address and words, for the pasteboard and the browser: Copy
/// Link, Copy Text, Open in Browser and the links inside a post, from its
/// menu and from the Mac's Post menu.
///
/// The browser is opened by the platform, not by the app's `openURL`, which
/// resolves a fediverse address inside the app — the right answer to a tap
/// on a link, and the wrong one to a menu item that says "in Browser".
enum PostLinks {
    /// The post's public page: its `url`, or its `uri` where a server sent
    /// no page (an ActivityPub id is still an address a browser can open).
    static func address(of status: Status) -> URL? {
        let post = status.displayed
        if let url = post.url { return url }
        guard let uri = URL(string: post.uri), uri.scheme?.hasPrefix("http") == true else {
            return nil
        }
        return uri
    }

    /// The post's words as a reader sees them: the HTML's text, with the
    /// content warning in front where there is one.
    static func text(of status: Status) -> String {
        let post = status.displayed
        let body = StatusHTMLParser().plainText(post.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !post.spoilerText.isEmpty else { return body }
        return post.spoilerText + "\n\n" + body
    }

    /// The web links written in the post, in reading order and without
    /// repeats — not its mentions and hashtags, which open in the app.
    static func webLinks(in status: Status) -> [URL] {
        let post = status.displayed
        let parsed = StatusHTMLParser().parse(
            post.content, mentions: post.mentions, tags: post.tags, emojis: post.emojis)
        var seen: Set<URL> = []
        return parsed.webLinks.filter { seen.insert($0).inserted }
    }

    /// What a link reads as in a menu: host and path, which is what a
    /// person recognises a link by; the scheme and query are noise.
    static func title(for url: URL) -> String {
        LinkRotorEntry.label(for: url)
    }

    static func copy(_ string: String) {
        #if canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        #elseif canImport(UIKit) && !os(watchOS)
            UIPasteboard.general.string = string
        #endif
    }

    /// A link on the pasteboard as a link, so an app that takes URLs gets
    /// one, and as text for every other.
    static func copy(_ url: URL) {
        #if canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #elseif canImport(UIKit) && !os(watchOS)
            UIPasteboard.general.url = url
        #endif
    }

    @MainActor
    static func openInBrowser(_ url: URL) {
        #if canImport(AppKit)
            NSWorkspace.shared.open(url)
        #elseif canImport(UIKit) && !os(watchOS)
            UIApplication.shared.open(url)
        #endif
    }
}
