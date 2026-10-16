# Aloha Social

A fediverse client for Apple platforms — iPhone, iPad, Mac, Apple Vision Pro,
Apple Watch and Apple TV. Built for iOS 27 / iPadOS 27 / macOS 27 / visionOS 27 /
watchOS 27 / tvOS 27 and nothing older.

Aloha Social speaks the Mastodon client API, so it works with Mastodon,
GoToSocial, Akkoma and anything else that serves that protocol. Its primary
target is [Nextcloud Social](https://github.com/AlohaSocial/social), and it goes
further there: photo, video, short-video, news and story experiences built on
the extensions that server publishes alongside the Mastodon surface.

Text posts. Photos, the way Pixelfed does them. Long video, the way PeerTube
does it. Short vertical video, the way Loops does it. Audio. One app, one
account list, six platforms.

Six platforms, but not six identical apps, and deliberately so
([docs/00 §3](docs/00-overview.md)): iPhone, iPad, Mac and Vision Pro get the
full feature set. **Apple Watch is a companion** — home timeline,
notifications, quick actions, short replies; it never authenticates on its own.
**Apple TV is video only** — Video and Shorts modes, and no composer.

**Status: implemented, pre-release.** All nine phases of
[docs/13](docs/13-implementation-plan.md) are built: ~57,000 lines of Swift in
eight local packages, 294 package tests plus 62 UI tests, and every platform
target building in Release with warnings as errors. Everything below `docs/` is
the contract the implementation satisfies, and
[docs/14 §6](docs/14-open-questions.md) records where it deliberately differs.

What it has **not** had is a real server. Every Nextcloud-specific route is
exercised against `MockAPIServer`, which was written from the same
specification — so it agrees with this client by construction. The open
questions in [docs/14 §3](docs/14-open-questions.md) are the ones a running
instance has to answer before 1.0.

## Recent additions (PR #6)

This follow-up PR (draft) adds the following features and fixes on top of the
base PR (#1):

- **Video privacy fix**: Federated videos whose `url` still points at the
  origin server are never handed to the player; the proxied playlist route is
  used instead (docs/06 §3).
- **Timeline race fix**: A confirmed like/boost can no longer be reverted by a
  stale page fetch; confirmations are timestamped and take precedence over the
  page's older copy.
- **Private-network server support**: Typed `http://192.168.x.x:8080` addresses
  keep their port and scheme through sign-in, re-probe, NodeInfo, and "open in
  browser" links. ATS blanket exception documented (docs/11 §5).
- **Notification policy screen**: Five `for_*` pickers (Accept/Filter/Drop)
  with a link to the filtered-notifications inbox; reachable from Settings
  and the Notifications screen.
- **Conversation mute**: "Mute conversation" / "Unmute conversation" in the
  post menu, in the in-app notification row context menu, and as a push
  notification action for mentions and replies.
- **"Show numbers" switch**: Hides reply/boost/favourite counts on posts,
  follower/post counts on profiles, "and N others" in grouped notifications,
  story view counts, and year-in-review follower figures.
- **"You're caught up" divider**: Home timeline and Notifications show a
  divider at the server-side marker; scrolling past it advances the marker
  (docs/08 §7).
- **Notification digests**: Per-account delivery mode "As they arrive" /
  "In a digest" (1–4 hours); quiet hours UI; DMs and mentions from followed
  accounts always break through; LocalNotifier schedules at digest times
  with `UNCalendarNotificationTrigger`.
- **Repository links corrected**: All self-references now point at
  `AlohaSocial/Apple` and `AlohaSocial/social`; OAuth website and User-Agent
  updated.
- **ATS exception on tvOS/watchOS**: Dedicated Info.plist files with the
  blanket exception so the new HTTP private-network sign-in works on all
  platforms.
- **App Group safe defaults**: Disabled by default; keychain sharing gated
  independently; personal-dev signing no longer claims a container it
  cannot have.
- **OAuth origin comparison hardened**: Case-insensitive, default-port-aware,
  discarded endpoints logged.
- **OAuth/http scheme persistence**: Re-probe, NodeInfo, Nextcloud connect,
  and "open in browser" all read the scheme/port from the stored API base.

## Building

Xcode 27 and nothing older; the toolchain is not optional, because every
platform is pinned to the 27 line. Open `AlohaSocial.xcodeproj`, set a signing
team, and run. There are no dependencies to fetch — the eight packages are
`path:` siblings and there is no third-party code.

`-AlohaMockServer` as a launch argument boots straight into a populated
timeline against the in-process mock, skipping OAuth. It is how the screen
tours run, and the fastest way to see the app without an account.

## Reading order

| Document | What it settles |
|---|---|
| [docs/00-overview.md](docs/00-overview.md) | Product scope, platforms, non-goals, vocabulary |
| [docs/01-architecture.md](docs/01-architecture.md) | Targets, Swift package layout, concurrency, dependency rules |
| [docs/02-server-api.md](docs/02-server-api.md) | The server contract: endpoints, capability detection, pagination, errors |
| [docs/03-auth-and-accounts.md](docs/03-auth-and-accounts.md) | API base discovery, OAuth + PKCE, Keychain, multi-account |
| [docs/04-data-model.md](docs/04-data-model.md) | SwiftData schema, DTO mapping, cache policy, migrations |
| [docs/05-core-ui.md](docs/05-core-ui.md) | Timelines, threads, profiles, notifications, search, settings |
| [docs/06-media-modes.md](docs/06-media-modes.md) | Photos, Video, Shorts, Audio, News, Stories, the media viewer |
| [docs/07-composer.md](docs/07-composer.md) | Posting: text, media, alt text, polls, threads, drafts, scheduling |
| [docs/08-notifications-sync.md](docs/08-notifications-sync.md) | Polling engine, background refresh, streaming/WebPush upgrade path |
| [docs/09-platforms-integrations.md](docs/09-platforms-integrations.md) | Per-platform UI, widgets, App Intents, share extension, Handoff |
| [docs/10-ai-features.md](docs/10-ai-features.md) | On-device Foundation Models and Translation framework features |
| [docs/11-safety-privacy-appstore.md](docs/11-safety-privacy-appstore.md) | Moderation UI, privacy manifest, App Store review requirements |
| [docs/12-conventions-quality.md](docs/12-conventions-quality.md) | Coding standards, testing, accessibility, localisation, CI |
| [docs/13-implementation-plan.md](docs/13-implementation-plan.md) | Phased work packages with acceptance criteria |
| [docs/14-open-questions.md](docs/14-open-questions.md) | Decisions deliberately left open, and assumptions made |

## Licence

MIT. See [LICENSE](LICENSE).

## Acknowledgements

Architectural debt is owed to [Ice Cubes](https://github.com/Dimillian/IceCubesApp)
by Thomas Ricouard — a modular, readable SwiftUI Mastodon client that showed
what the shape of this kind of app should be. Aloha Social shares none of its
code (Ice Cubes is AGPL v3, this is MIT) and none of its visual identity.
