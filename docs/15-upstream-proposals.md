# 15 — Upstream proposals for the Social app on Nextcloud

Answers to the server questions in [14-open-questions.md](14-open-questions.md)
§3, read from the source, and the §4 proposals written as issues ready to file.

Everything here was read from a shallow clone of `nextcloud/social` `master` at
`9ab8a7a` (1 October 2026, app version `0.26.105`). Paths are relative to that
repository. Line numbers will drift; the class and method names will not.

The app's `appinfo/info.xml` points bug reports at `alohasocial/social`
(lines 77–78), not at `nextcloud/social`. File wherever the maintainers actually
triage; the texts below work for either.

---

## 1. Answers to the open server questions

### 1.1 Does `POST /api/v1/statuses` honour `Idempotency-Key`?

**Yes, with three holes.**

`StatusApiController::statusNew()` (`lib/Controller/StatusApiController.php:124`)
reads the header, scopes it to the credential, and returns the earlier status
on a repeat:

- `idempotencyKey()` (`:348–357`) hashes `bearer | key` with SHA-256, so two
  clients can use the same key and the token never lands in the cache.
- `statusForIdempotencyKey()` (`:363–383`) looks the key up in `DurableCache`
  under `social_idempotency` and answers the stored status with **200** if it
  still exists (`:157–161`).
- `rememberIdempotencyKey()` (`:385–393`) stores the new status's `nid` for
  `IDEMPOTENCY_TTL = 3600` s (`:81`) — the same hour Mastodon keeps it.
  `DurableCache` falls back to a table (`social_durable_cache`) when there is no
  memcache, so it holds on a small instance too (`lib/Service/DurableCache.php:21–40`).

The holes:

1. **It is check-then-act, not a claim.** The key is written only *after*
   `createPost()` returns (`:264`, `:276`). A retry that arrives while the first
   request is still running finds nothing and posts again. That is exactly the
   flaky-link case: the client times out at 30 s, the server is still
   federating, the retry lands mid-flight.
2. **Scheduled posts bypass it.** The `scheduled_at` branch returns at
   `:143–151`, before the lookup; the comment says so. A retried schedule
   creates two `social_scheduled` rows.
3. **Held-for-review posts bypass it.** A post the first-post review holds
   returns 422 with `held_for_review: true` (`:233–262`) without remembering
   the key. A retry holds a second copy.

**Client change: a small one.** Keep sending the key (it already does,
`APIClient.swift:131`). Add a safety net for the window the server does not
cover:

- **Never retry concurrently.** After a timeout, wait for the original task to
  finish or be cancelled, then wait a further 5 s before retrying.
- **Pre-flight before any retry** of an immediate post: `GET
  /api/v1/accounts/{me}/statuses?limit=5` and treat a status created in the last
  five minutes with identical `text` (from `/source` if needed), identical
  `media_attachments` ids and the same `in_reply_to_id` as "already posted".
  Adopt it, do not retry.
- **For a scheduled post**, pre-flight against `GET /api/v1/scheduled_statuses`
  and match on `params.text`, `scheduled_at` and `media_ids`.
- **A 422 with `held_for_review: true` is final.** Show "waiting for a
  moderator", keep the draft read-only, never retry. The server's message
  already says "there is no need to write it again".

The upstream fix is a two-line claim — see issue 2.7.

### 1.2 Does status creation accept `scheduled_at`?

**Yes.** `statusNew()` hands any non-empty `scheduled_at` to
`ScheduledStatusService` before creating anything
(`lib/Controller/StatusApiController.php:136–151`) and answers Mastodon's
`ScheduledStatus` entity with 200.

- Parsed by `requestedTime()` (`lib/Service/ScheduledStatusService.php:106–122`)
  with `strtotime()`. An unparsable value is a **422**
  (`InvalidActionException` → 422, `lib/Controller/MastodonApiController.php:464`),
  never a silent immediate post.
- At least **5 minutes** ahead (`MIN_LEAD_TIME = 300`, `:53`, enforced at
  `:317–326`), at most `MAX_PENDING = 300` waiting per account (`:68`), plus a
  daily cap (`:344–353`). All 422.
- Content is validated at schedule time (`assertPublishable()`, `:369`), so a
  refusal reaches the person rather than the cron.
- Published by `Cron\ScheduledPosts` (`lib/Cron/ScheduledPosts.php:53`).

**Client change: none to behaviour.** The +5 minute minimum in
[07-composer.md](07-composer.md) §5 matches. Show the 422 message verbatim;
it names the limit. Remove the "where … accepts" hedge from doc 07.

### 1.3 Does OAuth accept `urn:ietf:wg:oauth:2.0:oob` for a new registration?

**Yes, and the code is shown on a page.** But it is **60 characters**, not six.

- `POST /api/v1/apps` (`lib/Controller/OAuthController.php:159`) splits
  `redirect_uris` on newlines and stores them as given (`:171–190`).
  `ClientService::createApp()` (`lib/Service/ClientService.php:69–82`) checks
  only that the list is non-empty. No URI validation, so `oob` registers like
  anything else. The server itself registers PeerTube clients with `oob`
  (`ClientService.php:103–115`).
- `GET /oauth/authorize` (`OAuthController.php:236`) requires a Nextcloud login
  (it is `#[NoAdminRequired]`, not `#[PublicPage]`), then checks the
  `redirect_uri` is one the client registered (`confirmData()`,
  `ClientService.php:282–286`). `oob` passes because it was registered.
