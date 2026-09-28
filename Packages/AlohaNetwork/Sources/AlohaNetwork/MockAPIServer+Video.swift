// SPDX-License-Identifier: MIT

import Foundation

extension MockAPIServer {
    /// Mock answers for the Video surfaces. `nil` means "not mine".
    func videoMock(
        route: String, url: URL, method: String, query: [URLQueryItem], body: Data?
    ) -> (Data, HTTPURLResponse)? {
        nil
    }
}
