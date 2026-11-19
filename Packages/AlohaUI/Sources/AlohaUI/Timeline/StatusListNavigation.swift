// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

#if canImport(AppKit)
    import AppKit
#endif

// The keyboard in a list of posts, on the Mac: a selected row, moved with
// j/k and the arrow keys, opened with Return or a double click, paged with
// Space, previewed with ⇧Space or ⌘Y — every list of posts alike: timelines,
// Activities, threads, profiles, search results and each column of the Deck
// (docs/09 §2).
//
// It used to be a focus ring drawn by the timeline alone, on a list made
// focusable as a whole: nothing had the focus until somebody clicked, so j/k
// did nothing at first; a click opened the post instead of choosing it; and a
// ring is not a selection, so VoiceOver and Full Keyboard Access did not
// follow it. The selection is now the list's own (`SelectableList`), which
// is what both of them follow, and the list takes the focus when its window
// appears.

/// What a list of posts tells its rows about the keyboard's selection.
struct StatusListRowContext {
    var selectedID: String?
    var isFocused: Bool
    /// Whether the rows are a `List`, whose own selection a click makes and
    /// the arrow keys move; otherwise a stack the rows draw and click for.
    var isNativeList: Bool
    /// Whether a row in a stack is clicked to select and double-clicked to
    /// open; off where each row is a button that opens on a click already.
    var rowsTakeClicks: Bool
    var select: (String) -> Void
    var open: (String) -> Void
    var noteVisible: (String, Bool) -> Void
}

extension EnvironmentValues {
    /// Set by `statusListNavigation` for the rows of the list it navigates.
    @Entry var statusListRow: StatusListRowContext?
    /// Whether the rows are in a list whose selection a click makes: a row
    /// then leaves its single click to the list and opens on a double click
    /// or Return. Kept apart from `statusListRow`, which changes with every
    /// move, so that a post's own body is not drawn again on each one.
    @Entry var statusListSelects = false
    /// Whether that list also gives the rows' menu, as a selecting `List`
    /// does for the row a secondary click is on.
    @Entry var statusListOwnsMenu = false
    /// Whether a list takes the keyboard focus when it appears. Off where
    /// something else should have it: the search screen's field, the
    /// Deck's second and third columns, a post opened beside its list.
    @Entry var statusListTakesFocus = true
}

/// Where j and k go from here. A pure function, so the rules are tested
/// rather than tried by hand (`StatusListCursorTests`).
enum StatusListCursor {
    /// The row a move of `step` lands on.
    ///
    /// From nothing, or from a selection the reader has scrolled away from
    /// (Space pages without moving it), a move starts from what is on
    /// screen rather than jumping back to where the selection was left — the
    /// way Mail and NetNewsWire do. Neither end wraps.
    static func next(
        after selection: String?, step: Int, ids: [String], visible: Set<String>
    ) -> String? {
        guard !ids.isEmpty else { return nil }
        let onScreen = ids.filter { visible.contains($0) }
        guard let selection, let index = ids.firstIndex(of: selection) else {
            return step > 0 ? onScreen.first ?? ids.first : onScreen.last ?? ids.last
        }
        if !onScreen.isEmpty, !visible.contains(selection) {
            return step > 0 ? onScreen.first : onScreen.last
        }
        let next = index + step
        return ids.indices.contains(next) ? ids[next] : selection
    }
}

/// The rows a list has on screen, as they appear and go. A plain object, not
/// observed: nothing is drawn from it, and a row scrolling past must not
/// redraw the list.
@MainActor
private final class VisibleRows {
    var ids: Set<String> = []
}

/// Return and the list's double click can both arrive for one press; the
/// post opens once.
@MainActor
private final class OpenGuard {
    private var last: (id: String, at: Date)?

    func mayOpen(_ id: String, now: Date = .now) -> Bool {
        defer { last = (id, now) }
        guard let last, last.id == id else { return true }
        return now.timeIntervalSince(last.at) > 0.4
    }
}

