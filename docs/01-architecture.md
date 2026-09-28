# 01 — Architecture

## 1. Dependency policy

**Zero third-party runtime dependencies.** Apple frameworks only.

| Need | Framework |
|---|---|
| HTTP | `URLSession` (+ `URLSessionWebSocketTask` for the streaming upgrade path) |
| Persistence | `SwiftData` |
| Image decode/display | `ImageIO`, `CoreGraphics`, custom cache (see §6) |
| Video | `AVFoundation`, `AVKit` |
| Audio | `AVFoundation`, `MediaPlayer` (Now Playing) |
| HTML parsing | Custom parser in `AlohaHTML` (see §5) — no `NSAttributedString(html:)` |
| Keychain | `Security` |
| On-device LLM | `FoundationModels` |
| Translation | `Translation` |
| Background work | `BackgroundTasks` |
| Notifications | `UserNotifications` |
| Intents | `AppIntents` |
| Widgets | `WidgetKit` |
| Live Activities | `ActivityKit` |
| Spotlight | `CoreSpotlight` |
| Auth web flow | `AuthenticationServices` (`ASWebAuthenticationSession`) |

`swift-testing` (bundled with the toolchain) is the test framework. It is not a
third-party dependency.

Adding any SPM dependency requires a written justification in the PR and an
MIT-compatible licence. The default answer is no.

## 2. Targets

Xcode project `AlohaSocial.xcodeproj`, one workspace, local Swift packages.

| Target | Type | Platforms |
|---|---|---|
| `AlohaSocial` | App | iOS, iPadOS, macOS, visionOS |
| `AlohaSocialWatch` | App | watchOS |
| `AlohaSocialTV` | App | tvOS |
| `AlohaShareExtension` | Share extension | iOS, iPadOS, macOS |
| `AlohaWidgets` | Widget extension | iOS, iPadOS, macOS |
| `AlohaIntents` | App Intents extension | iOS, iPadOS, macOS |

The four Apple-silicon-class platforms share **one** app target with
`#if os(...)` at the composition-root and view level only — never inside
business logic, which lives in packages that compile identically everywhere.

### Required project settings

The seed project must be changed to:

```
SWIFT_VERSION = 6.0                       // was 5.0
SWIFT_STRICT_CONCURRENCY = complete
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
SWIFT_APPROACHABLE_CONCURRENCY = YES
SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx xros xrsimulator
IPHONEOS_DEPLOYMENT_TARGET = 27.0
MACOSX_DEPLOYMENT_TARGET = 27.0
XROS_DEPLOYMENT_TARGET = 27.0
WATCHOS_DEPLOYMENT_TARGET = 27.0          // watch target
TVOS_DEPLOYMENT_TARGET = 27.0             // tv target
PRODUCT_BUNDLE_IDENTIFIER = com.nextcloud.alohasocial
ENABLE_USER_SCRIPT_SANDBOXING = YES
```

App group: `group.com.nextcloud.alohasocial` — shared by app, share extension,
widgets and intents extension for the SwiftData store and the Keychain access
group. Keychain access group: `$(AppIdentifierPrefix)com.nextcloud.alohasocial`.

## 3. Package layout

Local packages under `Packages/`. Each is a standalone SPM package with its own
tests. The dependency graph is a DAG and is enforced by review.

```
AlohaModels        ── no dependencies
AlohaHTML          ── AlohaModels
AlohaNetwork       ── AlohaModels
AlohaStore         ── AlohaModels, AlohaNetwork
AlohaMedia         ── AlohaModels, AlohaNetwork
AlohaIntelligence  ── AlohaModels, AlohaHTML
AlohaDesign        ── no dependencies
AlohaUI            ── all of the above
```

### `AlohaModels`

Wire types and domain types. Pure value types, `Sendable`, `Codable`, no
framework imports beyond `Foundation`.

