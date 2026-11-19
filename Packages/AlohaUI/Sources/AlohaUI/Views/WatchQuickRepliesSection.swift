// SPDX-License-Identifier: MIT

import AlohaNetwork
import SwiftUI

#if os(iOS)
    import WatchConnectivity

    /// The watch's quick replies, edited where there is a keyboard (docs/09 §4).
    ///
    /// A device setting rather than an account's, like the Live Activities
    /// switch: the watch on this wrist is one place, whichever account is
    /// active. Until somebody edits the list the watch uses its built-in set,
    /// and "Use the suggested replies" goes back to it — so a translation of
    /// the built-in set reaches people who never touched this.
    struct WatchQuickRepliesSection: View {
        private struct Phrase: Identifiable, Equatable {
            let id = UUID()
            var text: String
        }

        @State private var phrases: [Phrase] = WatchQuickReplies.current().map {
            Phrase(text: $0)
        }
        @State private var isCustom = WatchQuickReplies.stored() != nil
        @State private var pendingSave: Task<Void, Never>?

        var body: some View {
            if Self.mayHaveWatch {
                Section {
                    ForEach($phrases) { $phrase in
                        TextField(text: $phrase.text) {
                            Text("Quick reply", comment: "Placeholder for a watch quick reply")
                        }
                    }
                    .onDelete { phrases.remove(atOffsets: $0) }

                    if phrases.count < WatchQuickReplies.limit {
                        Button {
                            phrases.append(Phrase(text: ""))
                        } label: {
                            Label {
                                Text("Add a quick reply", comment: "Settings button")
                            } icon: {
                                Image(systemName: "plus")
                            }
                        }
                    }
                    if isCustom {
                        Button {
                            restoreSuggestions()
                        } label: {
                            Text("Use the suggested replies", comment: "Settings button")
                        }
                    }
                } header: {
                    Text("Apple Watch quick replies", comment: "Settings section")
                } footer: {
                    Text(
                        "Up to \(WatchQuickReplies.limit) short replies, shown above the reply field on your Apple Watch. Tapping one puts it in the reply; it is sent when you tap Send.",
                        comment: "Explanation of the watch quick replies setting")
                }
                // Typing changes the list a letter at a time; the watch gets
                // it once the typing pauses, not at every keystroke.
                .onChange(of: phrases) { _, _ in
                    pendingSave?.cancel()
                    pendingSave = Task {
                        try? await Task.sleep(for: .seconds(1))
                        guard !Task.isCancelled else { return }
                        save()
                    }
                }
                .onDisappear {
                    pendingSave?.cancel()
                    save()
                }
            }
        }

        /// iPad has no watch, and a phone that has activated its session
        /// knows whether it has one; one that has not yet is given the
        /// benefit of the doubt.
        private static var mayHaveWatch: Bool {
            guard WCSession.isSupported() else { return false }
            let session = WCSession.default
            return session.activationState != .activated || session.isPaired
        }

        private func save() {
            let clean = WatchQuickReplies.sanitized(phrases.map(\.text))
            let stored = WatchQuickReplies.stored()
            // Opening the list is not editing it: the built-in set stays
            // built in, and follows the language it is translated into.
            if stored == nil && clean == WatchQuickReplies.builtIn { return }
            guard clean != stored else { return }
            WatchQuickReplies.store(clean)
            isCustom = true
            WatchBridge.shared.quickRepliesChanged()
        }

        private func restoreSuggestions() {
            pendingSave?.cancel()
            WatchQuickReplies.store(nil)
            isCustom = false
            phrases = WatchQuickReplies.builtIn.map { Phrase(text: $0) }
            WatchBridge.shared.quickRepliesChanged()
        }
    }
#endif
