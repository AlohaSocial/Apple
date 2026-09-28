// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaModels

@Suite("Lossy decoding")
struct LossyDecodingTests {

    @Test("A page with one bad element decodes the rest")
    func lossyArrayDropsOnlyTheBadElement() throws {
        let json = """
            [
              {"shortcode": "one", "url": "https://example.test/1.png"},
              {"not_a_shortcode": true},
              {"shortcode": "three", "url": "https://example.test/3.png"}
            ]
            """.data(using: .utf8)!

        let decoded = try AlohaJSON.decoder.decode(LossyArray<CustomEmoji>.self, from: json)
        #expect(decoded.elements.count == 2)
        #expect(decoded.elements.map(\.shortcode) == ["one", "three"])
        #expect(decoded.failures.count == 1)
        #expect(decoded.failures[0].index == 1)
    }

    @Test("A bad element that is an array or object still advances the container")
    func lossyArrayHandlesNestedBadElements() throws {
        let json = """
            [
              {"shortcode": "ok", "url": "https://example.test/1.png"},
              [1, 2, {"deep": [3, 4]}],
              {"shortcode": "also_ok", "url": "https://example.test/2.png"}
            ]
            """.data(using: .utf8)!

        let decoded = try AlohaJSON.decoder.decode(LossyArray<CustomEmoji>.self, from: json)
        #expect(decoded.elements.map(\.shortcode) == ["ok", "also_ok"])
    }
}

@Suite("Flexible wire values")
struct FlexibleValueTests {

    struct Holder: Decodable {
        @FlexibleID var id: String
        @LenientURL var avatar: URL?
        @LenientBool var flag: Bool
        @LenientInt var count: Int
    }

    @Test("Ids decode from both strings and numbers")
    func idsAcceptBothForms() throws {
        let asString = #"{"id": "109374", "flag": true, "count": 3}"#.data(using: .utf8)!
        let asNumber = #"{"id": 109374, "flag": true, "count": 3}"#.data(using: .utf8)!

        #expect(try AlohaJSON.decoder.decode(Holder.self, from: asString).id == "109374")
        #expect(try AlohaJSON.decoder.decode(Holder.self, from: asNumber).id == "109374")
    }

    @Test("An empty avatar string is absence, not a failure")
    func emptyURLBecomesNil() throws {
        // Nextcloud Social can send "" here: Person::exportAsLocal() falls
        // through to a stored value that may be empty.
        let json = #"{"id": "1", "avatar": "", "flag": false, "count": 0}"#.data(using: .utf8)!
        let holder = try AlohaJSON.decoder.decode(Holder.self, from: json)
        #expect(holder.avatar == nil)
    }

    @Test("Absent keys fall back rather than throwing")
    func absentKeysUseZeroValues() throws {
        let json = #"{"id": "1"}"#.data(using: .utf8)!
        let holder = try AlohaJSON.decoder.decode(Holder.self, from: json)
        #expect(holder.avatar == nil)
        #expect(holder.flag == false)
        #expect(holder.count == 0)
    }

    @Test("Booleans and integers tolerate the forks' spellings")
    func lenientScalars() throws {
        let json = #"{"id": "1", "flag": 1, "count": "42"}"#.data(using: .utf8)!
        let holder = try AlohaJSON.decoder.decode(Holder.self, from: json)
        #expect(holder.flag == true)
        #expect(holder.count == 42)
    }
}

@Suite("Unknown enum cases")
struct UnknownCaseTests {

    @Test("An unrecognised notification type decodes rather than throwing")
    func unknownNotificationKind() throws {
        let raw = #""something.new""#.data(using: .utf8)!
        let kind = try AlohaJSON.decoder.decode(NotificationKind.self, from: raw)
        #expect(kind.isUnknown)
        #expect(kind.groups == false)
    }

    @Test("Visibility fails closed")
    func unknownVisibilityIsMostRestrictive() throws {
        let raw = #""local_only""#.data(using: .utf8)!
        let visibility = try AlohaJSON.decoder.decode(Visibility.self, from: raw)
        #expect(visibility.isUnknown)
        #expect(visibility.restrictiveness == Visibility.direct.restrictiveness)
        #expect(Visibility.mostRestrictive(.public, visibility) == visibility)
    }

