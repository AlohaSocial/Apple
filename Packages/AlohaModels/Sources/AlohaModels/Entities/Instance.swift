// SPDX-License-Identifier: MIT

import Foundation

/// `/api/v2/instance`, with `/api/v1/instance/` folded into the same shape.
///
/// Newer clients ask for v2 first and fall back to v1 on a 404, which is what
/// `InstanceDescription.init(v1:)` is for.
public struct InstanceDescription: Codable, Sendable, Hashable {
    public var domain: String
    public var title: String
    public var version: String
    public var sourceURL: String?
    public var shortDescription: String
    public var description: String
    @LenientURL public var thumbnail: URL?
    public var languages: [String]
    public var rules: [Rule]
    public var contactAccount: Account?
    public var contactEmail: String?
    @LenientBool public var registrationsEnabled: Bool
    @LenientBool public var approvalRequired: Bool
    public var userCount: Int?
    public var statusCount: Int?
    public var domainCount: Int?

    /// `{}` on Nextcloud Social, which is how a client learns there is no
    /// streaming endpoint and falls back to polling immediately rather than
    /// after a timeout (docs/02 §1).
    @LenientURL public var streamingURL: URL?
    /// `""` on Nextcloud Social, so a client decides against offering Web Push
    /// before it asks for it.
    public var vapidKey: String?
    @LenientBool public var translationEnabled: Bool
    /// `{"mastodon": 3}` on a 4.3-compatible server. What a 4.3 client reads
    /// *instead of* parsing a version string that, on a fork, says nothing.
    public var apiVersions: [String: Int]
    public var limits: ServerLimits

    public struct Rule: Codable, Sendable, Hashable, Identifiable {
        @FlexibleID public var id: String
        public var text: String
        public var hint: String?

        public init(id: String, text: String, hint: String? = nil) {
            _id = .init(wrappedValue: id)
            self.text = text
            self.hint = hint
        }
    }

    public init(
        domain: String, title: String = "", version: String = "", sourceURL: String? = nil,
        shortDescription: String = "", description: String = "", thumbnail: URL? = nil,
        languages: [String] = [], rules: [Rule] = [], contactAccount: Account? = nil,
        contactEmail: String? = nil, registrationsEnabled: Bool = false,
        approvalRequired: Bool = false, userCount: Int? = nil, statusCount: Int? = nil,
        domainCount: Int? = nil, streamingURL: URL? = nil, vapidKey: String? = nil,
        translationEnabled: Bool = false, apiVersions: [String: Int] = [:],
        limits: ServerLimits = .mastodonDefaults
    ) {
        self.domain = domain
        self.title = title
        self.version = version
        self.sourceURL = sourceURL
        self.shortDescription = shortDescription
        self.description = description
        _thumbnail = .init(wrappedValue: thumbnail)
        self.languages = languages
        self.rules = rules
        self.contactAccount = contactAccount
        self.contactEmail = contactEmail
        _registrationsEnabled = .init(wrappedValue: registrationsEnabled)
        _approvalRequired = .init(wrappedValue: approvalRequired)
        self.userCount = userCount
        self.statusCount = statusCount
        self.domainCount = domainCount
        _streamingURL = .init(wrappedValue: streamingURL)
        self.vapidKey = vapidKey
        _translationEnabled = .init(wrappedValue: translationEnabled)
        self.apiVersions = apiVersions
        self.limits = limits
    }
}

extension InstanceDescription {
    /// The Mastodon API generation this server implements, read from
    /// `api_versions` where present and inferred from the version string
    /// otherwise. Nextcloud Social announces `mastodon: 3`, which is 4.3.
    public var mastodonAPIVersion: Int? { apiVersions["mastodon"] }

    /// `nil` means no streaming. Nextcloud Social says so with an empty `urls`.
    public var hasStreaming: Bool { streamingURL != nil }

    /// An empty string is the server saying "do not offer Web Push".
    public var hasWebPush: Bool {
        guard let vapidKey else { return false }
        return !vapidKey.isEmpty
    }
}
