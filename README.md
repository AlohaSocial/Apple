# Aloha Social

A fediverse client for Apple platforms — iPhone, iPad, Mac, Apple Vision Pro,
Apple Watch and Apple TV. Built for iOS 27 / iPadOS 27 / macOS 27 / visionOS 27 /
watchOS 27 / tvOS 27 and nothing older.

Aloha Social speaks the Mastodon client API, so it works with Mastodon,
GoToSocial, Akkoma and anything else that serves that protocol. Its primary
target is [Nextcloud Social](https://github.com/nextcloud/social), and it goes
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
