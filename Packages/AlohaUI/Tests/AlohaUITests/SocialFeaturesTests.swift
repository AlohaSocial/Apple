// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaUI

@Suite("Made with AI")
struct AIGeneratedLabelTests {
    @Test("The switch adds the server's hashtag once, after the text")
    func appends() {
        #expect(
            ComposerModel.labelledAsAIGenerated("A sunset\n")
                == "A sunset\n\n#AIgenerated")
        #expect(ComposerModel.labelledAsAIGenerated("") == "#AIgenerated")
    }

    @Test(
        "A post that already says so is left alone",
        arguments: ["Look #AIgenerated", "#madewithai art", "drawn with #GenAI"])
    func alreadyLabelled(_ text: String) {
        #expect(ComposerModel.labelledAsAIGenerated(text) == text)
    }

    @Test("A word that only contains the tag is not the tag")
    func notATag() {
        #expect(
            ComposerModel.labelledAsAIGenerated("#aimless")
                == "#aimless\n\n#AIgenerated")
    }
}
