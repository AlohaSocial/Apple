// SPDX-License-Identifier: MIT

import Foundation

/// The wire shapes of `/api/v2/instance` and `/api/v1/instance/`, kept separate
/// from `InstanceDescription` so that one persisted type can be fed by either.
///
/// v2 renames `uri` to `domain`, makes `thumbnail` an object, moves the flat
/// contact and registration fields under `contact` and `registrations`, and
/// folds `urls` and a `translation` block into `configuration`.
public enum InstancePayload {
    public struct V2: Decodable, Sendable {
        public var domain: String?
        var title: String?
        var version: String?
        var sourceURL: String?
        var description: String?
        var thumbnail: Thumbnail?
        var languages: [String]?
        var rules: [InstanceDescription.Rule]?
        var contact: Contact?
        var registrations: Registrations?
        var usage: Usage?
        var apiVersions: [String: Int]?
        var configuration: Configuration?

        struct Thumbnail: Decodable, Sendable {
            @LenientURL var url: URL?
        }
        struct Contact: Decodable, Sendable {
            var email: String?
            var account: Account?
        }
        struct Registrations: Decodable, Sendable {
            @LenientBool var enabled: Bool
            @LenientBool var approvalRequired: Bool
            enum CodingKeys: String, CodingKey {
                case enabled
                case approvalRequired = "approval_required"
            }
        }
        struct Usage: Decodable, Sendable {
            var users: Users?
            struct Users: Decodable, Sendable {
                var activeMonth: Int?
                enum CodingKeys: String, CodingKey { case activeMonth = "active_month" }
            }
        }

        enum CodingKeys: String, CodingKey {
            case domain, title, version, description, thumbnail, languages, rules
            case contact, registrations, usage, configuration
            case sourceURL = "source_url"
            case apiVersions = "api_versions"
        }
    }

    public struct V1: Decodable, Sendable {
        var uri: String?
        var title: String?
        var version: String?
        var shortDescription: String?
        var description: String?
        @LenientURL var thumbnail: URL?
        var languages: [String]?
        var rules: [InstanceDescription.Rule]?
        var email: String?
        var contactAccount: Account?
        @LenientBool var registrations: Bool
        @LenientBool var approvalRequired: Bool
        var stats: Stats?
        var urls: URLs?
        var configuration: Configuration?

        struct Stats: Decodable, Sendable {
            var userCount: Int?
            var statusCount: Int?
            var domainCount: Int?
            enum CodingKeys: String, CodingKey {
                case userCount = "user_count"
                case statusCount = "status_count"
                case domainCount = "domain_count"
            }
        }

        enum CodingKeys: String, CodingKey {
            case uri, title, version, description, thumbnail, languages, rules, email
            case registrations, stats, urls, configuration
            case shortDescription = "short_description"
            case contactAccount = "contact_account"
            case approvalRequired = "approval_required"
        }
    }

    /// `urls` is an empty object on Nextcloud Social. Decoding it as a struct
    /// with optional members gives `nil`, which is exactly the signal.
    ///
    /// Two spellings: v1 calls the key `streaming_api`, and Mastodon 4.x's v2
    /// `configuration.urls` calls it `streaming`. A client that reads only one
    /// decides a server has no streaming when it does — which is what live
    /// testing against mastodon.social turned up.
    struct URLs: Decodable, Sendable {
        @LenientURL var streamingAPI: URL?
        @LenientURL var streaming: URL?

        var resolved: URL? { streaming ?? streamingAPI }

        enum CodingKeys: String, CodingKey {
            case streamingAPI = "streaming_api"
            case streaming
        }
    }

    struct Configuration: Decodable, Sendable {
        var urls: URLs?
        var statuses: Statuses?
        var mediaAttachments: MediaAttachments?
        var polls: Polls?
        var accounts: Accounts?
        var translation: Translation?
        var vapid: Vapid?

        // Without this mapping `media_attachments` never decodes, and the
        // limits silently fall back to Mastodon's defaults — which would cap
        // video uploads at 40 MB on a Nextcloud that allows 2048.
        enum CodingKeys: String, CodingKey {
            case urls, statuses, polls, accounts, translation, vapid
            case mediaAttachments = "media_attachments"
        }

