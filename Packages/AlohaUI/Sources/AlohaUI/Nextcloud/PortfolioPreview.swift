// SPDX-License-Identifier: MIT
import AlohaModels
import Foundation

enum PortfolioPreview {
    static func canSave(_ settings: PortfolioSettings) -> Bool {
        // An incomplete private draft must never prevent unpublishing.
        guard settings.active, settings.source == .collection else { return true }
        return
            !(settings.collectionID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    static func applying(
        _ settings: PortfolioSettings, to page: PortfolioPage,
        fallbackTitle: String
    ) -> PortfolioPage {
        var draft = page
        draft.title = settings.title.isEmpty ? fallbackTitle : settings.title
        draft.intro = settings.intro.isEmpty ? nil : settings.intro
        draft.layout = settings.layout
        draft.showCaptions = settings.showCaptions
        draft.showPlaces = settings.showPlaces
        draft.showDates = settings.showDates
        draft.showAvatar = settings.showAvatar
        return draft
    }
}