- `POST /oauth/authorize` (`OAuthController.php:456`) mints the code and, for
  `oob`, renders the consent template with the code in it (`:494–512`) — a
  selectable field with a **Copy code** button (`src/views/OAuth2Authorize.vue`).
- `POST /oauth/token` (`:576`) requires the same `redirect_uri=oob`. PKCE
  `S256` is supported and bound to the code (`ClientService::CODE_CHALLENGE_METHODS`,
  `:44`).

The catch: the code is `token(60)` (`ClientService.php:127`) from
`[A-Za-z0-9]` (`lib/Tools/Traits/TStringTools.php:29–39`), valid for
**10 minutes** (`TIME_CODE_TTL = 600`, `:35`). [03-auth-and-accounts.md](03-auth-and-accounts.md)
§7 and `AlohaSocialTV/TVApp.swift:61` both say "six characters". Nobody types
60 mixed-case characters with a Siri Remote in ten minutes.

**Client change: yes — the tvOS sign-in design.** Options, best first:

1. **Phone as relay.** The TV registers its app with *two* redirect URIs,
   `alohasocial://oauth` and `oob`, generates the PKCE verifier and `state`, and
   shows a QR code holding the full authorise URL (with `redirect_uri=alohasocial://oauth`,
   the S256 challenge and `state`) plus a pairing id. The iOS app scans it, runs
   `ASWebAuthenticationSession` on that URL, receives the code on its callback,
   and hands code and `state` to the TV over the local network
   (Bonjour/`Network.framework`). The TV exchanges it with its own verifier and
   secret. The verifier never leaves the TV, so an intercepted code is useless.
2. **Login Flow v2 on the TV.** Poll-based and designed for exactly this.
   Untested but plausible from the source: `currentSession()`
   (`lib/Controller/MastodonApiController.php:226–239`) accepts a Nextcloud
   session when `passesCSRFCheck()` is true, and Nextcloud's
   `Request::passesCSRFCheck()` returns true for any request carrying
   `OCS-APIRequest: true` (`nextcloud/server`
   `lib/private/AppFramework/Http/Request.php:436`). An app password sent as
   HTTP Basic plus that header should therefore authenticate the whole Social
   API — with no OAuth scope limit, which is the price. Verify with one
   `curl -u user:app-password -H 'OCS-APIRequest: true' …/api/v1/accounts/verify_credentials`
   before relying on it.
3. **Typed `oob` code** as the last resort, with the field accepting paste
   from Continuity Keyboard on a nearby iPhone.

Whichever wins, fix the "six characters" claim in doc 03 and `TVApp.swift`.

### 1.4 `only_media` / `only_video` / `only_news`: 422 or ignored?

**All three are implemented, and unknown parameters are silently ignored.
Nothing here ever answers 422 for a parameter.**

- Declared on `timelines()` (`lib/Controller/TimelineApiController.php:84–94`),
  `tag()` (`:204–206`), the list timeline (`lib/Controller/ListController.php:375–377`)
  and `only_media` on account statuses (`lib/Controller/AccountApiController.php:723`).
- Also read from the raw request by `ProbeOptions::fromArray()`
  (`lib/Model/Client/Options/ProbeOptions.php:397–411`), which reads a **fixed
  list** of keys. Anything not on it is dropped.
- Applied in SQL: `StreamTimelines::filterMedia()` / `filterNews()`
  (`lib/Db/StreamTimelines.php:214–262`) → `limitToMedia()` / `limitToVideo()` /
  `limitToNews()` (`lib/Db/SocialLimitsQueryBuilder.php:492`, `:536`, `:617`), on
  the indexed `media_kind` / `news_kind` columns decided at write time.
- An invalid `media_type` is coerced to `''` (`ProbeOptions.php:370`), i.e.
  ignored. The only 422 on that route is an unknown **timeline name**
  (`TimelineApiController.php:115–131`).
- Nextcloud's controller dispatch binds only declared parameters, so an extra
  query parameter never errors on any route.

So `acceptsNarrowing()` in `CapabilityDetector.swift:174` returns 2xx for
`only_video=true`, `only_short=true` and `only_banana=true` alike. It detects
nothing; it only turns a transient network failure into "absent" for 24 hours.

**Client change: yes, a simplification.** Drop the probe. Set
`onlyMediaFilter`, `onlyVideoFilter`, `onlyNewsFilter` from
`isNextcloudSocial` alone (nodeinfo `software.name` is `nextcloud-social`,
`lib/Controller/OAuthController.php:67`; the `contains("nextcloud") &&
contains("social")` test handles it, but doc 02 §4 and the fixtures in
`DiscoveryTests.swift` spell it differently and should be corrected). Fix
doc 02 §4 step 4 accordingly. **Never send a narrowing the server has not
announced** — an ignored `only_short` would silently return the unfiltered
timeline. This is why issue 2.1 asks for an announcement.

### 1.5 Does `Account.avatar` still return `""`?

**Yes.** `Person::exportAsLocal()` (`lib/Model/ActivityPub/Actor/Person.php:1418`)
only computes `$avatar` inside `if ($this->hasIcon())` (`:1419–1427`), where it
already falls back to `placeholderImage()`. Without an icon it emits
`$avatar ?? $this->getAvatar()` (`:1459–1460`), and `getAvatar()`
(`:191–198`) returns the stored string, default `''`. Any remote actor that
publishes no `icon` hits it.

`header` is worse: `getHeader()` (`:214–220`) falls back to `getAvatar()`, so it
is either the **avatar image** reused as a banner, or `''`.

**Client change: none.** Keep the defensive decode. Add one rule to doc 04 §2:
*a `header` equal to `avatar` is "no header".* Fix upstream in issue 2.8.

