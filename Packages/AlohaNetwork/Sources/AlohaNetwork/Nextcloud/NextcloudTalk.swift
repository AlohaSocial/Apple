// SPDX-License-Identifier: MIT

import Foundation
import OSLog

/// Nextcloud Talk (the `spreed` app), reached the way every OCS route is:
/// against the Nextcloud's own root, with the app password from Login Flow v2
/// as HTTP Basic and `OCS-APIRequest: true` — the same as push registration
/// (`NextcloudPush`) and the user lookup (`NextcloudLoginFlow.userID`). The
/// Social OAuth token is not a Nextcloud session and Talk refuses it.
///
/// Used for one thing: starting a call from a direct-message conversation
/// (docs/14 §7). A public room, so fediverse people on other servers, who
/// have no account on this Nextcloud, can join from the link as guests.
public struct NextcloudTalk: Sendable {
    private let transport: any HTTPTransport
    private let logger = Logger(subsystem: "social.aloha.app", category: "talk")

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    /// What this Nextcloud's Talk can do, from `cloud/capabilities`.
    public struct Capabilities: Sendable, Hashable {
        /// The conversation API version to use: 4 since Talk 13, 3 before.
        public var conversationAPIVersion: Int
        public var features: Set<String>
        /// Talk's own switch for calls (`config.call.enabled`), absent on
        /// versions from before it existed, which always allowed them.
        public var callsEnabled: Bool
        /// Whether this user may create conversations at all
        /// (`config.conversations.can-create`); an administrator can limit it
        /// to some groups.
        public var canCreateConversations: Bool

        /// Whether a call can be started from here: Talk is there, calls are
        /// on, and this person may make a room.
        public var canStartCalls: Bool { callsEnabled && canCreateConversations }
    }

    public struct Room: Sendable, Hashable, Decodable {
        public var token: String
        public var name: String?
        public var displayName: String?
    }

    public enum TalkError: Error, Sendable, Equatable {
        case unauthorised
        /// Talk said no: room creation is limited to some groups, say.
        case refused(Int)
        case malformedResponse
    }

    // MARK: - Capabilities

    static func capabilitiesRequest(credentials: NextcloudLoginFlow.Credentials) -> URLRequest {
        request(path: "ocs/v2.php/cloud/capabilities", credentials: credentials)
    }

    /// Nil when the Nextcloud has no Talk: no `spreed` key at all, or one
    /// without a conversation API this app speaks.
    static func parseCapabilities(_ data: Data) -> Capabilities? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let ocs = json["ocs"] as? [String: Any],
            let payload = ocs["data"] as? [String: Any],
            // An empty `capabilities` arrives as `[]`, not `{}`.
            let capabilities = payload["capabilities"] as? [String: Any],
            let spreed = capabilities["spreed"] as? [String: Any]
        else { return nil }

        let features = Set((spreed["features"] as? [Any])?.compactMap { $0 as? String } ?? [])
        let version: Int
        if features.contains("conversation-v4") {
            version = 4
        } else if features.contains("conversation-v3") {
            version = 3
        } else {
            return nil
        }

