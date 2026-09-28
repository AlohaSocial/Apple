# 02 — Server API contract

Everything in this document was verified against Nextcloud Social `master`
(app version 0.19.95 / 0.24.1 line, September 2026) — its `docs/API.md`,
`docs/Mastodon-Compatibility.md` and its controller route attributes — and
against the Mastodon 4.3 client API.

## 1. What Nextcloud Social serves

Nextcloud Social announces `Mastodon 4.3.0` compatibility
(`version: "4.2.0 (compatible; Nextcloud Social <v>)"` on v1, and
`api_versions: {"mastodon": 3}`). Of Mastodon's 145 documented client routes,
**three** are genuinely unserved:

| Missing | Consequence for this app |
|---|---|
| `/api/v1/streaming` | No WebSocket. `instance.urls` is `{}`, which is how the server says so. **Poll.** |
| `/api/v1/push/*` (Web Push) | No APNs via the server. `vapid_key` is `""`, which is how the server says so. **Poll + local notifications.** |
| `/api/v1/emails/confirmations` | Sign-up is not this app's job anyway. |

Everything else Mastodon documents is implemented and does real work. The one
remaining stub in the whole surface is `/api/saved_searches/list.json`, a
Twitter-era route that always answers `[]`. Do not call it.

## 2. Nextcloud Social extensions worth using

These are the reason the app is Nextcloud-first. Each must sit behind a
capability flag (§4).

### Timeline narrowing — the basis of the media modes

`GET /api/v1/timelines/{timeline}/` accepts, beyond Mastodon's parameters:

| Parameter | Meaning |
|---|---|
| `only_media` | Posts carrying any attachment. **Powers Photos mode.** |
| `only_video` | Posts carrying a `video` attachment, *or* that arrived as a PeerTube `Video`. Narrower than `only_media` and wins when both are sent. **Powers Video and Shorts modes.** |
| `only_news` | Posts that arrived as an ActivityPub `Article`/`Page`, or whose text links outward. Not a subset of `only_media`. **Powers News mode.** |

`{timeline}` is one of `home`, `account`, `public`, `direct`, `favourites`
(case-insensitive). Anything else is a **422**. The same three parameters work
on `/api/v1/timelines/tag/{hashtag}` and `/api/v1/timelines/list/{id}`.

On servers without these, the modes fall back to fetching the ordinary timeline
and filtering client-side, over-fetching to fill a page. See
[06-media-modes.md](06-media-modes.md) §2.

### Video

| Route | Use |
|---|---|
| `hls_url` on `MediaAttachment` | Non-Mastodon key. Master playlist for a **local** video's transcoding ladder, when the admin enabled `video_ladder`. `null` otherwise. Prefer it over `url` when present; fall back to `url` if it fails to load. |
| `GET /media/hls/{uuid}/master.m3u8` | What `hls_url` points at. Served as `application/vnd.apple.mpegurl`. **404 when no ladder** — that 404 is the signal to play `url` instead. |
| `GET /media/playlist/{nid}` | HLS playlist for a **federated** PeerTube video, rewritten so every segment is proxied back through the Nextcloud. Use for remote video; never point `AVPlayer` at the origin directly. |
| `GET /media/stream/{nid}` | Range-capable passthrough of a federated non-HLS video. |
| `POST /api/v1/statuses/{nid}/watched` | Body `position`, `duration` in seconds. Report playback position. Never federated, never shown to anyone else. A video past 95 % is forgotten, not bookmarked. Rate limit 600/min. |
| `DELETE /api/v1/statuses/{nid}/watched` | Remove from continue-watching. |
| `GET /api/v1/videos/continue` | `limit` (20, max 40). The reader's continue-watching row. Excludes anything under 10 s watched and anything finished. |

`GET /media/{uuid}` honours `Range` and always sends `Accept-Ranges: bytes`, so
seeking works on plain files too. The resized copy of a video is its poster
frame, served as `image/jpeg`.

