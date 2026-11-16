// SPDX-License-Identifier: MIT

import AlohaNetwork
import Foundation
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// Starting a Nextcloud Talk call from a direct-message conversation
/// (docs/14 §7): whether the account's Nextcloud can, making the room, and
/// opening it.
@MainActor
enum TalkCall {
    /// Per account, what the Nextcloud said about Talk and when. An answer
    /// holds for an hour; no answer — offline, or the Nextcloud unreachable —
    /// for five minutes, so a blip does not hide the button for long.
    private static var answers: [UUID: (at: Date, capabilities: NextcloudTalk.Capabilities?)] = [:]

    /// The Talk this account can start calls with, or nil.
    static func capabilities(
        for session: AccountSession, environment: AppEnvironment
    ) async -> NextcloudTalk.Capabilities? {
        guard session.hasNextcloudConnection,
            let credentials = (try? environment.credentials.nextcloudCredentials(for: session.id))
                ?? nil
        else { return nil }
        if let answer = answers[session.id] {
            let lifetime: TimeInterval = answer.capabilities == nil ? 5 * 60 : 60 * 60
            if Date().timeIntervalSince(answer.at) < lifetime {
                return answer.capabilities?.canStartCalls == true ? answer.capabilities : nil
            }
        }
        let capabilities = await NextcloudTalk(transport: environment.transport)
            .capabilities(credentials: credentials)
        answers[session.id] = (Date(), capabilities)
        return capabilities?.canStartCalls == true ? capabilities : nil
    }

    /// The room's name: everybody in the conversation, you included, so it
    /// reads the same in everyone's Talk list.
    static func roomName(others: [String], you: String) -> String {
        (others + [you]).formatted(.list(type: .and))
    }

    /// The call as it is made: the public room, and the links to it.
    struct Started {
        let joinURL: URL
        let appURL: URL?
    }

    static func start(
        named name: String, capabilities: NextcloudTalk.Capabilities,
        session: AccountSession, environment: AppEnvironment
    ) async throws -> Started {
        guard
            let credentials = (try? environment.credentials.nextcloudCredentials(for: session.id))
                ?? nil
        else { throw NextcloudTalk.TalkError.unauthorised }
        let room = try await NextcloudTalk(transport: environment.transport).createPublicRoom(
            named: name, capabilities: capabilities, credentials: credentials)
        return Started(
            joinURL: NextcloudTalk.joinURL(token: room.token, credentials: credentials),
            appURL: NextcloudTalk.appURL(token: room.token, credentials: credentials))
    }

    /// The Talk app where it is installed, through its own link; otherwise
    /// the web link, which the system gives to an app that claims the address
    /// or to the browser. Never the in-app browser: a call needs the camera
    /// and microphone, and the person's own browser is where they granted
    /// them before.
    static func open(_ call: Started, with openURL: OpenURLAction) async {
        #if os(iOS) || os(visionOS)
            if let appURL = call.appURL, await UIApplication.shared.open(appURL) {
                return
            }
        #endif
        openURL(call.joinURL, prefersInApp: false)
    }
}
