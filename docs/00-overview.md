# 00 — Overview

## 1. What this is

Aloha Social is a native client for the fediverse, built for Apple platforms
only, targeting the 2026 OS releases and nothing before them.

It talks the **Mastodon client API**. That makes it work against Mastodon,
GoToSocial, Akkoma, Pleroma and anything else serving that protocol. Its
**primary target is Nextcloud Social**, which serves that API plus a set of
extensions — video ladders, story carousels, Pixelfed and PeerTube route
translations, per-reader watch positions — that no other server has in one
place. Aloha Social uses them where they exist and degrades cleanly where they
do not.

The product thesis in one line: **the fediverse's four content shapes — text,
photo, long video, short video — deserve four idiomatic experiences inside one
app, not one timeline that renders all four badly.**

## 2. Positioning decision

**Nextcloud-first, Mastodon-compatible.**

- Any server advertising the Mastodon client API can be added as an account.
- Feature availability is decided by runtime capability detection
  (`/api/v2/instance`, `/api/v1/instance`, probe results), never by hardcoding
  a server list. See [02-server-api.md](02-server-api.md) §4.
- Nextcloud-specific extensions are allowed and encouraged, but every one of
  them must be behind a capability flag, and the app must be fully usable with
  every flag off.
- Onboarding names Nextcloud Social first and explains what it is. Other
  servers are equally reachable, one field away.

## 3. Platforms

All six, all at the 27 line. No backwards compatibility with 26 or earlier.

| Platform | Minimum | Role |
|---|---|---|
| iOS | 27.0 | Primary. Full feature set. |
| iPadOS | 27.0 | Full feature set, multi-column, pointer, keyboard, multi-window. |
| macOS | 27.0 | Full feature set, native SwiftUI (**not** Catalyst), menu bar, multi-window. |
| visionOS | 27.0 | Reading, browsing, composing. Media in a volumetric context. |
| watchOS | 27.0 | Companion: home timeline, notifications, quick actions, short replies. |
| tvOS | 27.0 | Video-focused: Video mode and Shorts mode only. No composer. |

Toolchain: **Xcode 27**, **Swift 6.4**, Swift 6 language mode, strict
concurrency complete, default actor isolation `MainActor`.

## 4. The four content shapes

These are the product's organising idea. Each is a **mode** — a distinct
top-level destination with its own navigation, its own idiomatic layout, and
its own gestures. They are not filters bolted onto one list.

| Mode | Inspired by | Server support |
|---|---|---|
| **Home** (text) | Mastodon | Universal |
| **Photos** | Pixelfed | `only_media=true` on Nextcloud Social; client-side filter elsewhere |
| **Video** | PeerTube | `only_video=true` on Nextcloud Social; client-side filter elsewhere |
| **Shorts** | Loops | Client-side classification everywhere (see [06-media-modes.md](06-media-modes.md) §4) |
| **News** | — | `only_news=true` on Nextcloud Social only; hidden elsewhere |
| **Audio** | — | Client-side classification everywhere |

Full treatment in [06-media-modes.md](06-media-modes.md).

## 5. In scope for 1.0

- Unlimited accounts across mixed servers, fast switching, per-account settings.
- All Mastodon timelines: home, local, federated, list, hashtag, account,
  favourites, bookmarks, conversations/DMs.
- Full thread view with ancestors and descendants, edit history, quote posts
  where the server supports them, emoji reactions where the server supports them.
- Profiles: view, follow/unfollow, notify bell, hide-boosts, block, mute,
  report, lists membership, featured tags, endorsements, account notes.
- Notifications: v2 grouped where available, v1 otherwise, policy and requests
  inbox, markers, unread counts.
- Search and Explore: accounts, hashtags, statuses, trends (tags/statuses/links),
  suggestions, directory.
- Composer: text with autocomplete, content warnings, visibility, language,
  replies, threads, polls, media with alt text, video and short-video capture
  and upload, drafts, scheduled posts.
- Four media modes with idiomatic UI, plus a shared full-screen media viewer.
- Stories where the server serves them.
- Filters (v2), domain blocks, blocked/muted account management.
- Opt-in on-device AI: rewrite, alt text generation, summarise, translate.
- Widgets, App Intents/Shortcuts, share extension, deep links, Handoff,
  Spotlight, Live Activities for uploads.
- Full Dynamic Type, VoiceOver, Reduce Motion, Increase Contrast support.
- String Catalogs, English complete, structurally ready for translation.

## 6. Explicit non-goals for 1.0

- **No account creation.** Nextcloud Social's client API cannot create an
  account (`registrations: false` always) and Mastodon sign-up flows differ per
  server. Onboarding links out to the server's own sign-up page.
- **No instance administration console.** Nextcloud Social serves a full admin
  API; its *moderation* half — the reports queue, silencing and suspending an
  account, and what may trend — is in scope and described in
  [11-safety-privacy-appstore.md](11-safety-privacy-appstore.md) §7. Instance
  *configuration* — storage, retention, relays, blocklist subscriptions, setup
  checks — is not: it belongs in the Nextcloud administration page, which is
  where an administrator already is when they are doing it.
- **No Nextcloud Files browser**, beyond the single "attach a file already on
  my Nextcloud" picker described in [07-composer.md](07-composer.md) §6.
- **No PeerTube upload.** Nextcloud Social's PeerTube routes are read-only.
  Video is posted through the Mastodon media + status routes instead.
- **No custom server-side feed algorithm.** Ordering is the server's.
- **No cross-account merged timeline** in 1.0. Deferred, noted in
  [14-open-questions.md](14-open-questions.md).
- **No cloud sync of app state.** Settings and drafts are device-local in 1.0;
  iCloud sync is a post-1.0 consideration.

## 7. Vocabulary

Used consistently across every document and expected in the code.

| Term | Meaning |
|---|---|
| **Instance** | A server, identified by host. |
| **Account** | One authenticated identity on one instance. The app holds many. |
| **API base** | The URL prefix Mastodon routes hang off. Not always the root — see [03-auth-and-accounts.md](03-auth-and-accounts.md) §2. |
| **Capability** | A runtime-detected server feature. See [02-server-api.md](02-server-api.md) §4. |
| **Status** | A post. Mastodon's word; used in code and never in UI. |
| **Post** | What a status is called in user-facing text. |
| **Boost** | Mastodon's `reblog`. `boost` in UI, `reblog` in wire types. |
| **Mode** | A top-level content destination: Home, Photos, Video, Shorts, News, Audio. `FeedMode` in code — `ContentMode` collides with SwiftUI's. |
| **Short** | A video classified as short-form vertical. See [06-media-modes.md](06-media-modes.md) §4. |

## 8. Success criteria for 1.0

1. A person adds a Nextcloud Social account and reads their home timeline in
   under 30 seconds from app launch, including on an instance that has **not**
   applied the root-rewrite rules.
2. The same build, unmodified, signs into `mastodon.social` and works.
3. Cold launch to first painted timeline row, from cache, under 400 ms on an
   iPhone 15-class device.
4. Every screen usable at Accessibility XXXL text size with VoiceOver.
5. Shorts mode scrolls at 120 Hz with no dropped frames on a 5-item preload.
6. Zero third-party runtime dependencies.
