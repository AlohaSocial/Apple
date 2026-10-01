// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaModels

@Suite("Media meta")
struct MediaMetaTests {
    private func attachment(meta: String) throws -> MediaAttachment {
        let json = """
            {"id": "1", "type": "video", "url": "https://example.com/v.mp4",
             "preview_url": null, "remote_url": null, "meta": \(meta)}
            """
        return try AlohaJSON.decoder.decode(MediaAttachment.self, from: Data(json.utf8))
    }

    @Test("A numeric frame rate keeps the rest of the meta")
    func numericFrameRate() throws {
        // Nextcloud's AttachmentMetaDim serialises frame_rate as a float.
        let media = try attachment(
            meta:
                #"{"original": {"width": 1080, "height": 1920, "frame_rate": 29.97, "duration": 12.5}}"#
        )
        #expect(media.meta?.original?.width == 1080)
        #expect(media.aspectRatio == 1080.0 / 1920.0)
        #expect(media.duration == 12.5)
        #expect(media.meta?.original?.frameRate == "29.97")
    }

    @Test("Mastodon's fractional frame-rate string still decodes")
    func stringFrameRate() throws {
        let media = try attachment(meta: #"{"original": {"frame_rate": "30/1", "width": 640}}"#)
        #expect(media.meta?.original?.frameRate == "30/1")
        #expect(media.meta?.original?.width == 640)
    }

    @Test("A local upload's top-level duration is the duration")
    func topLevelDuration() throws {
        let media = try attachment(
            meta: #"{"duration": 8, "original": {"width": 720, "height": 1280}}"#)
        #expect(media.duration == 8)
    }

    @Test("Mastodon's duration under original wins over the top level")
    func originalDurationFirst() throws {
        let media = try attachment(meta: #"{"duration": 8, "original": {"duration": 9.25}}"#)
        #expect(media.duration == 9.25)
    }

    @Test("One malformed field costs that field only")
    func malformedField() throws {
        let media = try attachment(
            meta: #"{"original": {"width": "wide", "height": 1280, "aspect": 0.5625}}"#)
        #expect(media.meta?.original?.width == nil)
        #expect(media.meta?.original?.height == 1280)
        #expect(media.aspectRatio == 0.5625)
    }
}

@Suite("Account header")
struct AccountHeaderTests {
    private func account(avatar: String, header: String) throws -> Account {
        let json = """
            {"id": "1", "username": "alice", "acct": "alice", "avatar": "\(avatar)",
             "avatar_static": "\(avatar)", "header": "\(header)", "header_static": "\(header)"}
            """
        return try AlohaJSON.decoder.decode(Account.self, from: Data(json.utf8))
    }

    @Test("A header that is the avatar again is no header")
    func headerEqualToAvatar() throws {
        // Person::exportAsLocal falls back to the avatar image for the header.
        let alice = try account(
            avatar: "https://cloud.example/avatar.png", header: "https://cloud.example/avatar.png")
        #expect(alice.avatar != nil)
        #expect(alice.header == nil)
        #expect(alice.headerStatic == nil)
    }

    @Test("A real header is kept")
    func distinctHeader() throws {
        let alice = try account(
            avatar: "https://cloud.example/avatar.png", header: "https://cloud.example/header.png")
        #expect(alice.header?.lastPathComponent == "header.png")
    }
}
