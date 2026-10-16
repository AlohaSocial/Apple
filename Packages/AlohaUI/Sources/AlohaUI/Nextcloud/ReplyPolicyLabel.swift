// SPDX-License-Identifier: MIT

import AlohaModels
import SwiftUI

/// One reply audience, named the way the composer and the post menu both say
/// it — so "who can reply" reads the same wherever it is chosen.
struct ReplyPolicyLabel: View {
    let policy: ReplyPolicy

    var body: some View {
        Label {
            Self.title(policy)
        } icon: {
            Image(systemName: Self.symbol(policy))
        }
    }

    static func title(_ policy: ReplyPolicy) -> Text {
        switch policy {
        case .everyone: Text("Everyone", comment: "Who can reply")
        case .followers: Text("Your followers", comment: "Who can reply")
        case .following: Text("People you follow", comment: "Who can reply")
        case .mentioned: Text("Only people you mention", comment: "Who can reply")
        case .nobody: Text("Nobody", comment: "Who can reply")
        }
    }

    static func symbol(_ policy: ReplyPolicy) -> String {
        switch policy {
        case .everyone: "globe"
        case .followers: "person.2"
        case .following: "person.crop.circle.badge.checkmark"
        case .mentioned: "at"
        case .nobody: "nosign"
        }
    }
}
