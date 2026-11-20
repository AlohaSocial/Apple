// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

/// Every keyboard shortcut the app has, in one list, for the help sheet
/// (Help ▸ Keyboard Shortcuts, ⌘/, and `?` in a list). The keys themselves are
/// the menu bar's (`AlohaCommands`) and the lists' (`statusListNavigation`);
/// change one there and here together. `KeyboardShortcutsTests` checks that
/// no key is listed for two things.
///
/// The single letters are Nextcloud Social's (`services/shortcuts.js`), so a
/// reader of the web app finds the same ones; the ⌘ ones are this app's,
/// because a Mac window has a menu bar and the web page does not.
public enum KeyboardShortcuts {
    public struct Entry: Identifiable, Sendable, Hashable {
        public var id: String { keys.joined(separator: "/") + label }
        /// Shown as written: "J", "⌘N", "?".
        public var keys: [String]
        public var label: String
    }

    /// The keys of a list of posts, which work while the list has the
    /// keyboard focus and nobody is typing (`statusListNavigation`).
    public static var timeline: [Entry] {
        var entries: [Entry] = [
            .init(
                keys: ["J", "↓"],
                label: String(localized: "Next post", comment: "Keyboard shortcut")),
            .init(
                keys: ["K", "↑"],
                label: String(localized: "Previous post", comment: "Keyboard shortcut")),
            .init(
                keys: ["↩", "O"],
                label: String(localized: "Open the selected post", comment: "Keyboard shortcut")),
        ]
        #if os(macOS)
            entries += [
                .init(
                    keys: [
                        String(localized: "Space", comment: "The space bar, in the shortcut list")
                    ],
                    label: String(localized: "Page down", comment: "Keyboard shortcut")),
                .init(
                    keys: [
                        "⇧"
                            + String(
                                localized: "Space", comment: "The space bar, in the shortcut list"),
                        "⌘Y",
                    ],
                    label: String(
                        localized: "Look at the selected post without leaving the list",
                        comment: "Keyboard shortcut")),
            ]
        #endif
        entries += [
            .init(
                keys: ["L", "F"],
                label: String(
                    localized: "Like the selected post", comment: "Keyboard shortcut")),
            .init(
                keys: ["B"],
                label: String(localized: "Boost the selected post", comment: "Keyboard shortcut")),
            .init(
                keys: ["R"],
                label: String(localized: "Reply to the selected post", comment: "Keyboard shortcut")
            ),
            .init(
                keys: ["?"],
                label: String(localized: "Show these shortcuts", comment: "Keyboard shortcut")),
        ]
        return entries
    }

