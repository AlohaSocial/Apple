import AlohaModels
import Testing
@testable import AlohaUI

@Suite("Portfolio draft preview")
struct PortfolioPreviewTests {
    @Test("Unsaved presentation changes replace the published presentation")
    func draftSettings() {
        let published = PortfolioPage(title: "Published", intro: "Old", handle: "@alice")
        let settings = PortfolioSettings(title: "Draft", intro: "New", layout: .rows,
            showCaptions: false, showPlaces: false, showDates: false, showAvatar: false)
        let draft = PortfolioPreview.applying(settings, to: published, fallbackTitle: "Alice")
        #expect(draft.title == "Draft" && draft.intro == "New" && draft.layout == .rows)
        #expect(!draft.showCaptions && !draft.showPlaces && !draft.showDates && !draft.showAvatar)
        #expect(draft.handle == published.handle && draft.posts == published.posts)
        #expect(published.title == "Published")
    }

    @Test("Clearing title and introduction respects the draft defaults")
    func clearedFields() {
        let draft = PortfolioPreview.applying(PortfolioSettings(),
            to: PortfolioPage(title: "Published", intro: "Old"), fallbackTitle: "Alice")
        #expect(draft.title == "Alice")
        #expect(draft.intro == nil)
    }
}
