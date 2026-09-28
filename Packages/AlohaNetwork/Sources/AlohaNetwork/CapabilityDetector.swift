// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import OSLog

/// Works out what one server can do, once at sign-in and every 24 h after.
///
/// The governing rule (docs/02 §4): **a capability that cannot be determined is
/// treated as absent.** Every probe here is tolerant of failure, and failure
/// always means `false`.
public struct CapabilityDetector: Sendable {
    private let transport: any HTTPTransport
    private let logger = Logger(subsystem: "com.nextcloud.alohasocial", category: "capabilities")

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func detect(
        apiBase: URL,
        accessToken: String?,
        instance: InstanceDescription,
        nodeInfo: NodeInfo?
    ) async -> ServerCapabilities {
        let softwareName = (nodeInfo?.software.name ?? "").lowercased()
        let isNextcloudSocial =
            softwareName.contains("nextcloud") && softwareName.contains("social")
        let mastodonVersion = instance.mastodonAPIVersion

        // 4.x surfaces are announced rather than probed where the server states
        // its API generation. Nextcloud Social says `{"mastodon": 3}`, which is
        // 4.3 — and gating on the version string alone used to hide finished
        // work, which is why api_versions exists.
        let isMastodon43 =
            (mastodonVersion ?? 0) >= 3
            || instance.version.contains("4.3")
            || instance.version.contains("4.4")

        async let grouped = probe(
            apiBase: apiBase, token: accessToken, path: "api/v2/notifications",
            query: [URLQueryItem(name: "limit", value: "1")])
        async let policy = probe(
            apiBase: apiBase, token: accessToken, path: "api/v2/notifications/policy")
        async let filtersV2 = probe(apiBase: apiBase, token: accessToken, path: "api/v2/filters")
        async let watch = probe(
            apiBase: apiBase, token: accessToken, path: "api/v1/videos/continue",
            query: [URLQueryItem(name: "limit", value: "1")])
        async let stories = probe(
            apiBase: apiBase, token: accessToken, path: "api/v1/stories/carousel")
        async let collections = probe(
            apiBase: apiBase, token: accessToken, path: "api/v1/collections")
        async let fromFile = probeAcceptsRoute(
            apiBase: apiBase, token: accessToken, path: "api/v1/media/from-file")
        async let translationLanguages = fetchTranslationLanguages(
            apiBase: apiBase, token: accessToken)
        // Nextcloud's own route, at the root above the API base. Detected here
        // so the colour is stored, refreshed and persisted with everything else
        // the server says about itself, rather than fetched again per launch.
        async let serverTheme = NextcloudThemeProbe(transport: transport)
            .theme(
                nextcloudRoot: ServerCapabilities.minimal(apiBase: apiBase).nextcloudRoot)

        // `only_video` and `only_news` are this app's own. Mastodon accepts
        // unknown query parameters silently, so the absence of a 422 is not
        // proof — the software name has to agree (docs/02 §4).
        // Resolve every concurrent probe before building the result: `&&` takes
        // an autoclosure, which cannot capture an `async let`.
        let hasGroupedRoute = await grouped
        let hasPolicy = await policy
        let hasFiltersV2 = await filtersV2
        let hasWatchPositions = await watch
        let hasStories = await stories
        let hasCollections = await collections
        let hasFromFile = await fromFile
        let languages = await translationLanguages
        let theme = await serverTheme

        // `only_video` and `only_news` are this app's own. Mastodon accepts
        // unknown query parameters silently, so the absence of a 422 is not
        // proof — the software name has to agree (docs/02 §4).
        let videoNarrowing =
            isNextcloudSocial
            ? await acceptsNarrowing(apiBase: apiBase, token: accessToken, parameter: "only_video")
            : false
        let newsNarrowing =
            isNextcloudSocial
            ? await acceptsNarrowing(apiBase: apiBase, token: accessToken, parameter: "only_news")
            : false
        // only_media is Mastodon's own on the account timeline and Nextcloud's
        // on the public one; assume it where the server is either.
        let mediaNarrowing: Bool
        if isNextcloudSocial {
            mediaNarrowing = true
        } else {
            mediaNarrowing = await acceptsNarrowing(
                apiBase: apiBase, token: accessToken, parameter: "only_media")
        }

        return ServerCapabilities(
            apiBase: apiBase,
            softwareName: softwareName,
            softwareVersion: nodeInfo?.software.version ?? instance.version,
            mastodonAPIVersion: mastodonVersion,
            streamingURL: instance.streamingURL,
            webPushVAPIDKey: instance.hasWebPush ? instance.vapidKey : nil,
            groupedNotifications: isMastodon43 && hasGroupedRoute,
            notificationPolicy: hasPolicy,
            filtersV2: hasFiltersV2,
            editHistory: isMastodon43,
            translation: instance.translationEnabled,
            translationLanguages: languages,
            onlyMediaFilter: mediaNarrowing,
            onlyVideoFilter: videoNarrowing,
            onlyNewsFilter: newsNarrowing,
            // Latched on first sighting of the field in a decoded entity, so it
            // starts false and is promoted by `latch(...)` below.
            hlsLadder: false,
            watchPositions: hasWatchPositions,
            stories: hasStories,
            collections: hasCollections,
            emojiReactions: false,
            quotePosts: false,
            mediaFromNextcloudFiles: hasFromFile,
            preferencesWrite: isNextcloudSocial,
            limits: instance.limits,
            theme: theme,
            detectedAt: Date()
        )
    }

