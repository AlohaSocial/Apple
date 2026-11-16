// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

#if os(macOS)
    /// Direct messages on the Mac: the conversations down the left, the one
    /// being read beside them, the way Messages and Mail are laid out.
    ///
    /// On a phone a conversation is pushed over the list, because there is
    /// room for one of them. A Mac window pushed the same way showed a list a
    /// third of the window wide in the middle of nothing, and then replaced
    /// it. Both views are the ones every platform uses; only where the
    /// conversation opens differs.
    struct ConversationsSplitView: View {
        @Environment(\.alohaPalette) private var palette

        let session: AccountSession
        let onAction: (StatusRowAction) -> Void

        @State private var selected: Conversation?

        var body: some View {
            HStack(spacing: 0) {
                ConversationsView(session: session, onAction: onAction) { route in
                    if case .conversation(let conversation) = route { selected = conversation }
                }
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 380)

                Divider().ignoresSafeArea()

                Group {
                    if let selected {
                        ConversationThreadView(
                            conversation: selected, session: session, onAction: onAction
                        )
                        // A different conversation is a different screen: its
                        // messages and its draft are not the last one's.
                        .id(selected.id)
                    } else {
                        ContentUnavailableView {
                            Label {
                                Text(
                                    "No conversation selected",
                                    comment: "Direct messages placeholder")
                            } icon: {
                                Image(systemName: AlohaSymbol.directMessage)
                            }
                        } description: {
                            Text(
                                "Choose a conversation on the left, or start a new one.",
                                comment: "Direct messages placeholder detail")
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.background)
            }
        }
    }
#endif
