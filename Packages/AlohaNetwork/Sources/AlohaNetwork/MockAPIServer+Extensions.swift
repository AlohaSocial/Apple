// SPDX-License-Identifier: MIT

import Foundation

/// The Nextcloud-only surfaces, each answered from its own file so the
/// feature areas can be built side by side without editing one switch.
extension MockAPIServer {
    func extensionAnswer(
        route: String, url: URL, method: String, query: [URLQueryItem], body: Data?
    ) -> (Data, HTTPURLResponse)? {
        let handlers: [(String, URL, String, [URLQueryItem], Data?) -> (Data, HTTPURLResponse)?] = [
            discoveryMock,
            interestsMock,
            statusExtrasMock,
            composerMock,
            profileMock,
            accountMock,
            storiesMock,
            videoMock,
            moderationMock,
        ]
        for handler in handlers {
            if let answered = handler(route, url, method, query, body) { return answered }
        }
        return nil
    }
}