- Mastodon entities: `Status`, `Account`, `MediaAttachment`, `Poll`,
  `Notification`, `GroupedNotificationsResults`, `Relationship`, `Context`,
  `Instance`, `InstanceV2`, `Tag`, `FilterV2`, `Conversation`, `Marker`,
  `Application`, `Token`, `Report`, `List`, `Card`, `Announcement`,
  `ScheduledStatus`, `Preferences`, `NotificationPolicy`, `NotificationRequest`,
  `CustomEmoji`, `FeaturedTag`, `Suggestion`.
- Nextcloud extensions: `Story`, `StoryCarouselEntry`, `WatchPosition`,
  `ContinueWatchingItem`, `PeerTubeVideo`, `PeerTubeChannel`, `PeerTubeConfig`.
- Enumerations: `Visibility`, `NotificationKind`, `AttachmentKind`,
  `SensitiveMediaPolicy`, `TimelineSource`, `FeedMode` (named so rather than
  `ContentMode`, which collides with SwiftUI's).
- `ServerCapabilities` (see [02-server-api.md](02-server-api.md) §4).

Decoding rules are in [04-data-model.md](04-data-model.md) §2 and are
non-negotiable: every field Mastodon documents as optional is decoded
defensively, and a single malformed entity in a page must never fail the page.

### `AlohaHTML`

Mastodon status content is a restricted HTML subset. `NSAttributedString`'s
HTML importer is WebKit-backed, main-thread-bound and far too slow for a
scrolling list, so it is forbidden.

`AlohaHTML` is a hand-written, allocation-light parser producing a
`RichText` value:

- Supported elements: `<p>`, `<br>`, `<a>`, `<span>`, `<strong>`/`<b>`,
  `<em>`/`<i>`, `<del>`, `<code>`, `<pre>`, `<blockquote>`, `<ul>`/`<ol>`/`<li>`.
- Link classification from `class` attributes: `mention` (with `u-url mention`),
  `hashtag`, plain. Mentions and hashtags are resolved against the status's
  `mentions` and `tags` arrays so taps route in-app rather than to Safari.
- Everything else is stripped to its text content. Entities are decoded.
- Custom emoji shortcodes (`:name:`) are located and resolved against
  `status.emojis` / `account.emojis` into inline image runs.
- Output is `AttributedString` with custom attribute keys for mention target,
  hashtag name, and emoji URL, plus a plain-text projection used for search,
  AI features, and VoiceOver.
- **Parsing is off the main actor** and results are cached by content hash.

### `AlohaNetwork`

- `APIClient` — an actor. One per account. Owns a `URLSession` configured with
  `waitsForConnectivity`, HTTP/3 allowed, and per-account `Authorization` header
  injection.
- `Endpoint` — a value describing method, path relative to the account's API
  base, query items, body, and required OAuth scope. Endpoints are declared as
  static factory methods grouped by area (`Endpoint.timelines`, `.accounts`,
  `.statuses`, …). No string concatenation at call sites.
- `Paginated<T>` — decoded payload plus `next`/`prev` cursors parsed from the
  `Link` header. See [02-server-api.md](02-server-api.md) §5.
- `APIError` — typed. See [02-server-api.md](02-server-api.md) §6.
- `RateLimiter` — reads `X-RateLimit-*` where present; otherwise a per-host
  token bucket to keep polling from hammering small instances.
- `ServerProbe` — the API-base discovery and capability detection routine.

### `AlohaStore`

SwiftData model container, repositories, and the sync engine.

- `ModelContainer` in the app group, one store, account-scoped rows.
- Repositories (`TimelineStore`, `AccountStore`, …) are the only things that
  touch `ModelContext`. Views never do.
- Depends on `AlohaHTML` because the plain-text projection stored on
  `StatusRecord` (for search and for the AI features' input) is derived at
  write time. Deriving it anywhere else would mean two parsers that can
  disagree.
- `SyncEngine` — the polling/refresh coordinator described in
  [08-notifications-sync.md](08-notifications-sync.md).
- Writes happen on a background `ModelActor`; reads for UI go through
  `@Query` or through main-actor fetches of small pages.

### `AlohaMedia`

- `ImageLoader` — an actor. Two-tier cache: `NSCache` in memory keyed by
  URL+target size, and a disk cache in the app group with an LRU eviction
  policy and a hard ceiling (default 512 MB, configurable). Downsamples with
  `CGImageSourceCreateThumbnailAtIndex` at decode time; full-size bitmaps are
  never held for list cells.
- `BlurHashDecoder` — pure Swift, renders the `blurhash` field as the placeholder.
- `VideoPlayerCoordinator` — a pool of `AVPlayer` instances (max 3 live),
  handles HLS vs progressive selection, preloading, PiP, AirPlay, and the
  `watched` position reporting.
- `AudioPlayerCoordinator` — single `AVAudioSession`-backed player with
  `MPNowPlayingInfoCenter` and remote command support, background playback.
- `MediaUploader` — chunk-free multipart upload with progress, backed by a
  `URLSession` background configuration so uploads survive app suspension, and
  driving a Live Activity.

### `AlohaIntelligence`

Everything touching `FoundationModels` and `Translation`, behind protocols so
the rest of the app compiles and tests without them. Availability is checked at
runtime (`SystemLanguageModel.default.availability`) and every feature has a
disabled state. See [10-ai-features.md](10-ai-features.md).

### `AlohaDesign`

Tokens and primitives, no business logic: colour roles, typography scale,
spacing scale, corner radii, materials, iconography (SF Symbols names as typed
constants), haptics, animation curves, and the theme engine. Light and dark are
both first-class. See [05-core-ui.md](05-core-ui.md) §2.

### `AlohaUI`

All SwiftUI views and view models. Organised by feature folder, mirroring
[05-core-ui.md](05-core-ui.md) and [06-media-modes.md](06-media-modes.md).

## 4. State and concurrency

- Swift 6 language mode, strict concurrency complete, no `@unchecked Sendable`
  without a comment explaining the invariant.
- Default actor isolation is `MainActor`: views, view models and coordinators
  are main-actor by default and say so implicitly.
- Anything doing I/O is an `actor` or a `ModelActor`: `APIClient`, `ImageLoader`,
  `SyncEngine`, repositories' write paths, `AlohaHTML`'s parser.
- Observation via `@Observable`. No Combine, no `ObservableObject`.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` applies to the **app target and
  the UI packages only**. The model, parser, network, store and media packages
  compile without it: their types cross actor boundaries by design, and a
  main-actor-isolated wire model could not be decoded off the main thread.
- One `AppEnvironment` (`@Observable`) is the composition root. It owns the
  account list, the active account, the `ServerCapabilities` for each, the
  theme, and the settings store. Injected through the SwiftUI environment.
- Per-account services are created and torn down with the account. A signed-out
  account leaves no live object and no cached bytes.

## 5. Navigation

- `NavigationStack` with a typed, `Codable` `Route` enum per tab, so state
  restoration and Handoff are the same mechanism.
- iPhone: `TabView` with the modes as tabs.
- iPad / Mac / visionOS: `NavigationSplitView`, sidebar listing modes plus
  lists, hashtags and saved searches; content column; detail column.
- Mac additionally supports multiple windows, each with its own
  `NavigationStack`, opened via `openWindow` with a `Route` value.
- Deep links and universal links resolve to a `Route` and are handled in exactly
  one place (`RouteResolver`), so every entry point behaves identically.

## 6. Error and offline philosophy

- Every screen renders from cache first, then refreshes. There is no spinner
  where cached content exists.
- A failed refresh over cached content is a non-modal inline banner, never an
  alert, never a cleared list.
- A failed action (post, boost, follow) is optimistic in the UI and rolled back
  with an explanation on failure.
- Offline is a first-class state, not an error: cached timelines, cached media,
  drafts queued for send. The queue drains on connectivity return.