        let config = spreed["config"] as? [String: Any]
        let call = config?["call"] as? [String: Any]
        let conversations = config?["conversations"] as? [String: Any]
        return Capabilities(
            conversationAPIVersion: version,
            features: features,
            callsEnabled: flag(call?["enabled"]) ?? true,
            canCreateConversations: flag(conversations?["can-create"]) ?? true)
    }

    /// OCS writes a boolean as `true`, `1` or `"1"` depending on the app.
    private static func flag(_ value: Any?) -> Bool? {
        switch value {
        case let value as Bool: value
        case let value as NSNumber: value.boolValue
        case let value as String: ["1", "true", "yes"].contains(value.lowercased())
        default: nil
        }
    }

    /// Nil when there is no Talk, or the Nextcloud could not be asked.
    public func capabilities(credentials: NextcloudLoginFlow.Credentials) async -> Capabilities? {
        guard
            let (data, response) = try? await transport.send(
                Self.capabilitiesRequest(credentials: credentials)),
            response.statusCode == 200
        else { return nil }
        return Self.parseCapabilities(data)
    }

    // MARK: - Rooms

    /// Talk's room types; 3 is a public room, joinable by link.
    static let publicRoomType = 3
    /// Talk refuses a longer name.
    static let maximumNameLength = 255

    static func createRoomRequest(
        name: String, apiVersion: Int, credentials: NextcloudLoginFlow.Credentials
    ) -> URLRequest {
        var request = request(
            path: "ocs/v2.php/apps/spreed/api/v\(apiVersion)/room", credentials: credentials)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded; charset=utf-8",
            forHTTPHeaderField: "Content-Type")
        request.httpBody = FormEncoding.body([
            URLQueryItem(name: "roomType", value: String(publicRoomType)),
            URLQueryItem(name: "roomName", value: String(name.prefix(maximumNameLength))),
        ])
        return request
    }

    static func parseRoom(_ data: Data) throws -> Room {
        struct Envelope: Decodable {
            struct OCS: Decodable { let data: Room }
            let ocs: OCS
        }
        guard let room = try? JSONDecoder().decode(Envelope.self, from: data).ocs.data,
            !room.token.isEmpty
        else { throw TalkError.malformedResponse }
        return room
    }

    /// Creates a public room named `name`. Its link is `joinURL(for:)`.
    public func createPublicRoom(
        named name: String, capabilities: Capabilities,
        credentials: NextcloudLoginFlow.Credentials
    ) async throws -> Room {
        let (data, response) = try await transport.send(
            Self.createRoomRequest(
                name: name, apiVersion: capabilities.conversationAPIVersion,
                credentials: credentials))
        switch response.statusCode {
        case 200, 201:
            logger.info("talk room created")
            return try Self.parseRoom(data)
        case 401:
            throw TalkError.unauthorised
        default:
            throw TalkError.refused(response.statusCode)
        }
    }

    // MARK: - Links

    /// The room's web link, which anyone can open — a guest in a browser,
    /// or the Talk app where it claims the address.
    ///
    /// With `index.php`: `/call/<token>` alone works only where the
    /// administrator has turned on pretty URLs, and a link that 404s in
    /// somebody else's browser is a call nobody can join.
    public static func joinURL(token: String, credentials: NextcloudLoginFlow.Credentials) -> URL {
        credentials.server.appending(path: "index.php/call").appending(component: token)
    }

    /// The Talk iOS app's own link to the room, for this account
    /// (`nextcloudtalk://open-conversation`, handled in talk-ios'
    /// `AppDelegate`). Opening it fails, harmlessly, when Talk is not
    /// installed, and the web link is used instead.
    public static func appURL(token: String, credentials: NextcloudLoginFlow.Credentials) -> URL? {
        var components = URLComponents()
        components.scheme = "nextcloudtalk"
        components.host = "open-conversation"
        components.queryItems = [
            URLQueryItem(name: "server", value: credentials.server.absoluteString),
            URLQueryItem(name: "user", value: credentials.filesUserID),
            URLQueryItem(name: "withRoomToken", value: token),
        ]
        return components.url
    }

    // MARK: - Requests

    /// Every OCS request: Basic with the app password, the OCS header every
    /// route insists on, and JSON rather than OCS's default XML.
    private static func request(
        path: String, credentials: NextcloudLoginFlow.Credentials
    )
        -> URLRequest
    {
        var components = URLComponents(
            url: credentials.server.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "format", value: "json")]
        var request = URLRequest(url: components?.url ?? credentials.server.appending(path: path))
        request.setValue(credentials.basicAuthorization, forHTTPHeaderField: "Authorization")
        request.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AlohaUserAgent.value, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }
}