/// A `List` whose rows can be selected on the Mac, and a plain one elsewhere,
/// where selecting a row is not how a touch screen reads.
struct SelectableList<Content: View>: View {
    @Binding var selection: String?
    @ViewBuilder var content: Content

    var body: some View {
        #if os(macOS)
            List(selection: $selection) { content }
        #else
            List { content }
        #endif
    }
}

private struct StatusListNavigation: ViewModifier {
    @Binding var selection: String?
    let ids: [String]
    let status: (String) -> Status?
    let onAction: (StatusRowAction) -> Void
    let open: ((String) -> Void)?
    let refresh: (() async -> Void)?
    let isNativeList: Bool
    let offersMenu: Bool
    let rowsAreButtons: Bool

    @Environment(\.statusListTakesFocus) private var takesFocus
    /// A Deck column: one of three lists in a window, which leaves the menu
    /// bar to whichever of them has the focus.
    @Environment(\.sharesToolbar) private var isDeckColumn
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var isShowingShortcuts = false
    @State private var visible = VisibleRows()
    @State private var openGuard = OpenGuard()

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            navigable(content, proxy: proxy)
        }
    }

    @ViewBuilder
    private func navigable(_ content: Content, proxy: ScrollViewProxy) -> some View {
        let context = StatusListRowContext(
            selectedID: selection, isFocused: isFocused, isNativeList: isNativeList,
            rowsTakeClicks: !rowsAreButtons,
            select: { id in
                selection = id
                isFocused = true
            },
            open: { openRow($0) },
            noteVisible: { [visible] id, isVisible in
                if isVisible { visible.ids.insert(id) } else { visible.ids.remove(id) }
            })
        let commands = commands(proxy: proxy)
        #if os(macOS)
            content
                .environment(\.statusListRow, context)
                .environment(\.statusListSelects, true)
                .environment(\.statusListOwnsMenu, isNativeList && offersMenu)
                .modifier(
                    ListMenu(
                        isNativeList: isNativeList, offersMenu: offersMenu, status: status,
                        onAction: onAction, open: { openRow($0) })
                )
                .focusable(!isNativeList)
                .focusEffectDisabled(!isNativeList)
                .focused($isFocused)
                .onAppear {
                    guard takesFocus else { return }
                    // A turn later: the list has to be in the window before
                    // it can be made its first responder.
                    Task { @MainActor in isFocused = true }
                }
                .onKeyPress(phases: [.down, .repeat]) { press in
                    handle(press, proxy: proxy)
                }
                .focusedValue(\.timelineCommands, commands)
                .modifier(SceneCommands(commands: isDeckColumn ? nil : commands))
                .sheet(isPresented: $isShowingShortcuts) { ShortcutHelpView() }
        #else
            // The iPad's menu bar reaches the list through the same commands
            // (`AlohaCommands`); a touch list has no focus to give.
            content
                .environment(\.statusListRow, context)
                .focusedSceneValue(\.timelineCommands, commands)
        #endif
    }

    // MARK: - Keys

    #if os(macOS)
        private func handle(_ press: KeyPress, proxy: ScrollViewProxy) -> KeyPress.Result {
            // ⌘, ⌃ and ⌥ combinations are the menu bar's.
            guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else {
                return .ignored
            }
            switch press.key {
            case .space:
                if press.modifiers.contains(.shift) {
                    act(.peek, proxy: proxy)
                } else {
                    page(proxy: proxy)
                }
                return .handled
            case .return:
                guard let selection else { return .ignored }
                openRow(selection)
                return .handled
            case .downArrow, .upArrow:
                // A `List` moves its own selection, and scrolls to it.
                guard !isNativeList else { return .ignored }
                move(by: press.key == .downArrow ? 1 : -1, proxy: proxy)
                return .handled
            case .home, .end:
                guard !isNativeList, let target = press.key == .home ? ids.first : ids.last
                else { return .ignored }
                selection = target
                proxy.scrollTo(target, anchor: press.key == .home ? .top : .bottom)
                return .handled
            default:
                break
            }
            switch press.characters.lowercased() {
            case "j": move(by: 1, proxy: proxy)
            case "k": move(by: -1, proxy: proxy)
            case "l", "f": act(.favourite, proxy: proxy)
            case "b": act(.boost, proxy: proxy)
            case "r": act(.reply, proxy: proxy)
            case "o": act(.open, proxy: proxy)
            case "?", "/": isShowingShortcuts = true
            default: return .ignored
            }
            return .handled
        }

        /// Space reads on, a page at a time, as NetNewsWire's does, without
        /// moving the selection: j and k then carry on from what is on screen
        /// (`StatusListCursor`).
        private func page(proxy: ScrollViewProxy) {
            // A `List` is a table in a scroll view, and the scroll view pages
            // itself exactly as Page Down does.
            if isNativeList,
                NSApplication.shared.sendAction(
                    #selector(NSResponder.scrollPageDown(_:)), to: nil, from: nil)
            {
                return
            }
            guard let lastOnScreen = ids.last(where: { visible.ids.contains($0) }) else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                proxy.scrollTo(lastOnScreen, anchor: .top)
            }
        }
    #endif

    private func move(by step: Int, proxy: ScrollViewProxy) {
        guard
            let next = StatusListCursor.next(
                after: selection, step: step, ids: ids, visible: visible.ids)
        else { return }
        selection = next
        // No anchor: the least scroll that shows the row, as the arrow keys
        // scroll a list.
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
            proxy.scrollTo(next)
        }
    }

    private func openRow(_ id: String) {
        guard openGuard.mayOpen(id) else { return }
        if let open {
            open(id)
        } else if let status = status(id) {
            onAction(.open(status))
        }
    }

    private func act(_ action: TimelineCommands.Action, proxy: ScrollViewProxy) {
        guard let id = selection, let status = status(id) else { return }
        switch action {
        case .favourite: onAction(.favourite(status))
        case .boost: onAction(.boost(status))
        case .reply: onAction(.reply(status))
        case .bookmark: onAction(.bookmark(status))
        case .translate: onAction(.translate(status))
        case .peek: onAction(.peek(status))
        case .open: openRow(id)
        case .copyLink:
            if let url = PostLinks.address(of: status) { PostLinks.copy(url) }
        case .openInBrowser:
            if let url = PostLinks.address(of: status) { PostLinks.openInBrowser(url) }
        }
    }

    private func commands(proxy: ScrollViewProxy) -> TimelineCommands {
        var commands = TimelineCommands(
            move: { move(by: $0, proxy: proxy) },
            act: { act($0, proxy: proxy) },
            refresh: {
                guard let refresh else { return }
                Task { await refresh() }
            },
            hasFocusedPost: selection.flatMap(status) != nil)
        commands.canRefresh = refresh != nil
        return commands
    }
}

