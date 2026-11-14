// SPDX-License-Identifier: MIT

import AppKit
import Foundation

/// "Post to Aloha Social" in every app's Services menu (docs/09 §2): the
/// selected text, or a link, opens a compose window with it already written.
///
/// Declared under `NSServices` in the Mac app's Info.plist; the message name
/// there is this method's selector. Pictures are not offered: a compose
/// window's request is the window's value, and image data does not belong
/// in it.
final class MacServiceProvider: NSObject {
    @objc func postToAlohaSocial(
        _ pasteboard: NSPasteboard, userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let text = Self.text(from: pasteboard)
        guard !text.isEmpty else {
            error.pointee =
                String(
                    localized: "There was no text or link to post.",
                    comment: "Services menu error") as NSString
            return
        }
        MacWindows.compose(draftText: text)
    }

    /// The selection as the composer should open with it. A browser hands
    /// over a selected link as both its text and its URL; the text is what
    /// was chosen, and the URL is used only where there is no text at all.
    static func text(from pasteboard: NSPasteboard) -> String {
        if let string = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty
        {
            return string
        }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        return urls.map(\.absoluteString).joined(separator: "\n")
    }
}
