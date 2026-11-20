// SPDX-License-Identifier: MIT

import AlohaDesign
import SwiftUI

#if os(macOS)
    /// The Mac's Settings window: the sections down a sidebar, one pane at a
    /// time beside it, the way System Settings is laid out.
    ///
    /// It used to be the phone's form in a tab — sixteen sections in one
    /// scroll, in a window that could not be made taller, with rows that
    /// lead to other screens and had nowhere to lead. Every pane is still
    /// the shared form (`SettingsView`), showing one of its sections, so no
    /// setting is implemented twice; what the Mac adds is its own panes
    /// (`Pane`) and the layout around them.
    public struct SettingsWindowView: View {
        /// A pane the app target brings: the Mac's own switches, which the
        /// shared form does not have.
        public struct Pane: Identifiable {
            public let id: String
            let title: String
            let symbolName: String
            /// Words the search should find it by, besides its title.
            let keywords: String
            let content: AnyView

            public init(
                id: String, title: String, symbolName: String, keywords: String = "",
                @ViewBuilder content: () -> some View
            ) {
                self.id = id
                self.title = title
                self.symbolName = symbolName
                self.keywords = keywords
                self.content = AnyView(content())
            }
        }

        enum Selection: Hashable {
            case section(SettingsSection)
            case pane(String)

            /// How the pane is remembered between openings of the window.
            var stored: String {
                switch self {
                case .section(let section): "section:\(section)"
                case .pane(let id): "pane:\(id)"
                }
            }

            /// The pane stored, if it is still one there is: a pane the app
            /// no longer has opens Accounts instead.
            init?(stored: String, paneIDs: [String]) {
                if stored.hasPrefix("pane:") {
                    let id = String(stored.dropFirst("pane:".count))
                    guard paneIDs.contains(id) else { return nil }
                    self = .pane(id)
                } else if stored.hasPrefix("section:") {
                    let name = stored.dropFirst("section:".count)
                    guard
                        let section = SettingsSection.allCases.first(where: {
                            "\($0)" == name
                        })
                    else { return nil }
                    self = .section(section)
                } else {
                    return nil
                }
            }
        }

        @Environment(AppEnvironment.self) private var environment
        @Environment(\.alohaPalette) private var palette
        @Environment(\.openWindow) private var openWindow

        private let panes: [Pane]
        private let onAddAccount: () -> Void

        @State private var selection: Selection = .section(.accounts)
        /// The pane last shown: the window opens where it was left rather
        /// than on Accounts every time.
        @AppStorage(MacOptions.settingsPaneKey) private var storedSelection = ""
        @State private var query = ""
        /// What a row in a pane asked to open. Never shown here: see `open`.
        @State private var path: [Route] = []

        public init(panes: [Pane] = [], onAddAccount: @escaping () -> Void) {
            self.panes = panes
            self.onAddAccount = onAddAccount
        }

        public var body: some View {
            NavigationSplitView {
                List(selection: optionalSelection) {
                    group([.accounts, .yourAccount])
                    Section {
                        row(.appearance)
                        ForEach(panes.filter(matches)) { pane in
                            Label {
                                Text(verbatim: pane.title)
                            } icon: {
                                IconTile(
                                    pane.symbolName, isSelected: selection == .pane(pane.id),
                                    size: 24)
                            }
                            .tag(Selection.pane(pane.id))
                        }
                    }
                    group([.feeds, .timeline, .media, .posting, .content])
                    group([.notifications, .soundAndTouch, .intelligence, .nextcloud])
                    group([.storage, .moderation, .deleteAccount, .about])
                }
                .listStyle(.sidebar)
                .searchable(
                    text: $query, placement: .sidebar,
                    prompt: Text("Search", comment: "Settings search field")
                )
                .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 260)
                .toolbar(removing: .sidebarToggle)
            } detail: {
                NavigationStack(path: $path) {
                    detail
                        // The pane's own section header is its title; the
                        // window keeps the name "Settings".
                        .toolbar(removing: .title)
                        .navigationDestination(for: Route.self) { _ in Color.clear }
                }
            }
            .onChange(of: path) { _, path in
                if let route = path.last { open(route) }
            }
            .onChange(of: query) { _, _ in selectFirstMatchIfNeeded() }
            .onAppear {
                if let restored = Selection(stored: storedSelection, paneIDs: panes.map(\.id)) {
                    selection = restored
                }
            }
            .onChange(of: selection) { _, selection in storedSelection = selection.stored }
            .frame(
                minWidth: 660, idealWidth: 760, maxWidth: .infinity,
                minHeight: 420, idealHeight: 620, maxHeight: .infinity)
        }

        @ViewBuilder
        private var detail: some View {
            switch selection {
            case .section(let section):
                SettingsView(section: section, onAddAccount: onAddAccount)
                    // Each pane its own form: the state of one — a
                    // confirmation, a sheet — is not another's to inherit.
                    .id(section)
            case .pane(let id):
                if let pane = panes.first(where: { $0.id == id }) {
                    pane.content
                }
            }
        }

        /// The shared form's rows lead to screens the main window's shell
        /// builds — filters, drafts, the profile editor. A Settings window
        /// has no shell, so each opens in a window of its own, where it can
        /// stay beside the settings instead of replacing them.
        private func open(_ route: Route) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { path = [] }
            openWindow(value: route)
        }

        @ViewBuilder
        private func group(_ sections: [SettingsSection]) -> some View {
            let shown = sections.filter(isListed)
            if !shown.isEmpty {
                Section {
                    ForEach(shown, id: \.self) { row($0) }
                }
            }
        }

        @ViewBuilder
        private func row(_ section: SettingsSection) -> some View {
            if isListed(section) {
                Label {
                    Text(verbatim: section.title)
                } icon: {
                    IconTile(
                        section.tileSymbolName, isSelected: selection == .section(section),
                        size: 24)
                }
                .tag(Selection.section(section))
            }
        }

        private func isListed(_ section: SettingsSection) -> Bool {
            section.isAvailable(in: environment) && section.matches(query)
        }

        private func matches(_ pane: Pane) -> Bool {
            SettingsSection.matches(query, in: [pane.title, pane.keywords])
        }

        /// A search that hides the pane on screen moves to the first it finds,
        /// so what is beside the list is always something in the list.
        private func selectFirstMatchIfNeeded() {
            let isStillListed: Bool =
                switch selection {
                case .section(let section): isListed(section)
                case .pane(let id): panes.contains { $0.id == id && matches($0) }
                }
            guard !isStillListed else { return }
            if let section = SettingsSection.allCases.first(where: isListed) {
                selection = .section(section)
            } else if let pane = panes.first(where: matches) {
                selection = .pane(pane.id)
            }
        }

        private var optionalSelection: Binding<Selection?> {
            Binding(
                get: { selection },
                set: { if let value = $0 { selection = value } })
        }
    }
#endif