### Photos

Pixelfed's own surface is served at both `/api/v1.1/…` and `/api/pixelfed/v1/…`
(identical implementations). Useful pieces:

| Route | Use |
|---|---|
| `GET /api/v1/collections`, `/{id}`, `/{id}/items` | Albums. Read and write. |
| `GET /api/v1/accounts/{id}/collections` | An account's albums. |
| `GET /api/v1.1/discover/posts/trending`, `/hashtags`, `/network/trending` | Photos-mode Explore. Backed by the same `TrendService` as the Mastodon trend routes, so results cannot disagree. |
| `GET /api/v1.1/discover/accounts/popular` | People to follow in Photos mode. |
| `GET /api/v1/places/search`, `/places/{id}`, `/places/{id}/statuses` | Geotagged posts. Optional. |

### Stories

Pixelfed-shaped, one image or video that expires after a day. Every route needs
a viewer; "not yours to see" and "there are none" are both **404**.

| Route | Use |
|---|---|
| `GET /api/v1/stories/carousel` | Own stories then followed accounts', oldest first, each with `seen`. |
| `GET /api/v1/stories/self` | Own stories; `view_count` filled only here and in the carousel. |
| `GET /api/v1/accounts/{account_id}/stories` | One account's. |
| `POST /api/v1/stories` | `media_id` (required), `caption` (≤500), `duration` (clamped 3–30 s). Max 40 live. |
| `POST /api/v1/stories/{id}/seen` | Idempotent; call as the carousel advances. |
| `DELETE /api/v1/stories/{id}` | Remove early. |

**Known asymmetry:** Pixelfed only fans stories out to instances it has
identified as Pixelfed, so stories *from* Pixelfed accounts do not arrive at a
Nextcloud Social instance. Stories will mostly be local and from other Social
instances. Do not present an empty carousel as an error.

### Media from Nextcloud Files

`POST /api/v1/media/from-file` — body `path` (relative to the viewer's own user
folder) and `description`. Attaches a file already on the Nextcloud without a
round trip through the device. Bytes are copied, not referenced. A traversal or
a folder is a **422**. This is a genuine Nextcloud-only advantage and is in the
composer. See [07-composer.md](07-composer.md) §6.

### Reading preference for sensitive media

| Route | Use |
|---|---|
| `GET /api/v1/preferences` | `reading:expand:media` is real here, with PeerTube's three NSFW policies under Mastodon's names: `show_all` (display), `default` (blur, blurhash showing, one press away), `hide_all` (not drawn at all — opening the post is what it takes). Also `posting:default:visibility`, `:sensitive`, `:language`. |
| `PUT /api/v1/preferences` | **Nextcloud extension.** Body `expandMedia` ∈ `show_all` \| `default` \| `hide_all` \| `''`. `''` means "follow the instance default" and is distinct from picking today's default. Anything else is a **422**. Answers the effective policy, the `choice`, and the `instance` default. |

The app must read this before showing any timeline and must honour all three
states. `reading:expand:spoilers` is always `false` here — a content warning is
not the same thing as sensitive media.

### Reactions, quotes, interaction policy

| Route | Use |
|---|---|
| `POST /api/v1/statuses/{nid}/react`, `/unreact`, `GET /reactions` | Emoji reactions (`EmojiReact`). A Misskey/Pleroma extension; Mastodon itself has none. Show the reaction row only when capability-detected. |
| `GET /api/v1/statuses/{nid}/quotes` | Quote posts of a status. |
| `PUT /api/v1/statuses/{nid}/interaction_policy` | Who may reply/boost/quote. |

### Other extensions used