### 1.6 The ActivityPub attachment shape

**Fixed on `master`, and never affected this client.**

- Outbound: `Stream::jsonSerialize()` (`lib/Model/ActivityPub/Stream.php:2574–2592`)
  maps every attachment through `asWireDocument()` → `MediaAttachment::asDocument()`
  (`lib/Model/Client/MediaAttachment.php:344–390`) whenever the format is not
  local: `type: Document`, full `mediaType`, `url`, `name` as alt text, and
  `width`/`height`/`blurhash`/`focalPoint` only when known. The comment cites
  Pixelfed dropping pictures as the reason.
- Inbound: both shapes are read (`MediaAttachment.php:195` takes `media_type`
  or `mediaType`; `lib/Service/PostImportService.php:1198` reads `attachment` and
  `media_attachments`).
- The client API (`FORMAT_LOCAL`) never carries `attachment` at all; it serves
  `media_attachments` in Mastodon's client shape.

**Client change: none.** Strike §3 item 7 from doc 14 and the corresponding
note in doc 04 §2. One adjacent find: `Document::import()`
(`lib/Model/ActivityPub/Object/Document.php:379–404`) ignores the `width` and
`height` a Mastodon peer sends on an inbound `Document`, which is half of why
`meta` is missing for remote video — see issue 2.4.

### 1.7 Two client defects found on the way

Not in §3, but they fell out of reading the media code:

- **Video duration is in the wrong place for local uploads.** On upload the
  server writes the running time to `meta.duration`
  (`lib/Service/CacheDocumentService.php:569–575`), not
  `meta.original.duration`; only PeerTube videos get both
  (`lib/Service/PeerTubeService.php:1065–1076`). `MediaAttachment.duration`
  (`MediaAttachment.swift:131`) reads only `meta.original.duration`, so every
  local video defers Shorts classification. **Change:** decode top-level
  `meta.duration` and fall back to it.
- **`frame_rate` is a number here, a string in Mastodon.** `AttachmentMetaDim`
  serialises `frame_rate` as a float (`lib/Model/Client/AttachmentMetaDim.php:134`);
  Mastodon sends `"30/1"`. `Dimensions.frameRate` is `String?`, and the whole
  `Meta` is decoded with `try?`, so one numeric `frame_rate` silently discards
  width, height and duration. **Change:** decode `frameRate` leniently (string
  or number), never let it fail `Meta`.

Both are fixed in the client: `Meta` and `Dimensions` decode field by field,
and `MediaAttachment.duration` falls back to `meta.duration`
(`MediaMetaTests`).

### 1.8 Summary

Every client change in the last column is made, except the tvOS phone relay:
the TV shows a QR code and the code is pasted with the iPhone's Apple TV
keyboard, which is good enough until the relay is built.

| # | Question | Answer | Client change |
|---|---|---|---|
| 1 | `Idempotency-Key` | Honoured, 1 h; not a claim, skips scheduled and held posts | Serialise retries; pre-flight against own recent statuses / scheduled list; held = final |
| 2 | `scheduled_at` | Accepted; ≥ 5 min, caps, 422 on bad input | Drop the hedge in doc 07 |
| 3 | `oob` | Accepted; code shown on a page, 60 chars, 10 min | Redesign tvOS sign-in; fix "six characters" |
| 5 | narrowing params | Implemented; unknown params ignored, never 422 | Remove probe; gate on software name |
| 6 | `avatar: ""` | Still happens; `header` reuses avatar | None; treat `header == avatar` as none |
| 7 | attachment shape | Fixed; client API unaffected | None; strike from doc 14 |
| — | `meta.duration`, `frame_rate` | Found while reading | Read `meta.duration`; lenient `frame_rate` |

---

## 2. Issues to file

Written to be pasted. Each names the files to touch. Mastodon API shapes are
from Mastodon's own documentation (4.3/4.4); check the current page when
filing.

### 2.1 `only_short`: an exact short-video narrowing

**Title:** Timelines: add `only_short` narrowing, decided on write, and announce supported narrowings

**Problem**

`only_video` gives clients every video. A Shorts/Loops-style feed needs short,
portrait videos, so clients filter client-side: fetch `only_video`, discard most
of it, over-fetch to fill a page, and defer anything whose `meta` is missing.
On a server with a few short videos among many long ones, a Shorts page can need
eight requests and still come back half empty.

Clients also cannot tell which narrowings a server honours: `ProbeOptions::fromArray()`
(`lib/Model/Client/Options/ProbeOptions.php:397–411`) ignores unknown keys, so
`only_short=true` on a server without it silently returns the unfiltered
timeline.

**Proposal**

1. A write-time column, like `media_kind` and `news_kind`:
   `social_stream.short_kind`, `VARCHAR(5)`, nullable — `'short'`, `''`, or
   `NULL` for "not classifiable yet".
2. The rule, in one static method beside `Stream::mediaKindOf()`
   (`lib/Model/ActivityPub/Stream.php:757`), so it cannot drift:

   ```
   short  ⇔  exactly one attachment of type video|gifv (or subtype Video)
             AND ( (duration ≤ 180 s AND width/height ≤ 1.0)
                   OR duration ≤ 60 s
                   OR hashtags ∩ {loops, short, shorts, reel} ≠ ∅ )
   NULL   ⇔  one video attachment but no duration or no dimensions yet
   ''     ⇔  everything else
   ```

3. `only_short=true` on every route that takes `only_video`:
   `TimelineApiController::timelines()` / `tag()`,
   `ListController` list timeline, `AccountApiController` account statuses.
   It is a narrowing of `only_video` and wins over it.
