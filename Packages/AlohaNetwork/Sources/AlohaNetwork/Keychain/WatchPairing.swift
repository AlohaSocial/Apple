// SPDX-License-Identifier: MIT

import Foundation

/// What the phone hands the watch: the active account, enough to read its home
/// timeline, and the colour its server wears.
///
/// One type on both ends of WatchConnectivity, so a field added on the phone is
/// a field the watch decodes. The accent fields are optional, so a pairing the
/// watch stored before they existed still decodes.
public struct WatchPairing: Codable, Sendable, Hashable {
    /// The application-context key the pairing travels under. An empty context
    /// means the phone has no account any more and the watch should forget it.
    public static let contextKey = "credentials"

    public var accountID: UUID
    public var apiBase: URL
    public var token: String
    public var handle: String
    public var accentBrightHex: String?
    public var accentDarkHex: String?
    public var accentTextHex: String?

    public init(
        accountID: UUID, apiBase: URL, token: String, handle: String,
        accentBrightHex: String? = nil, accentDarkHex: String? = nil, accentTextHex: String? = nil
    ) {
        self.accountID = accountID
        self.apiBase = apiBase
        self.token = token
        self.handle = handle
        self.accentBrightHex = accentBrightHex
        self.accentDarkHex = accentDarkHex
        self.accentTextHex = accentTextHex
    }
}
