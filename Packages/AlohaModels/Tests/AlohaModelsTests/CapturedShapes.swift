// SPDX-License-Identifier: MIT

import Foundation

/// Whole entities in the shapes servers actually send (docs/12 §2).
///
/// The Aloha Social shapes follow the server's own export functions key for
/// key — `Stream::exportAsLocal`, `Person::exportAsLocal`,
/// `MediaAttachment::jsonSerialize` and `Stream::exportAsNotification` — with
/// their nulls where the server writes nulls. The Mastodon shapes are
/// mastodon.social's 4.5 entities. Hand-written snippets test one key; these
/// test that a real page, with every key a server puts on it, decodes.
enum CapturedShapes {
    static let alohaAccount = #"""
        {
          "id": "184",
          "username": "frank",
          "acct": "frank",
          "display_name": "Frank :hibiscus:",
          "locked": false,
          "bot": false,
          "discoverable": true,
          "indexable": true,
          "group": false,
          "created_at": "2026-04-02T09:15:00.000Z",
          "note": "<p>Building things on <a href=\"https://cloud.example.test/apps/social/@frank\">my own server</a>.</p>",
          "url": "https://cloud.example.test/apps/social/@frank",
          "avatar": "https://cloud.example.test/index.php/avatar/frank/512",
          "avatar_static": "https://cloud.example.test/index.php/avatar/frank/512",
          "header": "https://cloud.example.test/apps/social/img/header.svg",
          "header_static": "https://cloud.example.test/apps/social/img/header.svg",
          "avatar_default": false,
          "header_default": true,
          "followers_count": 1204,
          "following_count": 311,
          "statuses_count": 5120,
          "last_status_at": "2026-10-16",
          "roles": [],
          "emojis": [
            {"shortcode": "hibiscus", "url": "https://cloud.example.test/emoji/hibiscus.png",
             "static_url": "https://cloud.example.test/emoji/hibiscus.png", "visible_in_picker": true}
          ],
          "fields": [
            {"name": "Pronouns", "value": "he/him", "verified_at": null},
            {"name": "Website", "value": "<a href=\"https://example.test\">example.test</a>",
             "verified_at": "2026-09-01T10:00:00.000Z"}
          ],
          "pronouns": "he/him",
          "support_link": "",
          "bluesky": null,
          "verification": null,
          "nextcloud_user": "frank"
        }
        """#

    /// A post written here: `quote_approval` and `reply_policy` are set,
    /// `interaction_policy` is null (this server applies its own), the video
    /// and dislike keys are null because it is not a video.
    static let alohaLocalStatus = #"""
        {
          "id": "1129384756",
          "local": true,
          "archived": false,
          "view_count": 87,
          "tagged_people": [],
          "interest": null,
          "content": "<p>Sunset at the harbour <a href=\"https://cloud.example.test/tags/photography\" class=\"mention hashtag\">#<span>photography</span></a></p>",
          "sensitive": false,
          "spoiler_text": "",
          "visibility": "public",
          "language": "en",
          "place": {"id": "77", "name": "Hilo", "country": "US", "lat": 19.7071, "long": -155.0885},
          "in_reply_to_id": null,
          "in_reply_to_account_id": null,
          "quote": null,
          "quote_approval": {"automatic": ["followers"], "manual": [], "current_user": "automatic"},
          "reply_policy": "followers,mentioned",
          "hidden_by_author": null,
          "can_hide": null,
          "reply_approval": null,
          "interaction_policy": null,
          "dislikes_count": null,
          "disliked": null,
          "video": null,
          "mentions": [],
          "emojis": [],
          "tags": [{"name": "photography", "url": "https://cloud.example.test/tags/photography"}],
          "ai_generated": false,
          "bluesky": null,
          "replies_count": 3,
          "reblogs_count": 12,
          "favourites_count": 41,
          "quotes_count": 2,
          "favourited": true,
          "reblogged": false,
          "muted": false,
          "bookmarked": false,
          "pinned": false,
          "card": null,
          "reactions": [{"name": "🌺", "count": 4, "me": true}],
          "poll": null,
          "uri": "https://cloud.example.test/apps/social/@frank/1129384756",
          "application": null,
          "filtered": [],
          "text": null,
          "url": "https://cloud.example.test/apps/social/@frank/1129384756",
          "reblog": null,
          "media_attachments": [
            {
              "id": "5521",
              "type": "image",
              "media_type": "image/jpeg",
              "url": "https://cloud.example.test/apps/social/document/get/resized?id=5521",
              "preview_url": "https://cloud.example.test/apps/social/document/get/preview?id=5521",
              "hls_url": null,
              "remote_url": null,
              "cache_error": null,
              "meta": {"original": {"width": 4032, "height": 3024, "size": "4032x3024", "aspect": 1.3333},
                       "focus": {"x": 0.1, "y": -0.2}},
              "description": "Boats in a calm harbour under an orange sky",
              "blurhash": "LKO2?U%2Tw=w]~RBVZRi};RPxuwH",
              "ai_generated": false
            }
          ],
          "created_at": "2026-10-16T18:42:07.000Z",
          "edited_at": null,
          "noindex": false,
          "account": \#(alohaAccount)
        }
        """#

    /// A post that arrived from a Mastodon server: no `quote_approval` or
    /// `reply_policy` of ours, an `interaction_policy` read off its document,
    /// and the attachment kept on the origin until the cache fetched it.
    static let alohaFederatedStatus = #"""
        {
          "id": "1129384999",
          "local": false,
          "archived": false,
          "view_count": null,
          "tagged_people": [{"id": "42", "username": "kai"}],
          "interest": {"tags": ["surfing"], "reason": "interest"},
          "content": "<p>Waves are up today</p>",
          "sensitive": true,
          "spoiler_text": "Water, lots of it",
          "visibility": "unlisted",
          "language": null,
          "place": null,
          "in_reply_to_id": "1129384756",
          "in_reply_to_account_id": "184",
          "quote": {"state": "accepted", "quoted_status": null},
          "quote_approval": null,
          "reply_policy": null,
          "hidden_by_author": false,
          "can_hide": true,
          "reply_approval": null,
          "interaction_policy": {"reply": true, "boost": false, "like": true},
          "dislikes_count": null,
          "disliked": null,
          "video": null,
          "mentions": [{"id": "184", "username": "frank", "acct": "frank",
                        "url": "https://cloud.example.test/apps/social/@frank"}],
          "emojis": [],
          "tags": [],
          "ai_generated": true,
          "bluesky": null,
          "replies_count": 0,
          "reblogs_count": 0,
          "favourites_count": 0,
          "quotes_count": 0,
          "favourited": false,
          "reblogged": false,
          "muted": false,
          "bookmarked": true,
          "pinned": false,
          "card": null,
          "reactions": [],
          "poll": null,
          "uri": "https://mastodon.example.test/users/kai/statuses/113377",
          "application": null,
          "filtered": [],
          "text": null,
          "url": "https://mastodon.example.test/@kai/113377",
          "reblog": null,
          "media_attachments": [
            {
              "id": "5530",
              "type": "video",
              "media_type": "video/mp4",
              "url": null,
              "preview_url": null,
              "hls_url": null,
              "remote_url": "https://files.mastodon.example.test/media/113377.mp4",
              "cache_error": 2,
              "meta": null,
              "description": null,
              "blurhash": null,
              "ai_generated": false
            }
          ],
          "created_at": "2026-10-16T19:01:00.000Z",
          "edited_at": "2026-10-16T19:05:30.000Z",
          "noindex": false,
          "account": {
            "id": "9001", "username": "kai", "acct": "kai@mastodon.example.test",
            "display_name": "", "locked": false, "bot": false, "discoverable": false,
            "indexable": false, "group": false, "created_at": "2025-01-01T00:00:00.000Z",
            "note": "", "url": "https://mastodon.example.test/@kai",
            "avatar": "", "avatar_static": "", "header": "", "header_static": "",
            "avatar_default": true, "header_default": true,
            "followers_count": "17", "following_count": 4, "statuses_count": 210,
            "last_status_at": null, "roles": [], "emojis": [], "fields": [],
            "pronouns": "", "support_link": "", "bluesky": null, "verification": null,
            "nextcloud_user": null
          }
        }
        """#

    /// mastodon.social's 4.5 status: a card, a poll, numeric-looking string
    /// ids, a quote policy and an application.
    static let mastodonStatus = #"""
        {
          "id": "115377001234567890",
          "created_at": "2026-10-15T08:00:00.123Z",
          "in_reply_to_id": null,
          "in_reply_to_account_id": null,
          "sensitive": false,
          "spoiler_text": "",
          "visibility": "public",
          "language": "de",
          "uri": "https://mastodon.social/users/alice/statuses/115377001234567890",
          "url": "https://mastodon.social/@alice/115377001234567890",
          "replies_count": 5,
          "reblogs_count": 20,
          "favourites_count": 100,
          "quotes_count": 1,
          "edited_at": null,
          "favourited": false,
          "reblogged": false,
          "muted": false,
          "bookmarked": false,
          "pinned": false,
          "content": "<p>Which one? <a href=\"https://example.org/article\" rel=\"nofollow noopener\" target=\"_blank\"><span class=\"invisible\">https://</span><span class=\"\">example.org/article</span><span class=\"invisible\"></span></a></p>",
          "filtered": [],
          "reblog": null,
          "quote": null,
          "quote_approval": {"automatic": ["public"], "manual": [], "current_user": "automatic"},
          "application": {"name": "Web", "website": null},
          "account": {
            "id": "109302",
            "username": "alice",
            "acct": "alice",
            "display_name": "Alice",
            "locked": false,
            "bot": false,
            "discoverable": true,
            "indexable": true,
            "group": false,
            "created_at": "2022-11-08T00:00:00.000Z",
            "note": "<p>Hi</p>",
            "url": "https://mastodon.social/@alice",
            "uri": "https://mastodon.social/users/alice",
            "avatar": "https://files.mastodon.social/accounts/avatars/109/302/original/a.png",
            "avatar_static": "https://files.mastodon.social/accounts/avatars/109/302/original/a.png",
            "header": "https://mastodon.social/headers/original/missing.png",
            "header_static": "https://mastodon.social/headers/original/missing.png",
            "followers_count": 512,
            "following_count": 128,
            "statuses_count": 4096,
            "last_status_at": "2026-10-15",
            "hide_collections": false,
            "noindex": false,
            "emojis": [],
            "roles": [],
            "fields": []
          },
          "media_attachments": [],
          "mentions": [],
          "tags": [],
          "emojis": [],
          "card": {
            "url": "https://example.org/article",
            "title": "An article",
            "description": "About things",
            "language": "en",
            "type": "link",
            "author_name": "",
            "author_url": "",
            "provider_name": "Example",
            "provider_url": "",
            "html": "",
            "width": 400,
            "height": 210,
            "image": null,
            "image_description": "",
            "embed_url": "",
            "blurhash": null,
            "published_at": null,
            "authors": []
          },
          "poll": {
            "id": "778899",
            "expires_at": "2026-10-16T08:00:00.000Z",
            "expired": false,
            "multiple": false,
            "votes_count": 42,
            "voters_count": 42,
            "voted": false,
            "own_votes": [],
            "options": [{"title": "This", "votes_count": 30}, {"title": "That", "votes_count": 12}],
            "emojis": []
          }
        }
        """#

    static let alohaStoryReaction = #"""
        {
          "id": "88001",
          "type": "story:react",
          "created_at": "2026-10-16T20:00:00.000Z",
          "status": null,
          "account": \#(alohaAccount)
        }
        """#

    static let mastodonMention = #"""
        {
          "id": "34975861",
          "type": "mention",
          "group_key": "ungrouped-34975861",
          "created_at": "2026-10-15T08:05:00.000Z",
          "account": {
            "id": "109302", "username": "alice", "acct": "alice", "display_name": "Alice",
            "locked": false, "bot": false, "group": false, "created_at": "2022-11-08T00:00:00.000Z",
            "note": "", "url": "https://mastodon.social/@alice",
            "avatar": "https://files.mastodon.social/a.png", "avatar_static": "https://files.mastodon.social/a.png",
            "header": "", "header_static": "", "followers_count": 1, "following_count": 1,
            "statuses_count": 1, "last_status_at": null, "emojis": [], "fields": []
          },
          "status": \#(mastodonStatus)
        }
        """#

    // MARK: - The malformed cases docs/12 lists, inside whole entities

    /// An attachment from an Aloha Social server before `meta` was written
    /// as an object: an empty AttachmentMeta json-encoded as `[]`.
    static let attachmentWithListMeta = #"""
        {"id": "1", "type": "image", "url": "https://cloud.example.test/m/1.jpg",
         "preview_url": null, "remote_url": null, "meta": [], "description": "", "blurhash": ""}
        """#

    /// A status with numeric ids, no `poll` key at all, and an author whose
    /// avatar is the empty string.
    static let statusWithNumericIDsAndNoPoll = #"""
        {
          "id": 4242, "uri": "https://cloud.example.test/p/4242", "url": null,
          "created_at": "2026-10-01T12:00:00.000Z", "content": "<p>Old server</p>",
          "spoiler_text": "", "visibility": "public", "sensitive": false,
          "replies_count": 0, "reblogs_count": 0, "favourites_count": 0,
          "in_reply_to_id": 4241, "in_reply_to_account_id": 7,
          "media_attachments": [], "mentions": [], "tags": [], "emojis": [],
          "account": {"id": 7, "username": "old", "acct": "old", "display_name": "Old",
                      "note": "", "avatar": "", "avatar_static": "", "header": "",
                      "header_static": "", "followers_count": 0, "following_count": 0,
                      "statuses_count": 1, "fields": [], "emojis": []}
        }
        """#
}
