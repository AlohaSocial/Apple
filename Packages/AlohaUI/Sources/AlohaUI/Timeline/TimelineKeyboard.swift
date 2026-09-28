// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

/// Every keyboard shortcut the app has, in one list — which is what makes the
/// help sheet honest: it is generated from the same table the timeline reads,
/// so a shortcut cannot be documented without existing or exist undocumented.
///
/// Nextcloud Social's `services/shortcuts.js` and `ShortcutHelp.vue`, with the
/// same letters where the app can offer them. The two ⌘ ones are this app's,
/// because a Mac window has a menu bar and the web page does not.
public enum KeyboardShortcuts {
    public struct Entry: Identifiable, Sendable, Hashable {
        public var id: String { keys.joined(separator: "/") + label }
        /// Shown as written: "J", "⌘N", "?".
        public var keys: [String]
        public var label: String
    }

    /// The single keys, which work while a timeline has keyboard focus and
    /// nobody is typing.
    public static var timeline: [Entry] {
        [
            .init(keys: ["J"], label: String(localized: "Next post", comment: "Keyboard shortcut")),
            .init(
                keys: ["K"], label: String(localized: "Previous post", comment: "Keyboard shortcut")
            ),
            .init(
                keys: ["L", "F"],
                label: String(localized: "Like the post in focus", comment: "Keyboard shortcut")),
            .init(
                keys: ["B"],
                label: String(localized: "Boost the post in focus", comment: "Keyboard shortcut")),
            .init(
                keys: ["R"],
                label: String(localized: "Reply to the post in focus", comment: "Keyboard shortcut")
            ),
            .init(
                keys: ["O", "↩"],
                label: String(localized: "Open the post in focus", comment: "Keyboard shortcut")),
            .init(
                keys: ["?"],
                label: String(localized: "Show these shortcuts", comment: "Keyboard shortcut")),
        ]
    }

    /// The ones that work anywhere in the window.
    public static var global: [Entry] {
        [
            .init(
                keys: ["⌘N"],
                label: String(localized: "Write a new post", comment: "Keyboard shortcut")),
            .init(
                keys: ["⌘F"], label: String(localized: "Search", comment: "Keyboard shortcut")),
            .init(
                keys: ["⌘↩"],
                label: String(localized: "Send what you are writing", comment: "Keyboard shortcut")),
        ]
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
                    Text("In a timeline", comment: "Shortcut section"),
                    KeyboardShortcuts.timeline)
                section(
                    Text("Anywhere", comment: "Shortcut section"), KeyboardShortcuts.global)
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

// MARK: - The timeline's keys

/// Moves a focus ring through a list of posts and acts on the one in focus.
///
/// Keys without a modifier, the way the web does it, and with the same guard:
/// they only fire while the list itself has keyboard focus, so a letter typed
/// into a search field or the composer is a letter and not a command.
struct TimelineKeyboardModifier: ViewModifier {
    @Binding var focusedID: String?
    @Binding var isShowingShortcuts: Bool

    let ids: [String]
    let status: (String) -> Status?
    let onAction: (StatusRowAction) -> Void

    func body(content: Content) -> some View {
        // macOS only. `.focusable()` is what makes `onKeyPress` fire, and on
        // iOS it also makes the whole list one focusable, activatable element:
        // it changed hit-testing enough to break two touch tours, and it puts
        // a container in the accessibility tree that VoiceOver then has to be
        // driven through. A Mac always has the keyboard these shortcuts are
        // for; a phone does not, and an iPad with one still has the touch
        // target it had before.
        #if os(macOS)
            content
                .focusable()
                .onKeyPress(characters: .alphanumerics.union(.punctuationCharacters)) { press in
                    handle(press.characters.lowercased()) ? .handled : .ignored
                }
                .onKeyPress(.return) {
                    guard let focused = focusedID, let status = status(focused) else {
                        return .ignored
                    }
                    onAction(.open(status))
                    return .handled
                }
        #else
            content
        #endif
    }

    private func handle(_ key: String) -> Bool {
        switch key {
        case "j": move(by: 1)
        case "k": move(by: -1)
        case "l", "f": act { .favourite($0) }
        case "b": act { .boost($0) }
        case "r": act { .reply($0) }
        case "o": act { .open($0) }
        case "?", "/": isShowingShortcuts = true
        default: return false
        }
        return true
    }

    private func move(by step: Int) {
        guard !ids.isEmpty else { return }
        guard let focused = focusedID, let index = ids.firstIndex(of: focused) else {
            focusedID = step > 0 ? ids.first : ids.last
            return
        }
        let next = index + step
        guard ids.indices.contains(next) else { return }
        focusedID = ids[next]
    }

    private func act(_ make: (Status) -> StatusRowAction) {
        guard let focused = focusedID, let status = status(focused) else { return }
        onAction(make(status))
    }
}

extension View {
    /// `j`/`k` to move, `l`/`b`/`r`/`o` to act, `?` for the list of them.
    func timelineKeyboard(
        focusedID: Binding<String?>,
        isShowingShortcuts: Binding<Bool>,
        ids: [String],
        status: @escaping (String) -> Status?,
        onAction: @escaping (StatusRowAction) -> Void
    ) -> some View {
        modifier(
            TimelineKeyboardModifier(
                focusedID: focusedID, isShowingShortcuts: isShowingShortcuts,
                ids: ids, status: status, onAction: onAction))
    }
}
