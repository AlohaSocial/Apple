# 13 — Implementation plan

> **Status, 2026-09-20.** Phases 0–9 are implemented. What is built, what is
> partial and what was deliberately left is recorded in
> [14-open-questions.md](14-open-questions.md) §6.

Phases are ordered so that each one ends with something demonstrable, and so
that the riskiest unknowns are resolved first. Each phase lists its work
packages and the acceptance criteria that decide whether it is done.

A phase is a reasonable unit of work to hand to an implementing agent in one
go. Work packages within a phase are mostly parallelisable.

---

## Phase 0 — Foundation

**Goal:** the project builds for all six platforms with the right settings and
an empty but correct architecture.

**Work packages**

- P0.1 Rewrite the seed Xcode project: bundle id `com.nextcloud.alohasocial`,
  Swift 6 language mode, strict concurrency complete, `MainActor` default
  isolation, deployment targets at 27.0, app group, Keychain access group.
  Delete `Item.swift` and the template `ContentView`. Replace the
  `fatalError` in the model container setup with a rebuild-on-failure path.
- P0.2 Create the six targets and the eight local Swift packages with the
  dependency graph from [01-architecture.md](01-architecture.md) §3.
- P0.3 `AlohaDesign`: colour roles (four appearances each), type scale, spacing,
  radii, SF Symbol constants, the theme model and its seven built-in themes.
- P0.4 `PrivacyInfo.xcprivacy` for the app and every extension; usage
  description strings; entitlements.
- P0.5 CI: the six jobs from [12-conventions-quality.md](12-conventions-quality.md) §6,
  with `build` and `lint` live and the rest scaffolded.
- P0.6 `MIT` headers, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`,
  `ACKNOWLEDGEMENTS.md`.

**Acceptance**

- `xcodebuild` succeeds for iOS, iPadOS, macOS, visionOS, watchOS and tvOS in
  Release with warnings as errors.
- CI is green on a clean clone with only a signing team configured.
- The design-system contrast test passes for all colour roles.

---

## Phase 1 — Talking to a server

**Goal:** sign in to a Nextcloud Social instance **with and without** the root
rewrite, and to mastodon.social, from the same build.

**Work packages**

- P1.1 `AlohaModels`: every wire type, the lossy decoding rules, the id and date
  decoders, the unknown-enum handling.
- P1.2 `AlohaNetwork`: `APIClient` actor, `Endpoint`, `Paginated`, `Link` header
  parsing, `APIError`, `RateLimiter`.
- P1.3 `ServerProbe`: API base discovery (all six candidates, concurrent, first
  wins), nodeinfo cross-check, re-probe trigger.
- P1.4 OAuth: app registration, PKCE, `ASWebAuthenticationSession`, token
  exchange, revocation, `.well-known/oauth-authorization-server` discovery.
- P1.5 Keychain storage with the `ThisDeviceOnly` accessibility class and the
  shared access group.
- P1.6 `ServerCapabilities` detection, persistence, and the 24-hour refresh.
- P1.7 The `MockAPIServer` and its six configurations, plus the fixture corpus
  captured from a real Nextcloud Social instance and from mastodon.social.
- P1.8 The sign-in screen with its three states and the failure UI including
  the copyable web-server snippet.

**Acceptance**

- Sign-in succeeds against `MockAPIServer` in **all six** configurations.
- Sign-in succeeds against a real Nextcloud Social instance without the rewrite
  rules applied — verified manually and recorded in the PR.
- Sign-in succeeds against mastodon.social.
- Decoding tests pass against the real-capture corpus.
- No token, code or verifier appears in any log at any level.

---

## Phase 2 — Reading

**Goal:** a usable read-only client.

**Work packages**

- P2.1 `AlohaHTML`: the parser, the link classification, custom emoji
  resolution, the content-hash cache, off-main-actor parsing.
- P2.2 `AlohaStore`: the SwiftData schema, the model container in the app group,
  repositories, the migration plan including the destructive path.
- P2.3 Timeline data source: paging, gap markers, gap closing, position
  stability, cache-first paint, the "N new posts" pill.
- P2.4 `AlohaMedia`: `ImageLoader` with the two-tier cache and downsampling,
  the blurhash decoder.
- P2.5 The status row and all its states: boost context, reply context, CW,
  sensitive media per policy, poll rendering, card rendering, action row,
  context menu, swipe actions.
- P2.6 Thread view with ancestors, descendants, indentation cap, edit history.
- P2.7 Profile view with all tabs and the relationship display.
- P2.8 The app shell: `TabView` on iPhone, `NavigationSplitView` elsewhere,
  typed `Route`, `RouteResolver`, state restoration.
- P2.9 Multi-account: the account list, switching, per-account caches.
- P2.10 Empty, error and offline states for every list.

**Acceptance**

- Home, local and federated timelines read, page and refresh correctly against
  all mock configurations.
- A gap is inserted, rendered and closed correctly — verified by test.
- Scroll position never moves when new content arrives.
- Frame time p99 under 8 ms with 500 cached rows.
- Cold launch to first painted row under 400 ms with a warm cache.
- Every screen passes the accessibility audit.

---

## Phase 3 — Writing

**Goal:** post, reply, and interact.

**Work packages**

- P3.1 The composer: text entry with live highlighting, autocomplete for
  `@`/`#`/`:`, character counting against the server's real limits, visibility,
  language, CW.