4. Announce the narrowings a server applies, because a probe cannot find them:

   ```json
   "configuration": {
     "timelines": { "narrowing": ["only_media", "only_video", "only_news", "only_short"] }
   }
   ```

   in both `/api/v1/instance` and `/api/v2/instance`
   (`InstanceService::configuration()`, `lib/Service/InstanceService.php:312`).
   Unknown keys under `configuration` are ignored by Mastodon clients.

**Implementation pointers**

- Schema: add the column and an index `(short_kind, nid)` named `social_s_sk` in
  `lib/Migration/Version1000Date20221118000002.php`, both in the `createTable`
  branch (beside `media_kind`, `:800`, index `:811`) and the upgrade branch
  (`:959–964`). Add `'short_kind'` to the `TABLE_STREAM` column list in
  `lib/Db/CoreRequestBuilder.php:665–700`.
- Backfill: a new dated step modelled on
  `lib/Migration/Version1000Date20260917000003.php` (batches of 5000, PHP-side
  classification from the stored `attachments` JSON).
- Write: `StreamRequest::save()` (`lib/Db/StreamRequest.php:172–189`), `update()`
  (`:296–307`) and `setRecoveredRemoteAttachments()` (`:488–497`) set it with
  the same arguments as `media_kind`.
- Reclassify: when `CacheDocumentService::generatePoster()` or
  `saveRemoteFileToCache()` learn a video's dimensions/duration, reset
  `short_kind` to `NULL` on posts carrying that document and let a `TimedJob`
  reclassify `NULL` rows (cheap: index on `(short_kind, nid)`).
- Read: `limitToShort()` in `lib/Db/SocialLimitsQueryBuilder.php` beside
  `limitToVideo()` (`:536`); applied in `StreamTimelines::filterMedia()`
  (`lib/Db/StreamTimelines.php:237`) before the `only_video` branch; add
  `isOnlyShort()` to the join-path condition at `:354–355`.
- Parse: `ProbeOptions` gains `onlyShort` (`fromArray()` and `jsonSerialize()`),
  so the `Link` header carries it (`MastodonApiController.php:742`).
- `NULL` rows are excluded from `only_short`. A client that wants them can still
  ask `only_video`.

**Acceptance criteria**

- `GET /api/v1/timelines/public?only_short=true` returns only posts the rule
  classifies `short`, newest first, at the same cost as `only_video`.
- Works on home, public, tag, list and account statuses; preserved in `Link`.
- `configuration.timelines.narrowing` lists exactly the narrowings applied.
- A local portrait 30 s upload is `short` immediately when ffmpeg is present;
  a remote one becomes `short` within one cron run of being cached.
- Unit tests over the classifier with the boundary cases (60 s, 180 s, aspect
  exactly 1.0, two videos, no meta).

### 2.2 Web Push (`/api/v1/push/subscription`)

**Title:** Implement Mastodon Web Push: `/api/v1/push/subscription`, VAPID key, RFC 8291 delivery

**Problem**

Every Mastodon client polls this server. `vapid_key` is answered `''`
(`lib/Controller/OAuthController.php:219`, `lib/Controller/ApiController.php:83`, `:95`)
and `/api/v1/push/*` is a 404 (`docs/Mastodon-Compatibility.md:159–161`, gap #3
at `:636`). Third-party mobile clients get no notifications at all unless the
person also installs the Nextcloud app. The compatibility document estimates
this at weeks; most of the hard parts already exist.

What exists:

- **One choke point.** Every notification that reaches a person goes through
  `NotificationService::emit()` (`lib/Service/NotificationService.php:545–616`):
  after the suppression checks, it maps the type via `SUBJECTS` (`:70–82`:
  mention, favourite, reblog, follow, follow_request, update, poll, status) and
  calls `INotificationManager::notify()` (`:598`). Callers:
  `SocialAppNotificationInterface::save()` (`lib/Interfaces/Internal/SocialAppNotificationInterface.php:53`),
  `LikeInterface` (`lib/Interfaces/Object/LikeInterface.php:182`),
  `AnnounceInterface` (`lib/Interfaces/Object/AnnounceInterface.php:286`), and
  the `on*()` methods of `NotificationService` itself.
- **A library already in the Nextcloud ecosystem.** The `notifications` app
  depends on `minishlink/web-push` `^11.0` for its own browser push
  (`nextcloud/notifications` `composer.json`, `lib/WebPushClient.php`). It is
  prefixed by Mozart to `OCA\Notifications\Vendor\…`, so it is **app-private and
  must not be called from Social** — but it proves the dependency is acceptable
  and shows the packaging. Nextcloud server's own `3rdparty` has
  `firebase/php-jwt` and `phpseclib` but nothing that does RFC 8291.
- The notifications app's Web Push is **not a substitute**: its registration
  protocol (`/ocs/v2.php/apps/notifications/api/v2/webpush`, activation-token
  handshake) and its payloads are Nextcloud's own. Mastodon clients speak
  neither.