`GET /api/v1/starter_packs`, `/{slug}` · `GET /api/v1/directories`,
`/directories/search` (other servers' directories) · `GET /api/v1/channels` ·
`GET /api/v1/memories/on_this_day` · `GET /api/v1/annual_reports` ·
`GET /api/v1/follow_graph` · `GET /api/v1/gifs`, `POST /api/v1/media/from-gif`.

All optional, all capability-gated, all deferred past Phase 5 — see
[13-implementation-plan.md](13-implementation-plan.md).

### PeerTube route translation

Nextcloud Social also translates a read-only slice of PeerTube's own API
(`/api/v1/videos`, `/api/v1/video-channels`, `/api/v1/config`,
`/api/v1/users/me`, `/api/v1/search/videos`, `/api/v1/videos/{id}/comment-threads`).

**Aloha Social does not use these.** They exist so that existing PeerTube
clients work. This app already has richer data through the Mastodon routes, and
mixing two id spaces (PeerTube's numeric ids are the post `nid`, but its
entity shapes differ) buys nothing. Documented here so nobody adds them later
thinking they are needed.

## 3. Hard limits to respect

| Limit | Value on Nextcloud Social | Where to read it |
|---|---|---|
| Status length | 5000 characters | `configuration.statuses.max_characters` |
| Attachments per status | server-stated | `configuration.statuses.max_media_attachments` |
| URL cost | server-stated | `configuration.statuses.characters_reserved_per_url` |
| Image upload | 10 MB default | `configuration.media_attachments.image_size_limit` |
| Video upload | 2048 MB default | `configuration.media_attachments.video_size_limit` |
| Allowed MIME types | server-stated | `configuration.media_attachments.supported_mime_types` |
| Poll options / length / expiry | server-stated | `configuration.polls.*` |
| Page size | default 20, **capped at 50** | — |
| Blocks/mutes page size | default 40 | — |

Never hardcode any of these. Read them from `/api/v2/instance`, fall back to
`/api/v1/instance`, and fall back to Mastodon's documented defaults only if
both fail. The composer's character counter, the media picker's limits, and the
upload pre-flight all read from this one source.

## 4. Capability detection

`ServerCapabilities` is computed once per account at sign-in, refreshed on app
launch and every 24 h, and persisted. Never inferred from a hostname.

```swift
struct ServerCapabilities: Sendable, Codable, Equatable {
    var apiBase: URL                 // resolved; see 03 §2
    var softwareName: String         // from nodeinfo; "nextcloud social", "mastodon", ...
    var softwareVersion: String
    var mastodonAPIVersion: Int?     // api_versions.mastodon

    // Transport
    var streamingURL: URL?           // instance.urls.streaming_api, nil when {}
    var webPushVAPIDKey: String?     // nil when ""

    // Mastodon 4.x surfaces
    var groupedNotifications: Bool   // /api/v2/notifications
    var notificationPolicy: Bool
    var filtersV2: Bool
    var editHistory: Bool
    var translation: Bool            // configuration.translation.enabled
    var translationLanguages: [String: [String]]

    // Nextcloud Social extensions
    var onlyMediaFilter: Bool
    var onlyVideoFilter: Bool
    var onlyNewsFilter: Bool
    var hlsLadder: Bool              // any attachment seen with hls_url != nil
    var watchPositions: Bool         // /api/v1/videos/continue
    var stories: Bool
    var collections: Bool
    var emojiReactions: Bool
    var quotePosts: Bool
    var mediaFromNextcloudFiles: Bool
    var preferencesWrite: Bool       // PUT /api/v1/preferences

    // Server-stated limits
    var limits: ServerLimits
}
```

Detection order, all of it tolerant of failure:

1. `GET /.well-known/nodeinfo/2.1`, falling back to `2.0`, for
   `software.name` / `software.version`. This is served at the **domain root**
   on Nextcloud Social even when the API is not.
2. `GET {apiBase}/api/v2/instance`, falling back to `/api/v1/instance`. Gives
   limits, `urls`, `configuration`, `api_versions`, `vapid_key`.
3. Cheap `HEAD`/`GET` probes with `limit=1` for the extension routes that have
   no announcement: `/api/v1/videos/continue`, `/api/v1/stories/carousel`,
   `/api/v1/collections`. 200 → available; 404 → absent; 401 → available but
   unauthorised (treat as available).
4. `only_media` / `only_video` / `only_news` are probed by requesting
   `/api/v1/timelines/public?limit=1&only_video=true` and checking for a **422**
   (Mastodon accepts unknown query parameters silently, so absence of 422 is
   not proof — additionally gate on `softwareName == "nextcloud social"` for
   `only_video` and `only_news`, which are this app's own).
5. `hlsLadder`, `emojiReactions` and `quotePosts` are latched on first sighting
   of the relevant field in a decoded entity, and persisted.

**Rule: a capability that cannot be determined is treated as absent.** The app
must be fully usable with every flag false.

## 5. Pagination

Cursor-based. `limit`, `max_id`, `min_id`, `since_id`. Default 20, cap 50.

The `Link` header is the only cursor the app reads:

```
Link: <…/api/v1/timelines/home?limit=20&max_id=41>; rel="next",
      <…/api/v1/timelines/home?limit=20&min_id=60>; rel="prev"
```

- `next` is sent only while a further page may exist. **A page shorter than
  `limit` is the last one.**
- `prev` is sent whenever the page is not empty.
- Every filter the caller sent survives into both links — so following `next`
  preserves `only_video` and friends automatically. **Follow the URL; do not
  rebuild it.**

Routes that send no `Link` header and must be paged manually or not at all:
`/api/v1/blocks`, `/api/v1/mutes` (no cursor at all), `/api/v1/scheduled_statuses`,
and any remote follower collection.

`/api/v1/followed_tags` pages on the followed-tag row id, not a status id.

`/api/v1/notifications` drops entries whose sub-type has no Mastodon name, so a
page can be shorter than `limit` while more remain — the server accounts for
this and still sends `next`. Trust the header, not the count.

## 6. Errors

```swift
enum APIError: Error, Sendable {
    case unauthorised           // 401 — token revoked or missing
    case forbidden              // 403 — scope or permission
    case notFound               // 404
    case unprocessable(String)  // 422 — validation; message is user-facing
    case rateLimited(retryAfter: TimeInterval?)   // 429
    case server(status: Int, body: String?)       // 5xx
    case decoding(underlying: Error, context: String)
    case transport(URLError)
    case cancelled
}
```

Mastodon-shaped errors are `{"error": "...", "error_description": "..."}`.
Nextcloud Social's Custom Local API uses a different envelope
(`{"result": …, "status": 1}`) — the app touches only two of those routes
(`/api/v1/global/accounts/search`, `/api/v1/global/tags/search`) and must
decode them separately. Prefer `/api/v2/search` and
`/api/v1/accounts/search` for everything; the global ones are for finding
people on *other* servers.

**401 handling:** a revoked token returns
`{"error": "the access_token was revoked"}`. On 401 the app marks the account
as needing re-authentication, stops all polling for it, keeps its cached data,
and shows a non-destructive "Sign in again" banner. It must never silently
delete the account or its cache.

**422 handling:** the message is written for a human and is shown verbatim,
prefixed by what the app was trying to do.

**Rate limiting:** `/api/oembed`, `/api/v1/instance/peers`,
`/api/v1/instance/activity`, media uploads, `/media/playlist/*`, OAuth token and
revoke are all rate-limited, some per anonymous caller. On 429 back off with
`Retry-After` if present, otherwise exponential with jitter, and never retry a
write automatically.

## 7. Endpoint inventory used by the app

Grouped by the feature that needs it. `{base}` is the resolved API base.

**Session** — `POST /api/v1/apps` · `GET /oauth/authorize` · `POST /oauth/token` ·
`POST /oauth/revoke` · `GET /.well-known/oauth-authorization-server` ·
`GET /api/v1/apps/verify_credentials` · `GET /api/v1/accounts/verify_credentials`

**Instance** — `GET /api/v2/instance` · `GET /api/v1/instance/` ·
`/instance/rules` · `/instance/extended_description` · `/instance/privacy_policy` ·
`/instance/terms_of_service` · `/instance/translation_languages` ·
`GET /api/v1/custom_emojis` · `GET /api/v1/preferences` · `PUT /api/v1/preferences` ·
`GET /api/v1/instance/peers` · `/instance/activity` · `/instance/domain_blocks`
(all three public, and all three may legitimately answer with nothing)

**Timelines** — `GET /api/v1/timelines/{home|public|direct|favourites}/` ·
`/timelines/tag/{hashtag}` · `/timelines/list/{id}` · `/timelines/link` ·
`GET /api/v1/favourites/` · `GET /api/v1/bookmarks` · `GET /api/v1/conversations` ·
`POST /api/v1/conversations/{id}/read` · `DELETE /api/v1/conversations/{id}` ·
`POST /api/v1/conversations/read_all` · `GET /api/v1/conversations/unread_count`

**Statuses** — `GET /api/v1/statuses/{id}` · `/context` · `/history` ·
`/source` · `/favourited_by` · `/reblogged_by` · `/quotes` · `/reactions` ·
`POST /api/v1/statuses` · `PUT /api/v1/statuses/{id}` ·
`DELETE /api/v1/statuses/{id}` · `POST /api/v1/statuses/{id}/{favourite|unfavourite|reblog|unreblog|bookmark|unbookmark|pin|unpin|mute|unmute}` ·
`POST /api/v1/statuses/{id}/translate` · `/react` · `/unreact` ·
`POST /api/v1/polls/{id}/votes` · `GET /api/v1/polls/{id}`

**Scheduled** — `GET/PUT/DELETE /api/v1/scheduled_statuses[/{id}]`

**Accounts** — `GET /api/v1/accounts/{id}` · `/statuses` · `/followers` ·
`/following` · `/featured_tags` · `/lists` · `GET /api/v1/accounts/relationships` ·
`/accounts/lookup` · `/accounts/search` · `/accounts/familiar_followers` ·
`POST /api/v1/accounts/{id}/{follow|unfollow|block|unblock|mute|unmute|note|pin|unpin|remove_from_followers}` ·
`PATCH /api/v1/accounts/update_credentials` ·
`GET/POST/DELETE /api/v1/follow_requests…` · `GET /api/v1/blocks` · `/mutes` ·
`GET/POST/DELETE /api/v1/domain_blocks` · `GET /api/v1/endorsements`

**Notifications** — `GET /api/v2/notifications` · `/{group_key}` ·
`/{group_key}/accounts` · `POST /api/v2/notifications/{group_key}/dismiss` ·
`GET /api/v2/notifications/unread_count` · v1 equivalents as fallback ·
`GET/PATCH /api/v2/notifications/policy` (v1 fallback) ·
`GET /api/v1/notifications/requests…` · `GET/POST /api/v1/markers`

**Link previews** — `GET /api/v1/statuses/{id}/card`, on the **detail screen
only**. The card is inlined in the status entity everywhere else; asking makes
the server build and cache one for a post that had none, so a timeline that
asked per row would be a request storm for a decoration. `{}` for a post with
no link is Mastodon's answer, not an error.

**Search & discovery** — `GET /api/v2/search` · `GET /api/v1/trends/{tags|statuses|links}` ·
`GET /api/v2/suggestions` · `DELETE /api/v1/suggestions/{id}` ·
`GET /api/v1/directory` (the instance's own profile directory, ordered `active`
or `new`; its `local` parameter is accepted by the server and ignored, so it is
not sent) · `GET /api/v1/tags/{hashtag}` · `/follow` · `/unfollow` ·
`GET /api/v1/followed_tags` · `GET/POST/DELETE /api/v1/featured_tags…`

**Lists** — `GET/POST/PUT/DELETE /api/v1/lists[/{id}]` ·
`GET/POST/DELETE /api/v1/lists/{id}/accounts`

**Filters** — `GET/POST/PUT/DELETE /api/v2/filters[/{id}]` and its keywords and
statuses sub-resources

**Media** — `POST /api/v2/media` (fallback `/api/v1/media`) ·
`PUT /api/v1/media/{id}` · `GET /api/v1/media/{id}` ·
`POST /api/v1/media/from-file` *(Nextcloud)*

**Video** *(Nextcloud)* — `POST/DELETE /api/v1/statuses/{id}/watched` ·
`GET /api/v1/videos/continue` · `GET /media/hls/{uuid}/master.m3u8` ·
`GET /media/playlist/{nid}`

**Stories** *(Nextcloud)* — `GET /api/v1/stories/carousel` · `/self` ·
`GET /api/v1/accounts/{id}/stories` · `POST /api/v1/stories` ·
`POST /api/v1/stories/{id}/seen` · `DELETE /api/v1/stories/{id}` ·
`POST /api/v1.1/stories/self-expire/{id}` ·
`GET /api/v1.2/stories/{carousel|viewers|reactions|mention-autocomplete}` ·
`POST /api/v1.2/stories/{react|comment}` — the v1.2 routes are Pixelfed's and
name the story in a **`sid` parameter**, never in the path

**Collections** *(Nextcloud)* — `GET/POST/PUT/DELETE /api/v1/collections[/{id}]` ·
`GET/POST /api/v1/collections/{id}/items`

**Safety** — `POST /api/v1/reports` · `GET /api/v1/announcements` ·
`POST /api/v1/announcements/{id}/dismiss` ·
`PUT/DELETE /api/v1/announcements/{id}/reactions/{name}`

**Your year** — `GET /api/v1/annual_reports` · `/{year}` · `/{year}/state` ·
`POST /api/v1/annual_reports/{year}/{generate|read}`

**Account deletion** *(Nextcloud session, not a bearer token)* —
`POST /api/v1/account/delete`, sent with the Nextcloud **app password** as HTTP
Basic. See [03-auth-and-accounts.md](03-auth-and-accounts.md) §5.

**Direct messages** — `GET /api/v1.1/direct/compose/mutuals`, the people a
message can be started with. The rest of Pixelfed's `direct/thread` family —
`GET /thread`, `POST /thread/send`, `DELETE /thread/message` — is deliberately
**not** used: it is a second representation of the same direct statuses the
Messages screen already reads, writes and deletes through Mastodon's own routes,
and two code paths over one set of posts is how the two drift.

### Served, and deliberately not called

- `GET /api/oembed` — for *other websites* embedding a post, not for a client.
  It serves local public posts only and answers `type: link` with an author and
  a provider, which is strictly less than `/api/v1/statuses/{id}` already gives.
- `GET /api/saved_searches/list.json` — returns a hardcoded `[]`. Recent
  searches are kept on the device, which is the feature it looks like.
- `POST /api/v1/statuses/{id}/dislike`, `/undislike` — **no route exists.** The
  server serialises `dislikes_count` and `disliked` on a video status and
  federates what PeerTube sends, but `DislikeService` is wired to no controller.
  The row shows the count read-only until that changes.

**Moderation** *(Nextcloud administrator only, checked per route)* —
`GET /api/v1/admin/reports[/{id}]` ·
`POST /api/v1/admin/reports/{id}/{resolve|reopen|assign_to_self|unassign}` ·
`GET /api/v1/admin/accounts[/{id}]` ·
`POST /api/v1/admin/accounts/{id}/{action|unsilence|unsuspend|unsensitive}` ·
`GET /api/v1/admin/trends/{tags|statuses|links}` ·
`POST /api/v1/admin/trends/{kind}/{id}/{approve|reject}`. Instance configuration
routes — domain, email and IP blocks, retention, measures, dimensions — are
served and deliberately not called.
