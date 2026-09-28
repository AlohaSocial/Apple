// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaModels

@Suite struct VideoChaptersTests {
    @Test func aChapterListInADescriptionIsParsed() {
        let text = """
            A talk about the thing.

            0:00 Intro
            1:02 - The first part
            01:02:03 – Much later
            Thanks for watching!
            """
        let chapters = VideoChapters.parse(from: text)
        #expect(chapters.map(\.start) == [0, 62, 3723])
        #expect(chapters.map(\.title) == ["Intro", "The first part", "Much later"])
    }

    @Test func aSingleTimestampIsNotAChapterList() {
        // "See 1:02 for the demo" is a reference; one stamp makes no table.
        #expect(VideoChapters.parse(from: "1:02 the demo\nand nothing else").isEmpty)
    }

    @Test func outOfOrderStampsAreMentionsNotChapters() {
        let text = "0:00 Start\n5:00 Middle\n2:30 (back to the earlier point)\n9:00 End"
        #expect(VideoChapters.parse(from: text).map(\.start) == [0, 300, 540])
    }

    @Test func clocksRoundTrip() {
        #expect(VideoChapters.seconds(from: "1:02") == 62)
        #expect(VideoChapters.seconds(from: "01:02:03") == 3723)
        #expect(VideoChapters.seconds(from: "1:75") == nil)
        #expect(VideoChapters.seconds(from: "12") == nil)
        #expect(VideoChapters.clock(62) == "1:02")
        #expect(VideoChapters.clock(3723) == "1:02:03")
    }

    @Test func serverChaptersDecodeFromSecondsOrClocks() throws {
        let json = #"""
            {"video": {"views": "1200", "live": 0, "download": false,
                       "category": {"id": 1, "label": "Music"},
                       "chapters": [{"start": 0, "title": "A"}, {"start": "1:30", "title": "B"}]},
             "dislikes_count": 3, "disliked": true}
            """#
        let extras = try AlohaJSON.decoder.decode(VideoStatusExtras.self, from: Data(json.utf8))
        #expect(extras.video?.views == 1200)
        #expect(extras.video?.live == false)
        #expect(extras.video?.download == false)
        #expect(extras.video?.category == "Music")
        #expect(extras.video?.chapters.map(\.start) == [0, 90])
        #expect(extras.dislikesCount == 3)
        #expect(extras.disliked == true)
    }

    @Test func aStatusWithoutVideoKeysStillDecodes() throws {
        let extras = try AlohaJSON.decoder.decode(
            VideoStatusExtras.self, from: Data(#"{"id": "1", "content": "<p>hi</p>"}"#.utf8))
        #expect(extras.video == nil)
        #expect(extras.dislikesCount == nil)
    }
}
