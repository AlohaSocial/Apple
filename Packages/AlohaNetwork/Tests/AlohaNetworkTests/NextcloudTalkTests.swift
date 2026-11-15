// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaNetwork

@Suite("Nextcloud Talk")
struct NextcloudTalkTests {

    private let credentials = NextcloudLoginFlow.Credentials(
        server: URL(string: "https://cloud.example.test/nextcloud/")!,
        loginName: "alice@example.com", appPassword: "secret", userID: "a.jones")

    private func capabilities(_ spreed: String?) -> Data {
        let inner =
            spreed.map { #"{"spreed": \#($0), "files": {"bigfilechunking": true}}"# } ?? "[]"
        return Data(
            #"{"ocs":{"meta":{"status":"ok","statuscode":200},"data":{"version":{"major":31},"capabilities":\#(inner)}}}"#
                .utf8)
    }

    @Test("Capabilities are asked of the Nextcloud root, the way every OCS route is")
    func capabilitiesRequest() throws {
        let request = NextcloudTalk.capabilitiesRequest(credentials: credentials)
        let url = try #require(request.url)
        #expect(url.path() == "/nextcloud/ocs/v2.php/cloud/capabilities")
        #expect(url.query() == "format=json")
        #expect(
            request.value(forHTTPHeaderField: "Authorization") == credentials.basicAuthorization)
        #expect(request.value(forHTTPHeaderField: "OCS-APIRequest") == "true")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("A Talk with the v4 conversation API and calls on can start calls")
    func modernTalk() throws {
        let parsed = try #require(
            NextcloudTalk.parseCapabilities(
                capabilities(
                    #"{"features": ["audio", "video", "conversation-v4", "chat-v2"], "config": {"call": {"enabled": true}, "conversations": {"can-create": true}}}"#
                )))
        #expect(parsed.conversationAPIVersion == 4)
        #expect(parsed.canStartCalls)
        #expect(parsed.features.contains("chat-v2"))
    }

    @Test("An older Talk speaks v3, and one without a config allows calls")
    func olderTalk() throws {
        let parsed = try #require(
            NextcloudTalk.parseCapabilities(capabilities(#"{"features": ["conversation-v3"]}"#)))
        #expect(parsed.conversationAPIVersion == 3)
        #expect(parsed.canStartCalls)
    }

    @Test("No spreed means no Talk; an empty capabilities list is not an error")
    func noTalk() {
        #expect(NextcloudTalk.parseCapabilities(capabilities(nil)) == nil)
        #expect(NextcloudTalk.parseCapabilities(capabilities(#"{"features": ["audio"]}"#)) == nil)
        #expect(NextcloudTalk.parseCapabilities(Data("<ocs/>".utf8)) == nil)
    }

    @Test("Calls switched off, or room creation limited to other groups, rule calls out")
    func restrictedTalk() throws {
        let noCalls = try #require(
            NextcloudTalk.parseCapabilities(
                capabilities(
                    #"{"features": ["conversation-v4"], "config": {"call": {"enabled": false}}}"#)))
        #expect(noCalls.canStartCalls == false)

        let noRooms = try #require(
            NextcloudTalk.parseCapabilities(
                capabilities(
                    #"{"features": ["conversation-v4"], "config": {"conversations": {"can-create": 0}}}"#
                )))
        #expect(noRooms.canStartCalls == false)
    }

    @Test("A room is created public, named, against the advertised API version")
    func createRoomRequest() throws {
        let request = NextcloudTalk.createRoomRequest(
            name: "Alice, Bob & Chloé", apiVersion: 4, credentials: credentials)
        let url = try #require(request.url)
        #expect(request.httpMethod == "POST")
        #expect(url.path() == "/nextcloud/ocs/v2.php/apps/spreed/api/v4/room")
        #expect(request.value(forHTTPHeaderField: "OCS-APIRequest") == "true")
        #expect(
            request.value(forHTTPHeaderField: "Authorization") == credentials.basicAuthorization)

        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        let fields = Dictionary(
            uniqueKeysWithValues: body.split(separator: "&").map { pair in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                return (
                    parts[0],
                    (parts.count > 1 ? parts[1] : "").replacingOccurrences(of: "+", with: " ")
                        .removingPercentEncoding ?? ""
                )
            })
        #expect(fields["roomType"] == "3")
        #expect(fields["roomName"] == "Alice, Bob & Chloé")
    }

    @Test("A name longer than Talk takes is shortened rather than refused")
    func longName() throws {
        let request = NextcloudTalk.createRoomRequest(
            name: String(repeating: "a", count: 400), apiVersion: 4, credentials: credentials)
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains(String(repeating: "a", count: 255)))
        #expect(body.contains(String(repeating: "a", count: 256)) == false)
    }

    @Test("The created room's token is read from the OCS envelope")
    func parsesRoom() throws {
        let room = try NextcloudTalk.parseRoom(
            Data(
                #"{"ocs":{"meta":{"status":"ok"},"data":{"id":12,"token":"abc123xy","type":3,"name":"Alice, Bob","displayName":"Alice, Bob"}}}"#
                    .utf8))
        #expect(room.token == "abc123xy")
        #expect(room.displayName == "Alice, Bob")
        #expect(throws: NextcloudTalk.TalkError.self) {
            try NextcloudTalk.parseRoom(Data(#"{"ocs":{"data":[]}}"#.utf8))
        }
    }

    @Test("The join link goes through index.php, so it works without pretty URLs")
    func joinURL() {
        let url = NextcloudTalk.joinURL(token: "abc123xy", credentials: credentials)
        #expect(
            url.absoluteString == "https://cloud.example.test/nextcloud/index.php/call/abc123xy")
    }

    @Test("The Talk app's link names the server, the user and the room")
    func appURL() throws {
        let url = try #require(NextcloudTalk.appURL(token: "abc123xy", credentials: credentials))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "nextcloudtalk")
        #expect(components.host == "open-conversation")
        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(items["withRoomToken"] == "abc123xy")
        #expect(items["user"] == "a.jones")
        #expect(items["server"] == "https://cloud.example.test/nextcloud/")
    }
}