- P3.2 Media attachment: pickers, camera, pre-flight against the two size
  ceilings and the MIME list, transcoding, background upload session, Live
  Activity, alt text editing.
- P3.3 Polls, threads (with the mid-thread failure path), drafts with autosave,
  scheduled posts.
- P3.4 `Idempotency-Key` handling and the offline send queue.
- P3.5 Actions: favourite, boost, bookmark, pin, mute conversation, delete,
  edit (via `/source`), delete-and-redraft — all optimistic with reconciliation.
- P3.6 Relationship actions: follow, unfollow, bell, hide boosts, block, mute,
  domain block, note, add to list.
- P3.7 Attach from Nextcloud Files (`/api/v1/media/from-file`).

**Acceptance**

- A post with 4 images and alt text, a poll, a CW and a non-default visibility
  posts correctly to both server kinds.
- A thread of 5 posts chains correctly; a simulated failure at post 3 leaves
  exactly 2 posted and resumes at 3 without duplicating.
- A retried post with the same idempotency key does not double-post.
- An upload survives the app being backgrounded.
- Offline posting queues and drains.

---

## Phase 4 — Notifications and sync

**Goal:** the app tells you when something happened.

**Work packages**

- P4.1 `SyncEngine` and `PollScheduler` with the interval table, backoff, the
  per-host token bucket, and Low Power Mode handling.
- P4.2 Notifications screen: v2 grouped with v1 fallback, filter chips, unread
  counts, markers.
- P4.3 Notification policy screen and the requests inbox, including the
  `drop`-behaves-as-`filter` footnote.
- P4.4 `BGAppRefreshTask` and `BGProcessingTask` registration and handlers.
- P4.5 Local notifications: categories, attachments, grouping, dedup, quiet
  hours, actions including inline reply.
- P4.6 The streaming upgrade path, tested against a mock that advertises it.
- P4.7 The Web Push upgrade path including the notification service extension,
  tested against a mock that advertises a VAPID key.

**Acceptance**

- Against a Nextcloud Social mock (no streaming, no push), a new mention appears
  as a local notification within one poll interval, exactly once.
- Against a Mastodon mock advertising streaming, the socket is used and the poll
  interval drops to the safety-net value.
- Against a mock advertising a VAPID key, a push subscription is created and
  local-notification raising is suppressed.
- Markers never move backwards across two simulated devices.
- Background refresh completes within 25 s and updates badge and widgets.

---

## Phase 5 — The modes

**Goal:** the product's differentiator.

**Work packages**

- P5.1 The mode framework: per-mode timeline keys, source selection, the
  capability-gated server filters, the client-side fallback with over-fetching.
- P5.2 `ContentClassifier` with its fixture corpus and the deferred
  reclassification path.
- P5.3 Photos mode: grid and feed layouts, collections/albums, the Pixelfed
  Explore surface.
- P5.4 Video mode: cards, Continue Watching, the player with the three-step
  source ladder and mandatory fallback, watch-position reporting, comments,
  PiP/AirPlay/background audio.
- P5.5 Shorts mode: the vertical pager, the `AVPlayer` pool, preloading, the
  gesture set with its non-gesture equivalents, the action rail, autoplay and
  battery policy.
- P5.6 The shared media viewer with zoom, dismiss, paging, alt text, save,
  share, and keyboard control.
- P5.7 Audio mode with the docked mini-player and Now Playing integration.
- P5.8 News mode (Nextcloud only).
- P5.9 Stories: the carousel, the player, seen reporting, posting, expiry.

**Acceptance**

- Each mode sources correctly on a server with the filters and on one without,
  with no duplicated or skipped rows across pages.
- A video with `hls_url` plays the ladder; a 404 on the master playlist falls
  back to `url` without the person noticing.