    @Test("Sensitive media policy keeps PeerTube's three states under Mastodon's names")
    func sensitivePolicies() throws {
        #expect(SensitiveMediaPolicy(rawValue: "show_all")?.allowsAutomaticReveal == true)
        #expect(SensitiveMediaPolicy(rawValue: "default")?.drawsAtAll == true)
        #expect(SensitiveMediaPolicy(rawValue: "hide_all")?.drawsAtAll == false)
    }
}

@Suite("Dates")
struct DateParsingTests {

    @Test("All four forms the fediverse sends parse")
    func allForms() {
        #expect(DateParsing.parse("2026-09-20T12:34:56.789Z") != nil)
        #expect(DateParsing.parse("2026-09-20T12:34:56Z") != nil)
        #expect(DateParsing.parse("2026-09-20") != nil)
        // /api/v1/instance/activity keys each week by the unix time its Monday began.
        #expect(DateParsing.parse("1758326400") != nil)
        #expect(DateParsing.parse("not a date") == nil)
    }
}

@Suite("Instance payloads")
struct InstancePayloadTests {

    /// Found by live testing against mastodon.social: v1 spells the key
    /// `streaming_api`, Mastodon 4.x's v2 `configuration.urls` spells it
    /// `streaming`. Reading only one decides a server has no streaming when it
    /// does, and silently drops the app to polling.
    @Test("Both spellings of the streaming URL are read")
    func streamingURLSpellings() throws {
        let v2Modern = """
            {"domain":"m.test","configuration":{"urls":{"streaming":"wss://m.test/api/v1/streaming"}}}
            """.data(using: .utf8)!
        let v2Legacy = """
            {"domain":"m.test","configuration":{"urls":{"streaming_api":"wss://m.test/api/v1/streaming"}}}
            """.data(using: .utf8)!

        for payload in [v2Modern, v2Legacy] {
            let decoded = try AlohaJSON.decoder.decode(InstancePayload.V2.self, from: payload)
            #expect(InstanceDescription(v2: decoded).hasStreaming)
        }
    }

    /// Nextcloud Social sends `{}` and `""`, and both are deliberate signals
    /// rather than missing data (docs/02 §1).
    @Test("An empty urls object and empty vapid key mean no streaming and no push")
    func emptySignals() throws {
        let payload = """
            {"domain":"cloud.test","configuration":{"urls":{},"vapid":{"public_key":""}}}
            """.data(using: .utf8)!
        let described = InstanceDescription(
            v2: try AlohaJSON.decoder.decode(InstancePayload.V2.self, from: payload))

        #expect(described.hasStreaming == false)
        #expect(described.hasWebPush == false)
    }

    @Test("v1 and v2 produce the same limits from the same configuration")
    func limitsAgree() throws {
        let configuration = """
            "configuration":{"statuses":{"max_characters":5000,"max_media_attachments":4},
            "media_attachments":{"image_size_limit":10485760,"video_size_limit":2147483648}}
            """
        let v1 = try AlohaJSON.decoder.decode(
            InstancePayload.V1.self,
            from: "{\"uri\":\"cloud.test\",\(configuration)}".data(using: .utf8)!)
        let v2 = try AlohaJSON.decoder.decode(
            InstancePayload.V2.self,
            from: "{\"domain\":\"cloud.test\",\(configuration)}".data(using: .utf8)!)

        #expect(InstanceDescription(v1: v1).limits == InstanceDescription(v2: v2).limits)
        // Two different ceilings, because the server reads an image whole into
        // memory and copies a video a chunk at a time.
        #expect(InstanceDescription(v2: v2).limits.imageSizeLimit == 10 * 1024 * 1024)
        #expect(InstanceDescription(v2: v2).limits.videoSizeLimit == 2048 * 1024 * 1024)
        #expect(
            InstanceDescription(v2: v2).limits.sizeLimit(forMIMEType: "video/mp4")
                == 2048 * 1024 * 1024)
    }
}
