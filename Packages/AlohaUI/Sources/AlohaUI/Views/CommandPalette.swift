// SPDX-License-Identifier: MIT

import AlohaDesign
import SwiftUI

#if os(macOS)
    /// ⌘K: type where to go, press Return.
    ///
    /// Every place in the sidebar, the screens that live in the account menu
    /// and a search for whatever was typed, in one field — the quickest way
    /// across an app for somebody whose hands are already on the keyboard.
    struct CommandPalette: View {
        struct Item: Identifiable, Hashable {
            let id: String
            let title: String
            let symbolName: String
            let route: Route
        }

        @Environment(\.alohaPalette) private var palette

        let items: [Item]
        let onOpen: (Route) -> Void
        let onClose: () -> Void

        @State private var query = ""
        @State private var highlighted = 0
        @FocusState private var isFieldFocused: Bool

        private var matches: [Item] {
            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            var found = items.filter {
                needle.isEmpty
                    || $0.title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive])
                        != nil
            }
            if !needle.isEmpty {
                found.append(
                    Item(
                        id: "search", title: String(localized: "Search for “\(needle)”", comment: "Command palette item"),
                        symbolName: AlohaSymbol.search, route: .search(query: needle)))
            }
            return found
        }

        var body: some View {
            ZStack(alignment: .top) {
                // A click anywhere else puts it away.
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onClose)

                VStack(spacing: 0) {
                    HStack(spacing: AlohaMetrics.space2) {
                        Image(systemName: "command")
                            .foregroundStyle(palette.secondaryLabel)
                        TextField(
                            text: $query,
                            prompt: Text("Go to…", comment: "Command palette field")
                        ) {
                            Text("Go to", comment: "Command palette field")
                        }
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($isFieldFocused)
                        .onSubmit(openHighlighted)
                    }
                    .padding(AlohaMetrics.space3)

                    Divider()

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(Array(matches.enumerated()), id: \.element.id) { index, item in
                                    row(item, isHighlighted: index == highlighted)
                                        .id(item.id)
                                        .onTapGesture { open(item) }
                                        .onHover { if $0 { highlighted = index } }
                                }
                            }
                            .padding(AlohaMetrics.space2)
                        }
                        .frame(maxHeight: 340)
                        .onChange(of: highlighted) { _, index in
                            guard matches.indices.contains(index) else { return }
                            proxy.scrollTo(matches[index].id)
                        }
                    }
                }
                .frame(width: 520)
                .background(.regularMaterial, in: panel)
                .overlay(panel.strokeBorder(palette.separator.opacity(0.5), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
                .padding(.top, 90)
            }
            .onAppear { isFieldFocused = true }
            .onChange(of: query) { _, _ in highlighted = 0 }
            .onKeyPress(.downArrow) {
                highlighted = min(highlighted + 1, max(matches.count - 1, 0))
                return .handled
            }
            .onKeyPress(.upArrow) {
                highlighted = max(highlighted - 1, 0)
                return .handled
            }
            .onExitCommand(perform: onClose)
            .transition(.opacity)
        }

        private var panel: RoundedRectangle {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
        }

        private func row(_ item: Item, isHighlighted: Bool) -> some View {
            HStack(spacing: AlohaMetrics.space3) {
                Image(systemName: item.symbolName)
                    .frame(width: 22)
                    .foregroundStyle(isHighlighted ? palette.onAccent : palette.secondaryLabel)
                Text(verbatim: item.title)
                    .foregroundStyle(isHighlighted ? palette.onAccent : palette.label)
                Spacer()
            }
            .padding(.horizontal, AlohaMetrics.space3)
            .padding(.vertical, AlohaMetrics.space2)
            .background(
                isHighlighted ? AnyShapeStyle(palette.accent) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous)
            )
            .contentShape(Rectangle())
        }

        private func openHighlighted() {
            guard matches.indices.contains(highlighted) else { return }
            open(matches[highlighted])
        }

        private func open(_ item: Item) {
            onClose()
            onOpen(item.route)
        }
    }
#endif