- A federated PeerTube video plays through `/media/playlist/{nid}` and never
  contacts the origin host — verified by a network assertion in test.
- Watch positions round-trip and Continue Watching excludes the under-10 s and
  over-95 % cases.
- Shorts sustains 120 Hz with a 3-item preload and at most 3 live players.
- Every gesture-only action in Shorts has a menu equivalent (Switch Control).

---

## Phase 6 — Search, discovery and organisation

**Work packages**

- P6.1 Search with the three result sections and URL/handle resolution.
- P6.2 Explore: trends (with the single-bucket history caveat honoured),
  suggestions, directory, other servers' directories.
- P6.3 Lists: CRUD, membership, per-list timelines including the media modes.
- P6.4 Followed hashtags, hashtag timelines, local tag groups.
- P6.5 Bookmarks, favourites, conversations/DMs.
- P6.6 v2 filters: management UI and client-side application.

**Acceptance**

- A pasted remote post URL opens in-app with working action buttons.
- A filter created in-app hides matching cached content immediately and stops
  hiding when it expires, without a refetch.
- Trends render without drawing a sparkline from a single data point.

---

## Phase 7 — Platform surfaces

**Work packages**

- P7.1 iPad: keyboard shortcuts, pointer, multi-scene, drag and drop.
- P7.2 macOS: menu bar, multi-window, toolbar search, Services, Dock menu,
  optional menu bar extra, sandbox and notarisation.
- P7.3 visionOS: window model, hover effects, separate media windows.
- P7.4 watchOS app and complications, with `WatchConnectivity` credential
  transfer.
- P7.5 tvOS app with the out-of-band sign-in, shelves, player and Shorts.
- P7.6 Share extension.
- P7.7 App Intents, Shortcuts phrases, Control Center controls.
- P7.8 Widgets for every family and platform.
- P7.9 Handoff, Spotlight indexing, Live Activities.

**Acceptance**

- Every platform builds, launches, and performs its stated role.
- A share from Safari on iOS posts successfully including while offline.
- A Shortcut posts a status with media.
- Handoff moves a half-written draft from iPhone to Mac.
- A Spotlight search finds a bookmarked post and opens it.

---

## Phase 8 — Intelligence

**Work packages**

- P8.1 `AlohaIntelligence` protocols, availability handling, the settings section.
- P8.2 Rewrite and proofread with the diff sheet and the mention/hashtag/URL
  placeholder protection.
- P8.3 Alt text generation with the review requirement and the person-description
  guardrails.
- P8.4 Summarise for threads and long statuses.
- P8.5 Translation: server path first, on-device fallback, attribution.

**Acceptance**

- Every feature is absent from the UI with its toggle off.
- A rewrite never loses a mention, hashtag or URL — asserted by test over a
  corpus.
- Generated alt text is never posted without the person having been told it is
  there and unreviewed.
- The privacy statement in [10-ai-features.md](10-ai-features.md) §8 is true of
  the shipped code.

---

## Phase 9 — Ship

**Work packages**

- P9.1 Onboarding: the EULA, the "what is the fediverse" explainer, the
  first-account flow, mode selection.
- P9.2 Settings, complete, on every platform.
- P9.3 Safety: report flow with instance rules, block/mute/domain-block
  management, the account-removal path.
- P9.4 Full localisation pass: every string in a catalog, pseudolocalisation
  screenshots clean, RTL verified.
- P9.5 Full accessibility pass on every screen on every platform.
- P9.6 App Store assets: screenshots for six platforms, description, keywords,
  age rating, export compliance, nutrition label.
- P9.7 Performance pass against every budget in
  [12-conventions-quality.md](12-conventions-quality.md) §8.
- P9.8 Repository readiness: README, CONTRIBUTING, clean-clone build verified on
  a second machine.

**Acceptance**

- Every budget met.
- Every accessibility check passes on every platform.
- App Review's four UGC requirements each demonstrably satisfied, with the
  screen they live on named in the review notes.
- A clean clone builds and runs with only a signing team configured.

---

## Ordering notes

- **Phase 1 is the riskiest and must not be compressed.** The no-rewrite
  discovery path is the difference between the app working for self-hosters and
  not, and it cannot be retrofitted.
- Phases 5 and 7 are large and parallelisable; each work package within them is
  independently testable.
- Phase 8 can slip past 1.0 without harming the product. Nothing else can.
- Phase 4's Web Push path is written and dormant. Resist the temptation to skip
  it — it is what makes the app good on Mastodon today and correct on Nextcloud
  Social tomorrow.
