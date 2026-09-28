// SPDX-License-Identifier: MIT

import AlohaModels

/// Where each action is answered.
///
/// Exists so the compiler and the tests can both see that nothing falls
/// through. Six actions used to reach a `default:` and silently do nothing —
/// block and mute among them, which App Review requires to work (docs/11 §1.3).
public enum StatusActionRouting {
    public enum Destination: Sendable, Hashable {
        /// Handled by the shell, because it presents something or navigates.
        case shell
        /// Handled by `StatusActions`, because it is a server call.
        case actions
        case unhandled
    }

    public static func destination(of action: StatusRowAction) -> Destination {
        switch action {
        case .open, .watch, .openProfile, .openMedia, .openCard, .followLink,
            .reply, .report, .share, .translate, .edit, .delete, .block, .mute,
            .quote, .showDelivery, .showEditHistory, .quoteControls, .tagPeople,
            .addToCollection, .addToList:
            .shell
        case .boost, .favourite, .bookmark, .muteConversation, .vote, .react,
            .archive, .pin, .dislike:
            .actions
        }
    }
}