    /// The ones that work anywhere in the window: the menu bar's.
    public static var global: [Entry] {
        #if os(macOS)
            return [
                .init(
                    keys: ["⌘N"],
                    label: String(localized: "Write a new post", comment: "Keyboard shortcut")),
                .init(
                    keys: ["⌥⌘N"],
                    label: String(localized: "Open a new window", comment: "Keyboard shortcut")),
                .init(
                    keys: ["⌘L"],
                    label: String(
                        localized: "Open a post or profile by its link",
                        comment: "Keyboard shortcut")),
                .init(
                    keys: ["⌘F"], label: String(localized: "Search", comment: "Keyboard shortcut")),
                .init(
                    keys: ["⌘K"],
                    label: String(localized: "Go to a place by name", comment: "Keyboard shortcut")),
                .init(
                    keys: ["⌘R"],
                    label: String(localized: "Refresh the list", comment: "Keyboard shortcut")),
                .init(
                    keys: ["⌘["], label: String(localized: "Go back", comment: "Keyboard shortcut")),
                .init(
                    keys: ["⇧⌘H"],
                    label: String(
                        localized: "Go to your home timeline", comment: "Keyboard shortcut")),
                .init(
                    keys: ["⌘1…⌘9"],
                    label: String(
                        localized: "The places in the sidebar, in order",
                        comment: "Keyboard shortcut")),
                .init(
                    keys: ["⌃⌘1…⌃⌘9"],
                    label: String(localized: "Switch account", comment: "Keyboard shortcut")),
                .init(
                    keys: ["⌘+", "⌘−", "⌘0"],
                    label: String(
                        localized: "Larger text, smaller text, actual size",
                        comment: "Keyboard shortcut")),
                .init(
                    keys: ["⌘↩"],
                    label: String(
                        localized: "Send what you are writing", comment: "Keyboard shortcut")),
                .init(
                    keys: ["⇧⌘M"],
                    label: String(localized: "Mini timeline", comment: "Keyboard shortcut")),
                .init(
                    keys: ["⌘/"],
                    label: String(localized: "Show these shortcuts", comment: "Keyboard shortcut")),
            ]
        #else
            return [
                .init(
                    keys: ["⌘N"],
                    label: String(localized: "Write a new post", comment: "Keyboard shortcut")),
                .init(
                    keys: ["⌘F"], label: String(localized: "Search", comment: "Keyboard shortcut")),
                .init(
                    keys: ["⌘↩"],
                    label: String(
                        localized: "Send what you are writing", comment: "Keyboard shortcut")),
                .init(
                    keys: ["⌘R"],
                    label: String(localized: "Refresh the timeline", comment: "Keyboard shortcut")),
                .init(
                    keys: ["⌘["], label: String(localized: "Go back", comment: "Keyboard shortcut")),
                .init(
                    keys: ["⇧⌘H"],
                    label: String(
                        localized: "Go to your home timeline", comment: "Keyboard shortcut")),
                .init(
                    keys: ["⌘1…⌘9"],
                    label: String(
                        localized: "The places in the sidebar, in order",
                        comment: "Keyboard shortcut")),
                .init(
                    keys: ["⌥⌘N"],
                    label: String(localized: "Open a new window", comment: "Keyboard shortcut")),
            ]
        #endif
    }

    /// The Mac's Post menu, which acts on the selected post.
    public static var post: [Entry] {
        #if os(macOS)
            return [
                .init(keys: ["⌘O"], label: String(localized: "Open", comment: "Keyboard shortcut")),
                .init(
                    keys: ["⇧⌘R"], label: String(localized: "Reply", comment: "Keyboard shortcut")),
                .init(
                    keys: ["⇧⌘B"], label: String(localized: "Boost", comment: "Keyboard shortcut")),
                .init(
                    keys: ["⇧⌘L"],
                    label: String(localized: "Favourite", comment: "Keyboard shortcut")),
                .init(
                    keys: ["⌘D"], label: String(localized: "Bookmark", comment: "Keyboard shortcut")
                ),
                .init(
                    keys: ["⇧⌘T"],
                    label: String(localized: "Translate", comment: "Keyboard shortcut")),
                .init(
                    keys: ["⇧⌘C"],
                    label: String(localized: "Copy link", comment: "Keyboard shortcut")),
                .init(
                    keys: ["⌥⌘O"],
                    label: String(localized: "Open in browser", comment: "Keyboard shortcut")),
            ]
        #else
            return []
        #endif
    }
}

/// The list of shortcuts, as a sheet. Reachable with `?` from a timeline and
/// from Settings, because a shortcut nobody can find is not a shortcut.
public struct ShortcutHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alohaPalette) private var palette

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                section(
                    Text("In a list of posts", comment: "Shortcut section"),
                    KeyboardShortcuts.timeline)
                section(
                    Text("Anywhere", comment: "Shortcut section"), KeyboardShortcuts.global)
                if !KeyboardShortcuts.post.isEmpty {
                    section(
                        Text("The selected post", comment: "Shortcut section"),
                        KeyboardShortcuts.post)
                }
            }
            .navigationTitle(Text("Keyboard shortcuts", comment: "Screen title"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", comment: "Sheet action")
                    }
                }
            }
        }
    }

    private func section(_ title: Text, _ entries: [KeyboardShortcuts.Entry]) -> some View {
        Section {
            ForEach(entries) { entry in
                HStack {
                    Text(entry.label)
                    Spacer()
                    HStack(spacing: AlohaMetrics.space1) {
                        ForEach(entry.keys, id: \.self) { key in
                            Text(verbatim: key)
                                .font(.footnote.monospaced().weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    palette.surfaceRaised,
                                    in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }
            }
        } header: {
            title
        }
    }
}
