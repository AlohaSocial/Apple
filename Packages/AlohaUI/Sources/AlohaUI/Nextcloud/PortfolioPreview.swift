import AlohaModels

enum PortfolioPreview {
    static func applying(_ settings: PortfolioSettings, to page: PortfolioPage,
        fallbackTitle: String) -> PortfolioPage {
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
