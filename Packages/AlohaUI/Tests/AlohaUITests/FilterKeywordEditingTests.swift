// SPDX-License-Identifier: MIT
import Testing

@testable import AlohaUI

@Suite("Filter keyword editing")
struct FilterKeywordEditingTests {
    @Test("A delayed edit to a removed keyword does not overwrite another row")
    func removedKeyword() {
        var removed = FilterDraft.Keyword(serverID: "old", text: "old", wholeWord: false)
        let retained = FilterDraft.Keyword(serverID: "kept", text: "kept", wholeWord: true)
        removed.text = "late edit"
        #expect(FilterEditorView.replacing(removed, in: [retained]) == [retained])
        #expect(FilterEditorView.replacing(removed, in: []).isEmpty)
    }

    @Test("A reordered keyword is edited by identity, not its old array position")
    func reorderedKeyword() {
        let first = FilterDraft.Keyword(serverID: "first", text: "first", wholeWord: false)
        var second = FilterDraft.Keyword(serverID: "second", text: "second", wholeWord: false)
        let original = [second, first]
        second.text = "updated"
        second.wholeWord = true
        let result = FilterEditorView.replacing(second, in: original)
        #expect(result[0] == second)
        #expect(result[1] == first)
    }
}
