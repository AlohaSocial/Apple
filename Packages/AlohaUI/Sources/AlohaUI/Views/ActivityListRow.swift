// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import SwiftUI

/// One row of the activity list: a notification (or group), or the
/// "caught up" divider below the one the reader had already seen.
///
/// The list used to be an array of `AnyView` keyed by position, so every
/// arrival at the top renamed every row below it — SwiftUI rebuilt them all,
/// animated nothing, and lost each row's state. Each row is now named by what
/// it shows.
enum ActivityListRow<Item: Identifiable>: Identifiable where Item.ID == String {
    case item(Item)
    case caughtUp(after: String)

    var id: String {
        switch self {
        case .item(let item): "item-\(item.id)"
        case .caughtUp(let after): "caughtUp-\(after)"
        }
    }

    /// The items in order, with the divider after the one at `markerIndex`.
    static func rows(_ items: [Item], dividerAfter markerIndex: Int?, markerID: String?) -> [Self] {
        var rows = items.map(Self.item)
        if let markerIndex, let markerID, items.indices.contains(markerIndex) {
            rows.insert(.caughtUp(after: markerID), at: markerIndex + 1)
        }
        return rows
    }
}

/// A post's words as one plain line, from the rich-text cache.
///
/// The preview under an activity row parsed the post's HTML in the row's
/// body — on the main actor, every time the list was evaluated. This reserves
/// the line while the cache answers, so nothing below it moves.
struct StatusPlainPreview: View {
    let status: Status
    var lineLimit = 2

    @State private var text: String?

    var body: some View {
        Text(verbatim: text ?? " ")
            .lineLimit(lineLimit)
            .task(id: FilterCacheKey(status)) {
                text = await RichTextCache.shared.plainText(for: status)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
    }
}