    // MARK: - Probes

    /// 200 → available. 404 → absent. **401 → available but unauthorised**,
    /// which is still available: the route exists, the token just did not carry
    /// the scope or was not sent.
    private func probe(
        apiBase: URL, token: String?, path: String, query: [URLQueryItem] = []
    ) async -> Bool {
        guard
            var components = URLComponents(
                url: apiBase.appending(path: path), resolvingAgainstBaseURL: false)
        else { return false }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { return false }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.timeoutInterval = 8

        guard let (_, response) = try? await transport.send(request) else { return false }
        switch response.statusCode {
        case 200..<300, 401, 403: return true
        default: return false
        }
    }

    /// A POST-only route cannot be probed with a GET without side effects. A
    /// 405 is proof the path exists; a 404 is proof it does not.
    private func probeAcceptsRoute(apiBase: URL, token: String?, path: String) async -> Bool {
        var request = URLRequest(url: apiBase.appending(path: path))
        request.httpMethod = "GET"
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.timeoutInterval = 8

        guard let (_, response) = try? await transport.send(request) else { return false }
        return response.statusCode != 404
    }

    /// Nextcloud Social answers a **422** for a `{timeline}` it does not know,
    /// and accepts its own narrowings. A 422 here means the parameter was
    /// rejected; anything 2xx means it was taken.
    private func acceptsNarrowing(apiBase: URL, token: String?, parameter: String) async -> Bool {
        guard
            var components = URLComponents(
                url: apiBase.appending(path: "api/v1/timelines/public/"),
                resolvingAgainstBaseURL: false)
        else { return false }
        components.queryItems = [
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: parameter, value: "true"),
        ]
        guard let url = components.url else { return false }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.timeoutInterval = 8

        guard let (_, response) = try? await transport.send(request) else { return false }
        return (200..<300).contains(response.statusCode)
    }

    private func fetchTranslationLanguages(apiBase: URL, token: String?) async -> [String: [String]]
    {
        var request = URLRequest(
            url: apiBase.appending(path: "api/v1/instance/translation_languages"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.timeoutInterval = 8

        guard let (data, response) = try? await transport.send(request),
            (200..<300).contains(response.statusCode),
            let languages = try? AlohaJSON.decoder.decode([String: [String]].self, from: data)
        else { return [:] }
        return languages
    }
}

extension ServerCapabilities {
    /// Promoted on first sighting of the relevant field in a decoded entity and
    /// persisted, because these three have nothing to announce them (docs/02 §4).
    public mutating func latch(observing statuses: [Status]) {
        for status in statuses.map(\.displayed) {
            if !hlsLadder, status.mediaAttachments.contains(where: { $0.hlsURL != nil }) {
                hlsLadder = true
            }
            if !emojiReactions, let reactions = status.reactions, !reactions.isEmpty {
                emojiReactions = true
            }
            if !quotePosts, status.quoteID != nil {
                quotePosts = true
            }
            if hlsLadder && emojiReactions && quotePosts { return }
        }
    }
}