#if os(macOS)
    /// The post menu and the double click, for the list as a whole: a `List`
    /// that selects decides what a secondary click is on, and Return and a
    /// double click are its primary action.
    private struct ListMenu: ViewModifier {
        let isNativeList: Bool
        let offersMenu: Bool
        let status: (String) -> Status?
        let onAction: (StatusRowAction) -> Void
        let open: (String) -> Void

        func body(content: Content) -> some View {
            if isNativeList {
                content.contextMenu(forSelectionType: String.self) { ids in
                    if offersMenu, ids.count == 1, let id = ids.first, let status = status(id) {
                        StatusMenu(status: status, onAction: onAction)
                    }
                } primaryAction: { ids in
                    if let id = ids.first { open(id) }
                }
            } else {
                content
            }
        }
    }

    /// The commands again for the window as a whole, for when the focus is
    /// outside the list — or not at all, in a Deck column.
    private struct SceneCommands: ViewModifier {
        let commands: TimelineCommands?

        func body(content: Content) -> some View {
            if let commands {
                content.focusedSceneValue(\.sceneTimelineCommands, commands)
            } else {
                content
            }
        }
    }
#endif

/// One row of a navigated list: its tag for the list's selection, the
/// selection's highlight, and — in a stack — the clicks a `List` would take.
private struct StatusListRowModifier: ViewModifier {
    @Environment(\.statusListRow) private var list
    @Environment(\.alohaPalette) private var palette