**Proposal — API (Mastodon's shape)**

All four routes need a bearer token with the **`push`** scope, and operate on
*the subscription of the token making the call*: one per access token, a new
`POST` replaces it.

`POST /api/v1/push/subscription`

| Param | Notes |
|---|---|
| `subscription[endpoint]` | HTTPS URL, ≤ 765 chars |
| `subscription[keys][p256dh]` | base64url, uncompressed P-256 point (65 bytes) |
| `subscription[keys][auth]` | base64url, 16 bytes |
| `subscription[standard]` | bool, Mastodon 4.4+. `true` → RFC 8291 `aes128gcm`; absent/`false` → legacy `aesgcm` (draft-04) with `Encryption`/`Crypto-Key` headers |
| `data[alerts][mention\|status\|reblog\|follow\|follow_request\|favourite\|poll\|update\|admin.sign_up\|admin.report]` | bool each, default false |
| `data[policy]` | `all` (default) \| `followed` \| `follower` \| `none` |

Answers a `WebPushSubscription`:

```json
{
  "id": "17",
  "endpoint": "https://push.example/…",
  "standard": true,
  "alerts": { "mention": true, "status": false, "reblog": true, "follow": true,
              "follow_request": true, "favourite": true, "poll": true,
              "update": false, "admin.sign_up": false, "admin.report": false },
  "policy": "all",
  "server_key": "BEm…"
}
```

- `GET /api/v1/push/subscription` → the same entity, or **404**
  `{"error":"Record not found"}`.
- `PUT /api/v1/push/subscription` → `data[alerts][…]`, `data[policy]` only;
  404 if none.
- `DELETE /api/v1/push/subscription` → `{}`, 200 even if there was none.

The pushed payload, encrypted to the subscription:

```json
{
  "notification_id": "123456",
  "notification_type": "mention",
  "preferred_locale": "en",
  "access_token": "",
  "icon": "https://cloud.example/…/avatar",
  "title": "Alice mentioned you",
  "body": "first 140 characters, plain text"
}
```

`access_token` is a deliberate deviation: the server stores only a hash of each
token (`lib/Db/ClientAuthRequest.php:105`, `SecretHasher`) and cannot echo it.
Send `""` and document that clients must route by endpoint, not by token.
`notification_id` is the id `/api/v1/notifications` serves for the same row, so
a client can fetch it.

**Proposal — VAPID (RFC 8292)**

- Generate once with `Minishlink\WebPush\VAPID::createVapidKeys()` on first
  need. Store in app config: `push_vapid_public` (plain), `push_vapid_private`
  as a **sensitive, lazy** value via `IAppConfig`, sealed with `ICrypto` the way
  `lib/Security/PrivateKeyCipher.php` seals actor keys. Subject:
  `mailto:` the instance contact email, else the instance URL.
- An `occ social:push:rotate-vapid` that regenerates and **deletes all
  subscriptions** (they are bound to the old key; clients resubscribe when
  `vapid_key` changes).
- Expose the public key, base64url uncompressed, where Mastodon clients look:
  - `vapid_key` on `POST /api/v1/apps` (`OAuthController.php:219`) and
    `GET /api/v1/apps/verify_credentials` (`ApiController.php:83`, `:95`);
  - `configuration.vapid.public_key` in `/api/v2/instance`
    (`lib/Model/Instance.php:399–430`, via `InstanceService::configuration()`);
  - `server_key` on the subscription entity.
  - Keep answering `''` while the admin has push disabled.

**Proposal — delivery (RFC 8030 / 8291)**

- Encrypt with `minishlink/web-push` (`Encryption::encrypt()` and
  `VAPID::getVapidHeaders()`; check signatures for the pinned version), honouring
  each subscription's `standard` flag (`aes128gcm` vs `aesgcm`). Pad to a fixed
  bucket; keep the plaintext under 3 KB.
- **Send through `OCP\Http\Client\IClientService`, not the library's Guzzle
  pool.** That keeps Nextcloud's proxy settings and its refusal of local and
  private addresses (`allow_local_remote_servers`), which matters because
  `endpoint` is a URL a client chose: without it this is an SSRF primitive.
  It also avoids shipping a second Guzzle; if the library's HTTP layer must be
  bundled, prefix it with Mozart as `nextcloud/notifications` does.
- Headers: `TTL: 172800`, `Urgency: high` for mention/follow_request,
  `normal` otherwise, `Topic` = notification id (so a retry replaces, not
  duplicates).
- Responses: 201/202 → success; **404/410 → delete the subscription**; 413 →
  log, shrink body; 429/5xx → retry with backoff, give up after 3 attempts or
  48 h.
- **Not in the inbox request.** Inbox delivery is synchronous and other servers
  time out. Enqueue a `QueuedJob` per (subscription, notification) via `IJobList`
  and let a dedicated `TimedJob` flush the queue every minute. Do not put this on
  `Cron\Queue`: it runs every 12 minutes (`lib/Cron/Queue.php:56`), which is too
  slow for a notification. Where `notify_push` is installed, flushing at the end
  of the request with a 2 s connect / 5 s total timeout is acceptable, falling
  back to the job.

**Which events push**

Hook `NotificationService::emit()` immediately after
`$this->notificationManager->notify($raised)` (`:598`), so a push is exactly as
suppressed as a bell entry (blocks, mutes with notifications hidden,
`isSuppressed()` `:735`, the notification policy). Map `SUBJECTS` 1:1 to Mastodon
`notification_type`. Then, per subscription of the recipient's user:

1. alert for that type enabled;
2. `policy`: `followed` → actor is followed by the recipient; `follower` →
   actor follows the recipient; `none` → nothing; use `FollowsRequest`;
3. enqueue.

`admin.sign_up` and `admin.report`: raise from the sign-up and
`ReportService` paths for users who are Nextcloud admins (the admin routes
already check this per route).

**Lifecycle**

Delete subscriptions when: the token is revoked (`POST /oauth/revoke`,
`OAuthController.php:664`; `ClientService::revokeToken()` `:265` and
`revokeAuthorizationOf()` `:204`; `ClientAuthRequest::revoke()` `:172`), the
authorisation is replaced on re-consent, the user is deleted
(`lib/Listeners/UserDeletedListener.php`), the push service answers 404/410,
or the VAPID key rotates.

**Scopes**

Add `'push'` to `OAuthController::SCOPES` (`:696–707`) and to
`/.well-known/oauth-authorization-server`. Map the four new route methods to
`['push']` in `MastodonApiController::ROUTE_SCOPES` (`:256`). `push` has no
broad form; `read`/`write` do not grant it, as in Mastodon.

**Routes**

A new `lib/Controller/PushApiController.php extends MastodonApiController`, with
`#[FrontpageRoute]` attributes like every other controller (see the comment in
`appinfo/routes.php`; these paths have no slash-swallowing parameter, so nothing
needs `routes.php`), plus `lib/Service/WebPushService.php`,
`lib/Db/PushSubscriptionRequest.php` and `lib/Model/Client/PushSubscription.php`.
An admin switch `push_enabled` (default on) in `ConfigService`, and a setup
check that sends a test push to nothing (VAPID header generation works, ext
requirements met).

**DB migration sketch**

In `lib/Migration/Version1000Date20221118000002.php` (the file that describes
the whole schema), plus `TABLE_PUSH_SUBSCRIPTIONS = 'social_push_sub'` and its
column list in `lib/Db/CoreRequestBuilder.php`:

```php
if (!$schema->hasTable('social_push_sub')) {
	$table = $schema->createTable('social_push_sub');
	$table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true, 'unsigned' => true]);
	// the authorisation the token belongs to: one subscription per token
	$table->addColumn('auth_id', Types::BIGINT, ['notnull' => true, 'unsigned' => true]);
	$table->addColumn('user_id', Types::STRING, ['length' => 64, 'notnull' => true]);
	$table->addColumn('endpoint', Types::STRING, ['length' => 765, 'notnull' => true]);
	$table->addColumn('p256dh', Types::STRING, ['length' => 128, 'notnull' => true]);
	$table->addColumn('auth_secret', Types::STRING, ['length' => 32, 'notnull' => true]);
	$table->addColumn('standard', Types::BOOLEAN, ['default' => false, 'notnull' => false]);
	$table->addColumn('alerts', Types::TEXT, ['notnull' => true]);          // JSON
	$table->addColumn('policy', Types::STRING, ['length' => 16, 'default' => 'all', 'notnull' => true]);
	$table->addColumn('failures', Types::INTEGER, ['default' => 0, 'notnull' => true]);
	$table->addColumn('last_success', Types::DATETIME, ['notnull' => false]);
	$table->addColumn('creation', Types::DATETIME, ['notnull' => false]);
	$table->setPrimaryKey(['id']);
	$table->addUniqueIndex(['auth_id'], 'social_push_auth');
	$table->addIndex(['user_id'], 'social_push_user');
}
```

The delivery queue lives in `oc_jobs` (`IJobList`), so no second table.
`endpoint` is not indexed (765 × utf8mb4 exceeds MySQL's key limit), and does
not need to be.

**Acceptance criteria**

- Ivory, Ice Cubes, Tusky (via UnifiedPush) and the official Mastodon iOS app
  subscribe and receive a mention within 60 s of the inbox accepting it.
- `standard=true` subscriptions get `aes128gcm`; others get `aesgcm`; both
  decrypt with a reference implementation in tests.
- Blocked/muted actors, a `policy` mismatch, or a disabled alert produce no push.
- An endpoint on `127.0.0.1` or a private range is refused at subscription with
  422 unless `allow_local_remote_servers` is on.
- 410 from the push service deletes the row; revoking the token deletes the row.
- `vapid_key` is non-empty in all three places when enabled and `''` when the
  admin disables push.
- No inbox request waits on a push service.

### 2.3 Streaming

**Title:** Real-time updates: extend the notify_push events now; decide on Mastodon streaming separately

**Problem**

`instance.urls` is `{}` (`lib/Service/InstanceService.php:188–190`), so every
client polls. A Mastodon-compatible `wss://…/api/v1/streaming` needs a process
that outlives a PHP request (gap #10, `docs/Mastodon-Compatibility.md:643`), and
long-lived SSE in PHP-FPM would pin one worker per connected client. Neither is
small.

But half of it already exists. `PushService` (`lib/Service/PushService.php`)
already pushes a `notify_custom` event named `social_timeline` through the
`notify_push` app to every local home/direct viewer of a new post (`:40–79`,
called from `lib/Interfaces/Object/NoteInterface.php:190`). And because
`NotificationService::emit()` calls `INotificationManager::notify()`, notify_push
already sends `notify_notification` for every Social notification. A client
holding a Nextcloud app password can open notify_push's websocket today. It
just cannot tell what changed.

**Proposal**

Phase 1 (days): make the notify_push channel useful to non-web clients.

- Give `social_timeline` a body: `{"timeline":"home","nid":"123"}` (and
  `"direct"` for direct viewers), so a client can fetch `min_id` instead of
  refreshing blind. notify_push already supports a JSON body on custom events.
- Add `social_delete` `{"nid":"123"}` (from `PostDeletedEvent`,
  `lib/Events/PostDeletedEvent.php`), `social_status_update` `{"nid":"123"}`
  (from `NotificationService::onStatusEdited()`, `:141`), and
  `social_notification` `{"id":"456","type":"mention"}` (from `emit()`).
- Announce it: `configuration.nextcloud.notify_push: true` in both instance
  documents when `OCA\NotifyPush\Queue\IQueue` resolves (`PushService::getQueue()`,
  `:86`).
- Document the events in `docs/API.md`.

Phase 2 (decision first): Mastodon's streaming API — `GET /api/v1/streaming/health`
and a WebSocket at `urls.streaming_api` / `configuration.urls.streaming`
accepting `stream=user|user:notification|public|public:local|hashtag|list|direct`
and emitting `update`, `delete`, `notification`, `status.update`,
`filters_changed`, `conversation`, `announcement` with stringified JSON
payloads. Options: a small sidecar (Rust or Go) reading the same Redis
notify_push uses and authenticating bearer tokens against `social_client_auth`;
or teaching notify_push itself a Mastodon-shaped endpoint. Either way it is a
deployment component, which is why it is a separate decision.

**Acceptance criteria (phase 1)**

- A client authenticated to notify_push with an app password receives
  `social_timeline {"timeline":"home","nid":…}` within a second of a followed
  account posting, and `social_notification` for each notification.
- Events carry ids only, never content.
- No behaviour change when notify_push is absent.

### 2.4 Complete video `meta` for every attachment

**Title:** Media: fill `meta.original.{width,height,duration,aspect}` for every video, local and remote

**Problem**

Clients need a video's aspect ratio to lay it out without a jump, and its
duration to show a running time before a frame loads. Today:

- **Local upload:** duration goes to top-level `meta.duration` only
  (`lib/Service/CacheDocumentService.php:569–575`); width/height come from the
  poster frame and only if ffmpeg is installed (`VideoThumbnailService::poster()`
  returns null otherwise). Without ffmpeg there is no `meta` beyond zeros.
- **Remote:** `Document::import()` (`lib/Model/ActivityPub/Object/Document.php:379–404`)
  ignores the `width` and `height` Mastodon and Pixelfed send on every
  `Document`. Streamed videos (no local copy) never get dimensions.
- `AttachmentMetaDim::import()` reads `duration` with `getInt()`
  (`lib/Model/Client/AttachmentMetaDim.php:117`), truncating 2.9 s to 2.
- `frame_rate` is serialised as a float (`:134`); Mastodon's is a string
  (`"30/1"`), and typed clients decoding Mastodon's schema fail on it.
- Only PeerTube videos get `meta.original.duration`
  (`lib/Service/PeerTubeService.php:1065–1076`).

**Proposal**

1. One place that completes video meta:
   `meta.original = {width, height, aspect, duration, frame_rate, bitrate}` and
   the top-level `duration` kept for compatibility. Called from
   `saveMediaFromTemp()` (`CacheDocumentService.php:539–585`),
   `generatePoster()` (`:96–150`) and remote caching.
2. Probe with **ffprobe** when present (same discovery as ffmpeg), else parse
   the container in PHP: `getid3` (GPL/LGPL/MPL) reads MP4/MOV/WebM headers
   without decoding, enough for width, height, duration and rotation. Honour
   the rotation matrix: a phone's portrait video is stored landscape with a 90°
   flag, and reporting 1920×1080 for it is the bug that breaks Shorts.
3. Import `width`/`height` (and PeerTube's `duration`) from inbound `Document`s
   in `Document::import()`, into `localCopySize` until a local probe overrides.
4. `duration` as float; `frame_rate` as Mastodon's string.
5. Backfill: extend `occ social:media:posters` (the command
   `generatePoster()` serves, `CacheDocumentService.php:85`) to complete meta
   for existing documents.

**Acceptance criteria**

- Every `video`/`gifv` attachment in the client API carries
  `meta.original.width`, `height` and `duration` (all > 0) when there is a local
  copy, or when the origin stated them — with or without ffmpeg.
- A portrait phone video reports `height > width`.
- `meta.original.frame_rate` is a string; `duration` keeps fractions.
- Issue 2.1's classifier has what it needs on write for local uploads.

### 2.5 Mastodon clients at the domain root

**Title:** Client API at the domain root without hand-written proxy rules

**Problem**

The Mastodon client API lives under `/index.php/apps/social/`. No Mastodon
client accepts a path prefix, so none can connect until the admin installs the
Apache proxy rules in `docs/Admin.md` (`:123–130`). `lib/SetupChecks/ClientApiAtRoot.php`
says so, and says PHP cannot fix it: Nextcloud's router lets only ten core
apps register root URLs (`nextcloud/server`
`lib/private/AppFramework/Routing/RouteParser.php:19–30`, enforced at
`:212–215`; the `root` argument of `#[Route]` is subject to the same list,
`lib/public/AppFramework/Http/Attribute/Route.php:49`). Every third-party client
works around this with a discovery dance over candidate bases.

**Proposal**, in three parts across three repositories:

1. **`nextcloud/server`:** a sanctioned, admin-opted-in way for an app to claim
   root prefixes — either `social` on the allowlist for `/api/v1`, `/api/v2`,
   `/api/v1.1`, `/oauth`, or a general `root_routes` declaration in
   `info.xml` that an admin enables with `occ app:root-routes social on`.
   With pretty URLs (`htaccess.RewriteBase`), Nextcloud's own `.htaccess`
   front-controller rule then delivers `/api/v1/instance` to `index.php` with
   no extra web-server config. Collision check: core uses `/ocs`, `/remote.php`,
   `/apps`; nothing at `/api` or `/oauth`.
2. **`nextcloud/social`, now:** serve `/.well-known/oauth-authorization-server`
   from the existing well-known handler (`lib/WellKnown/WebfingerHandler.php:61–70`,
   registered at `lib/AppInfo/Application.php:102`) instead of only as a
   `FrontpageRoute` (`lib/Controller/OAuthController.php:738`). Nextcloud's
   stock `.htaccess` already forwards `/.well-known/*` to `index.php`
   (`nextcloud/server` `.htaccess:157`), so one of the four rules disappears on
   every Apache install.
3. **`nextcloud/social`, now:** announce the API base in NodeInfo's free-form
   `metadata` (`OAuthController::nodeInfo()`, `:110–147`):
   `"metadata": {"nodeName": …, "mastodonApiBase": "https://cloud.example/index.php/apps/social/"}`.
   NodeInfo is already reachable at the true root, so a client that knows to
   look gets the base in one request instead of six probes.
4. **`nextcloud/documentation`:** the Apache and nginx snippets in the admin
   manual, plus AIO and snap, so "install Social" includes "clients can
   connect".

**Acceptance criteria**

- On a stock Apache install with pretty URLs and the opt-in enabled,
  `GET https://cloud.example/api/v1/instance` answers the instance document
  with no custom rules.
- `/.well-known/oauth-authorization-server` answers at the root on a stock
  install today.
- NodeInfo carries `metadata.mastodonApiBase`, and it is the base that works.
- `ClientApiAtRoot` reports success in all of the above.

### 2.6 A real `static_url` for animated custom emoji

**Title:** Custom emoji: serve a still `static_url` for animated emoji

**Problem**

`static_url` is always `url` — for local emoji (`lib/Model/CustomEmoji.php:116`,
reasoning at `:22–24`) and for remote ones (`lib/Model/ActivityPub/ACore.php:811`).
A client honouring Reduce Motion or "don't autoplay animations" has nothing
still to show and must either animate anyway or decode the GIF itself.

Separately: remote emoji URLs are handed to clients verbatim
(`ACore.php:786–815`), so every reader's client fetches the remote host
directly — unlike attachments, which are proxied.

**Proposal**

1. Local emoji: in `EmojiService::add()` (`lib/Service/EmojiService.php:151–206`),
   detect animation (GIF with > 1 frame, PNG with an `acTL` chunk, WebP with
   `ANIM`) and write the first frame as `<shortcode>.static.png` beside the
   original (Imagick when present — `ImageConversionService` already probes it;
   GD reads a GIF's or APNG's first frame; animated WebP without Imagick keeps
   `static_url = url`).
2. Store `static_filename` in `social_emoji`
   (`lib/Migration/Version1000Date20221118000002.php:1849–1865`, both branches;
   `TABLE_EMOJI` columns in `lib/Db/CoreRequestBuilder.php:605–613`), and a
   repair step that generates stills for existing rows.
3. Serve `GET /emoji/{shortcode}/static` beside `emojiOpen()`
   (`lib/Controller/InstanceApiController.php:375`), same caching.
4. `CustomEmoji::jsonSerialize()` emits the static route when there is one.
5. Later, remote emoji: cache through `social_cache_doc` like attachments, which
   fixes the leak and gives the same still for free.

**Acceptance criteria**

- An animated GIF emoji's `static_url` serves a single-frame PNG; a still
  emoji's `static_url` equals `url`.
- Existing animated emoji get stills after upgrade.
- `/api/v1/custom_emojis` and emoji on statuses agree.

### 2.7 Idempotency: claim the key before posting

**Title:** `POST /api/v1/statuses`: claim the `Idempotency-Key` before creating, and cover scheduled and held posts

**Problem**

See §1.1. The key is remembered after `createPost()`
(`lib/Controller/StatusApiController.php:264`, `:276`), so a retry that arrives
while the first request is still running posts twice; scheduled (`:143–151`) and
held (`:233–262`) posts skip it entirely.

**Proposal**

- Claim first: `DurableCache::inc('social_idempotency_claim', $key, 60)`
  (`lib/Service/DurableCache.php:96`) — atomic on memcache and via
  `insertIfAbsent()` on the table. A value above 1 means another request holds
  the key: answer **409** `{"error":"a request with this Idempotency-Key is in progress"}`
  — or wait up to 10 s for the result and return it.
- Remember the outcome for scheduled posts (the `ScheduledStatus` id) and held
  posts (the 422 body), and replay it.

**Acceptance criteria**

- Two concurrent requests with one key create one status; the second gets the
  same status or a 409.
- A retried scheduled post creates one `social_scheduled` row.
- A retried held post creates one hold.

### 2.8 `Account.avatar` is never empty

**Title:** Account entity: `avatar`/`header` must always be URLs

**Problem**

`Person::exportAsLocal()` (`lib/Model/ActivityPub/Actor/Person.php:1418–1462`)
falls back to the placeholder only when the actor has an icon without a local
copy (`:1419–1427`). An actor with no icon at all emits `getAvatar()` — `''`
by default (`:191–198`). `getHeader()` (`:214–220`) falls back to the avatar,
so a header is the avatar stretched, or `''`. Mastodon declares all four fields
URLs and serves `missing.png` / a blank header instead.

**Proposal**

- In `exportAsLocal()`: `avatar` and `avatar_static` fall back to
  `placeholderImage()` whenever empty, icon or not.
- `header`/`header_static`: a static blank image route
  (`img/header-missing.png`) when the actor has no header — never the avatar.
- `DirectoryAccount::jsonSerialize()` (`lib/Model/Client/DirectoryAccount.php:196`)
  and `PixelfedService` (`:442`, `:658`) apply the same rule.

**Acceptance criteria**

- No Account entity anywhere in the client API carries `""` for `avatar`,
  `avatar_static`, `header` or `header_static`.
- `header` equals `avatar` only if the person really uploaded the same picture.
