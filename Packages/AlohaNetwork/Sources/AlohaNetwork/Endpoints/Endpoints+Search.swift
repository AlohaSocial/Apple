// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

// MARK: - Search, one kind at a time

extension Endpoint.search {
    /// What `/api/v2/search` can be narrowed to with `type`.
    public enum ResultType: String, Sendable, Hashable, CaseIterable {
        case accounts
        case hashtags
        case statuses
    }

    /// One page of one kind of result.
    ///
    /// A search across every kind answers at most `limit` of each, and the
    /// rest cannot be reached: `offset` is only honoured once `type` names
    /// a single kind (docs/05 §7). So the search screen asks for everything
    /// at once to show the shape of the answer, and pages through one kind
    /// with this.
    public static func page(
        _ query: String, type: ResultType, offset: Int = 0, limit: Int = Endpoint.defaultLimit,
        resolve: Bool = false
    ) -> Endpoint {
        Endpoint(
            path: "api/v2/search",
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "type", value: type.rawValue),
                URLQueryItem(name: "limit", value: String(Endpoint.clampedLimit(limit))),
            ]
                + (offset > 0 ? [URLQueryItem(name: "offset", value: String(offset))] : [])
                + .flag("resolve", resolve))
    }
}