    let id: String
    /// The ground a `List` row is drawn on; nil for a row in a stack.
    let ground: Color?

    func body(content: Content) -> some View {
        let isSelected = list?.selectedID == id
        let highlight = highlight(isSelected: isSelected)
        rowClicks(
            content
                .tag(id)
                .modifier(RowGround(ground: ground, highlight: highlight))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .onAppear { list?.noteVisible(id, true) }
                .onDisappear { list?.noteVisible(id, false) }
        )
    }

    /// The theme's accent, lightly, rather than the system's selection
    /// colour: a post is drawn in the theme's own label colours, and the
    /// system's emphasised blue under them would leave grey on blue. Strong
    /// while the list has the focus, quiet when it does not, as a Mac list's
    /// selection is.
    private func highlight(isSelected: Bool) -> Color? {
        guard isSelected, let list else { return nil }
        return list.isFocused ? palette.accent.opacity(0.16) : palette.label.opacity(0.07)
    }

    @ViewBuilder
    private func rowClicks(_ row: some View) -> some View {
        #if os(macOS)
            if let list, !list.isNativeList, list.rowsTakeClicks {
                row
                    .onTapGesture(count: 2) { list.open(id) }
                    .simultaneousGesture(TapGesture().onEnded { list.select(id) })
            } else {
                row
            }
        #else
            row
        #endif
    }
}

private struct RowGround: ViewModifier {
    let ground: Color?
    let highlight: Color?

    func body(content: Content) -> some View {
        if let ground {
            content.listRowBackground(
                ZStack {
                    ground
                    if let highlight { highlight }
                })
        } else {
            content.background {
                if let highlight {
                    RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
                        .fill(highlight)
                        .padding(.horizontal, -AlohaMetrics.space2)
                }
            }
        }
    }
}

extension View {
    /// The Mac's keyboard for a list of posts (see the top of this file).
    ///
    /// - Parameters:
    ///   - selection: The list's selection, shared with `SelectableList`.
    ///   - ids: The selectable rows, in order.
    ///   - status: The post a row shows, for the actions; nil for a row that
    ///     is not a post.
    ///   - open: What opening a row does, where it is not opening its post.
    ///   - refresh: What ⌘R does.
    ///   - isNativeList: Whether the rows are a `SelectableList`.
    ///   - offersMenu: Whether a secondary click on a row gives the post menu.
    ///   - rowsAreButtons: Whether each row opens on a click by itself, so
    ///     the list adds no clicks of its own.
    func statusListNavigation(
        selection: Binding<String?>,
        ids: [String],
        status: @escaping (String) -> Status?,
        onAction: @escaping (StatusRowAction) -> Void,
        open: ((String) -> Void)? = nil,
        refresh: (() async -> Void)? = nil,
        isNativeList: Bool = true,
        offersMenu: Bool = true,
        rowsAreButtons: Bool = false
    ) -> some View {
        modifier(
            StatusListNavigation(
                selection: selection, ids: ids, status: status, onAction: onAction, open: open,
                refresh: refresh, isNativeList: isNativeList, offersMenu: offersMenu,
                rowsAreButtons: rowsAreButtons))
    }

    /// One row of a list with `statusListNavigation`. `ground` is the
    /// `listRowBackground` the row had; nil for a row in a stack.
    func statusListRow(_ id: String, ground: Color?) -> some View {
        modifier(StatusListRowModifier(id: id, ground: ground))
    }
}

extension View {
    /// `refreshable`, and ⌘R for it on the Mac: View ▸ Refresh reaches every
    /// screen that can be pulled to refresh, not only the lists of posts
    /// (`RefreshCommand`).
    func alohaRefreshable(action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        #if os(macOS)
            refreshable(action: action)
                .focusedSceneValue(\.refreshCommand, RefreshCommand { Task { await action() } })
        #else
            refreshable(action: action)
        #endif
    }
}