        struct Statuses: Decodable, Sendable {
            var maxCharacters: Int?
            var maxMediaAttachments: Int?
            var charactersReservedPerURL: Int?
            enum CodingKeys: String, CodingKey {
                case maxCharacters = "max_characters"
                case maxMediaAttachments = "max_media_attachments"
                case charactersReservedPerURL = "characters_reserved_per_url"
            }
        }
        struct MediaAttachments: Decodable, Sendable {
            var supportedMIMETypes: [String]?
            var imageSizeLimit: Int?
            var videoSizeLimit: Int?
            enum CodingKeys: String, CodingKey {
                case supportedMIMETypes = "supported_mime_types"
                case imageSizeLimit = "image_size_limit"
                case videoSizeLimit = "video_size_limit"
            }
        }
        struct Polls: Decodable, Sendable {
            var maxOptions: Int?
            var maxCharactersPerOption: Int?
            var minExpiration: TimeInterval?
            var maxExpiration: TimeInterval?
            enum CodingKeys: String, CodingKey {
                case maxOptions = "max_options"
                case maxCharactersPerOption = "max_characters_per_option"
                case minExpiration = "min_expiration"
                case maxExpiration = "max_expiration"
            }
        }
        struct Accounts: Decodable, Sendable {
            var maxFeaturedTags: Int?
            enum CodingKeys: String, CodingKey { case maxFeaturedTags = "max_featured_tags" }
        }
        struct Translation: Decodable, Sendable {
            @LenientBool var enabled: Bool
        }
        struct Vapid: Decodable, Sendable {
            var publicKey: String?
            enum CodingKeys: String, CodingKey { case publicKey = "public_key" }
        }
    }

    static func limits(from configuration: Configuration?) -> ServerLimits {
        let fallback = ServerLimits.mastodonDefaults
        guard let configuration else { return fallback }
        return ServerLimits(
            maxStatusCharacters: configuration.statuses?.maxCharacters
                ?? fallback.maxStatusCharacters,
            maxMediaAttachments: configuration.statuses?.maxMediaAttachments
                ?? fallback.maxMediaAttachments,
            charactersReservedPerURL: configuration.statuses?.charactersReservedPerURL
                ?? fallback.charactersReservedPerURL,
            imageSizeLimit: configuration.mediaAttachments?.imageSizeLimit
                ?? fallback.imageSizeLimit,
            videoSizeLimit: configuration.mediaAttachments?.videoSizeLimit
                ?? fallback.videoSizeLimit,
            supportedMIMETypes: configuration.mediaAttachments?.supportedMIMETypes
                ?? fallback.supportedMIMETypes,
            maxPollOptions: configuration.polls?.maxOptions ?? fallback.maxPollOptions,
            maxPollOptionCharacters: configuration.polls?.maxCharactersPerOption
                ?? fallback.maxPollOptionCharacters,
            minPollExpiration: configuration.polls?.minExpiration ?? fallback.minPollExpiration,
            maxPollExpiration: configuration.polls?.maxExpiration ?? fallback.maxPollExpiration,
            maxFeaturedTags: configuration.accounts?.maxFeaturedTags ?? fallback.maxFeaturedTags
        )
    }
}

extension InstanceDescription {
    public init(v2: InstancePayload.V2) {
        self.init(
            domain: v2.domain ?? "",
            title: v2.title ?? "",
            version: v2.version ?? "",
            sourceURL: v2.sourceURL,
            shortDescription: v2.description ?? "",
            description: v2.description ?? "",
            thumbnail: v2.thumbnail?.url,
            languages: v2.languages ?? [],
            rules: v2.rules ?? [],
            contactAccount: v2.contact?.account,
            contactEmail: v2.contact?.email,
            registrationsEnabled: v2.registrations?.enabled ?? false,
            approvalRequired: v2.registrations?.approvalRequired ?? false,
            userCount: v2.usage?.users?.activeMonth,
            statusCount: nil,
            domainCount: nil,
            streamingURL: v2.configuration?.urls?.resolved,
            vapidKey: v2.configuration?.vapid?.publicKey,
            translationEnabled: v2.configuration?.translation?.enabled ?? false,
            apiVersions: v2.apiVersions ?? [:],
            limits: InstancePayload.limits(from: v2.configuration)
        )
    }

    public init(v1: InstancePayload.V1) {
        self.init(
            domain: v1.uri ?? "",
            title: v1.title ?? "",
            version: v1.version ?? "",
            sourceURL: nil,
            shortDescription: v1.shortDescription ?? "",
            description: v1.description ?? "",
            thumbnail: v1.thumbnail,
            languages: v1.languages ?? [],
            rules: v1.rules ?? [],
            contactAccount: v1.contactAccount,
            contactEmail: v1.email,
            registrationsEnabled: v1.registrations,
            approvalRequired: v1.approvalRequired,
            userCount: v1.stats?.userCount,
            statusCount: v1.stats?.statusCount,
            domainCount: v1.stats?.domainCount,
            streamingURL: v1.urls?.resolved ?? v1.configuration?.urls?.resolved,
            vapidKey: v1.configuration?.vapid?.publicKey,
            translationEnabled: v1.configuration?.translation?.enabled ?? false,
            apiVersions: [:],
            limits: InstancePayload.limits(from: v1.configuration)
        )
    }
}
