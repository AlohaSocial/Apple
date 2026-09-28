# 14 — Open questions and assumptions

Decisions deliberately deferred, assumptions made where the specification had
to choose, and things to check with the server before building against them.

## 1. Assumptions made without being asked

| # | Assumption | Why | Cost of being wrong |
|---|---|---|---|
| 1 | ~~Autoplay is on by default in Shorts mode, Wi-Fi-only elsewhere.~~ **Resolved:** autoplay is always on, on every network, including cellular and Low Power Mode. One off-switch, no per-network states. | Confirmed by the product owner. | — |
| 2 | Bundle id `com.nextcloud.alohasocial`, replacing the seed project's `nextcloud.AlohaSocial`. | The seed value is not a valid reverse-DNS identifier. | Must be decided before the first TestFlight build; changing it later means a new App Store record. |
| 3 | The app name is "Aloha Social" and the URL scheme is `alohasocial://`. | From the working directory and the seed project. | Rename is cheap now, expensive after launch. |
| 4 | No CLAUDE.md at the repository root; conventions live in [12-conventions-quality.md](12-conventions-quality.md). | The multi-file spec set was chosen over the variant that added one. | None — a CLAUDE.md can be added later pointing at doc 12. |
| 5 | Age rating 17+. | Unrestricted access to arbitrary federated content. | Rejection at review if set lower. |
| 6 | No iCloud sync of any app state in 1.0. | Tokens are `ThisDeviceOnly` by design; syncing drafts and settings without syncing accounts is confusing. | A post-1.0 feature. |

## 2. Deferred past 1.0

- **Cross-account merged timeline and merged notifications.** Genuinely useful,
  genuinely hard: deduplication across servers, ordering across clock skew, and
  per-post account context on every action. The data model already carries
  `accountID` on every row, so it is additive.
- **Live Activities for anything but uploads.**
- **Immersive visionOS experiences.**
- **Safari extension** for "open this in Aloha Social".
- **Nextcloud Files browser** beyond the composer's path picker.
- **Admin and moderation console** over Nextcloud Social's admin API.
- **CarPlay** for audio mode.

**Deferred, then built anyway.** Annual reports / Wrapstodon
(`/api/v1/annual_reports`), memories (`/api/v1/memories/on_this_day`), starter
packs, places, channels, the follow graph and GIF search were all listed here
as past 1.0. Every one of them is now in the app — `AnnualReportView`,
`MemoriesView`, `StarterPacksView`, `PlaceView`, `ChannelsView`,
`FollowConstellationView`, `GIFPicker`, each behind its capability flag. They
were cheap once the endpoints were modelled, and none is load-bearing, which is
what made them easy to add and would make them easy to drop. Recorded in §6.

## 3. To verify against the server before building

| # | Question | Where it matters |
|---|---|---|
| 1 | Does `POST /api/v1/statuses` on Nextcloud Social honour an `Idempotency-Key` header, or ignore it? If ignored, retry-on-timeout can double-post and the composer needs a different safety net (e.g. a pre-flight check for an identical recent status). | [07-composer.md](07-composer.md) §5 |
| 2 | Does Nextcloud Social accept `scheduled_at` on `POST /api/v1/statuses`? The scheduled-statuses read/update/delete routes exist and a cron runs them, but the creation path should be confirmed. | [07-composer.md](07-composer.md) §5 |
| 3 | Does the OAuth flow accept `urn:ietf:wg:oauth:2.0:oob` as a registered redirect URI for a *new* registration, not only in `denyUrl`? The whole tvOS sign-in depends on it. | [03-auth-and-accounts.md](03-auth-and-accounts.md) §7 |
| 4 | ~~What credentials does WebDAV browsing need?~~ **Answered:** the Social token is issued by Social's own authorisation server and is not a Nextcloud session, so WebDAV refuses it. **Nextcloud Login Flow v2** grants a real app password, and one app password unlocks both Files browsing and push. Implemented; see §7. | [07-composer.md](07-composer.md) §6 |
| 5 | Is `only_media` / `only_video` / `only_news` a **422** on a server that does not implement them, or silently ignored? The capability probe assumes 422 on Nextcloud Social and gates on `software.name` elsewhere; if stock Mastodon silently ignores them the fallback is correct either way, but the probe can be simplified if the behaviour is known. | [02-server-api.md](02-server-api.md) §4 |
| 6 | Does `Account.avatar` returning `""` still occur on current `master`? The compatibility document lists it as an open defect verified against a running instance. The defensive decode stays regardless, but a fix upstream is worth having. | [04-data-model.md](04-data-model.md) §2 |
| 7 | Will the ActivityPub attachment-shape defect (attachments served in Mastodon client shape rather than as `Document` with `mediaType`) affect anything this client reads? It is a *peer*-facing defect, so probably not — but a status re-fetched from a peer could carry the odd shape. | [04-data-model.md](04-data-model.md) §2 |

## 4. Worth proposing upstream to Nextcloud Social

Each of these would make the client materially better and none is large.

1. **An `only_short` timeline narrowing**, decided on the write like `only_video`
   and `only_news` are, using duration and aspect from the stored media meta.
   It would turn Shorts mode from a heuristic into an exact feed and would
   benefit every client, not just this one.
2. **Web Push (`/api/v1/push/*`)**. Already identified upstream as a known
   weeks-long item. It is the single largest quality gap for a mobile client:
   everything else in this specification works around its absence.
3. **The streaming API.** Second largest, and a smaller win than push for a
   phone.
4. **Fill `meta.original.{width,height,duration}` for every video attachment.**
   The Shorts classifier degrades to a deferred reclassification without it, and
   every client that lays out media needs the aspect ratio to avoid layout shift.
5. **Make the root-rewrite rules part of the standard Nextcloud installation
   guidance**, or register the routes at the root from the app. Every third-party
   client is blocked on this, and the discovery dance in
   [03-auth-and-accounts.md](03-auth-and-accounts.md) §2 exists only because of it.
6. **A non-empty `static_url` distinct from `url` for animated custom emoji**,
   so a Reduce Motion reader can be shown a still.

## 5. Things intentionally not specified

- Exact pixel values, spacing numbers and animation durations. Those are the
  implementer's, within the design system's scale.
- The app icon and marketing assets.
- The precise wording of user-facing strings, beyond the few quoted where the
  wording carries a decision (the privacy statement, the `drop`/`filter`
  footnote, the "your server manages your name" message).
- Which of the seven built-in themes is the default. System.


## 6. Implementation status

Recorded 2026-09-20, after building the app against this specification, and
kept current since. **Phases 0–9 are implemented.** 294 tests across eight
package suites plus 62 UI tests; all five platform targets build in Release
with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`; both extensions ship.

### Complete

Every phase in [13-implementation-plan.md](13-implementation-plan.md), including
the pieces that were partial in the first pass: alt-text generation, on-device
translation, video trim, scheduled-post management, Web Push, the upload Live
Activity, the collections UI, the Nextcloud attach picker, String Catalogs and
the CI gates.

### Deliberately different from the specification

| Change | Why |
|---|---|
| `ContentMode` is named **`FeedMode`** | Collides with SwiftUI's own `ContentMode`. |
| `AlohaStore` depends on `AlohaHTML` | The plain-text projection is derived at write time; deriving it elsewhere would mean two parsers that can disagree. |
| **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set on the app target only, not on `AlohaUI`/`AlohaDesign`** | It caused a shipped crash (below) and then blocked correct use of `TranslationSession`. SwiftUI already makes `View.body` main-actor, so the flag bought ergonomics the platform provides anyway. View models keep an explicit `@MainActor`. |
| Alt text is generated by **Vision**, then phrased by the language model | `FoundationModels` takes no image. Vision reads the picture and the model only sees a list of detected things — which is what makes "never identify anyone" enforceable rather than hopeful. |
| On-device translation uses **`translationPresentation`** | `TranslationSession.translate` is `@concurrent` while `ViewModifier.body` is main-actor, so a session obtained there cannot legally be handed to it. Apple's presentation is the same on-device translation and handles the language-pair download. iOS and iPadOS only; the server path covers the rest. |

### Two crashes found by running the app, and their causes

Both were the same class of defect and neither was caught by the type checker.

1. **Sign-in trapped the process.** `ASWebAuthenticationSession` delivers its
   completion on a background XPC queue, but under `MainActor` default
   isolation the closure was inferred main-actor-isolated, so Swift's runtime
   isolation check trapped. Found three more instances of the same pattern by
   audit — `StreamingConnection`'s socket callbacks and two
   `MPRemoteCommandCenter` handlers — all of which would have crashed the first
   time streaming or lock-screen audio controls were used. Pinned by
   `CallbackIsolationTests`.

   A second bug sat behind it: `INFOPLIST_KEY_CFBundleURLTypes = ""` never
   registered the `alohasocial` scheme, so the session failed its dry run and
   called back immediately — which is how the crash was reached at all.

2. **The app launched with no window.** Twice, from two different causes. A
   custom `INFOPLIST_FILE` drops the generated `NSPrincipalClass`, without
   which AppKit never finishes launching. Then localized package resources
   without `defaultLocalization` produced resource bundles the app could not
   load, with the same symptom and no crash report either time.

### What a screenshot tour found that reading the code did not

The first time the app ran with data on an iOS simulator (`-AlohaMockServer`,
driven by `AlohaSocialUITests/ScreenTourTests`, which photographs every screen
into `/tmp/shots/`) it showed a different class of defect: things that compile,
pass unit tests, and are wrong on the screen.

- **The app could not be installed on iOS at all.** All three extensions relied
  on `INFOPLIST_KEY_NSExtensionPointIdentifier`, which is not a generated key;
  without an `NSExtension` dictionary the installer refused the bundle. Each
  extension now carries an explicit `Supporting/<Target>-Info.plist`.
- **Shorts drew off-screen.** The rotated-`TabView` vertical pager mis-measured
  under the safe area; every page was shifted half a screen left. Replaced with
  a paging `ScrollView` (`scrollTargetBehavior(.paging)`), with the overlay
  padded by the real safe-area insets and the navigation bar hidden.
- **Photos showed blank tiles** for text-only statuses — Mastodon ignores
  `only_media` on the home timeline. The grid filters locally as well.
- **Text read “with a  link .”** in Video rows, Shorts and notifications: three
  places still stripped tags with a regex instead of the parser. All go through
  `StatusHTMLParser.plainText` now.
- **The composer's counter wrapped one digit per line.** Eight tool icons plus
  the counter overflowed an iPhone; the icons scroll and the counter is
  `fixedSize()`.
- **Tapping a name did nothing useful** — only the avatar opened a profile;
  and your own profile offered a Follow button. Both fixed.
- **Search had no field.** `.searchable` on a pushed iOS screen rendered
  nothing; it now uses `.navigationBarDrawer(displayMode: .always)` and focuses
  on arrival.
- Toolbar symbols had no accessibility labels; a portrait video swallowed the
  row (capped at 4:5 and 300pt); “Bob and 1 others”; the notification permission
  prompt appeared on the welcome screen, and even in mock mode.

A second tour on the Mac (`SidebarTourTests`, which clicks every sidebar row)
found two more that reading never would have:

- **Nothing in the sidebar but the modes did anything.** Notifications,
  Bookmarks, Favourites, Explore, Search, Lists, Conversations and Settings were
  value-based `NavigationLink`s in a `NavigationSplitView` sidebar, which has no
  stack of its own to push onto. The sidebar now selects a `SidebarItem` — a
  mode or a destination — and the detail column shows whichever is selected.
  On iPhone, where Explore, Lists, Bookmarks, Favourites and Conversations had no
  entry point at all, they join the source menu as a “Browse” section.
- **Shorts killed the Mac app.** SwiftUI's `VideoPlayer` aborts inside
  `_AVKit_SwiftUI` on macOS 27 while building its representable's class
  metadata. `PlayerSurface` wraps `AVPlayerView` directly on the Mac and keeps
  `VideoPlayer` elsewhere; the viewer and the trim sheet go through it too.

### A third pass, driving the app rather than photographing it

Tapping, typing and posting — rather than only looking — found a different
class again (`InteractionTourTests`, plus a mock server that now accepts posts,
records favourites and boosts, and serves search, trends, lists and
conversations):

- **Replying published a top-level post.** The composer was presented with
  `.sheet(isPresented:)` and a separate `composerReplyTo`, so the sheet's body
  could be built before the reply target landed: no "Replying to", no `@handle`
  prefilled, and `in_reply_to_id` nil on the way out. The composer is now
  presented by item (`ComposerPresentation`), which cannot come apart.
- **A post you had just made did not appear.** It went to the store, but the
  timeline only picked it up on the next refresh — and then behind the "new
  posts" pill, which is exactly where you would not look for it. The session
  publishes what it posted and matching timelines insert it at the top.
- **A just-posted status was dated in the future** — "in 0s", because the
  server's `created_at` lands a fraction of a second ahead. `PostAge` reads
  "now" for anything under a minute old or dated ahead, which also covers real
  clock skew between a server and a phone.
- **Conversations showed the home timeline.** The route rendered
  `timelines/direct` — deprecated in Mastodon 3.0, so empty on newer servers —
  instead of the chat-shaped screen docs/05 §8 describes. `ConversationsView`
  now uses `/api/v1/conversations`, one row per conversation with participants,
  last message, unread dot and mark-read on open.
- **The image in the media viewer sat against the top edge**, because a
  `GeometryReader` lays its child out top-leading and `RemoteImage` never
  claimed the space it was given.
- **Explore offered a trend period picker to servers that ignore it.** Only
  Nextcloud Social narrows trends by period; on Mastodon the control changed
  nothing. It now appears only where it works.
- **Every row was called "ellipsis" to VoiceOver on macOS** — the combined row
  inherited the overflow menu's identifier — and the spoken label named the
  author and the age but never the post. Both fixed; a boost now says who
  boosted it.

Two things this pass proved were *not* bugs, having looked: clicking a post on
the Mac works in every part of the row (the first tour clicked a dead point and
then a back button that does not exist in a split view), and polls, cards,
mentions and hashtags all render — the fixtures simply had none until now.

The mock server also grew the routes any real server has and the app depends
on — single status, context, account, account statuses, relationships,
notifications (grouped and flat) — so the tour exercises the thread, profile
and notification screens rather than a 404 banner.

### Making it beautiful

A fourth pass, this one about how the app feels rather than whether it works.

**The app had no icon.** `AppIcon.appiconset` held a `Contents.json` and no
images at all. `tools/make-icons.swift` draws the mark — two speech bubbles,
one behind the other — and writes every size the catalog asks for, plus five
alternate icon sets registered through
`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`.

**Nobody had a face.** Every row, notification and conversation showed an empty
grey circle wherever an avatar had not loaded. `MonogramView` draws initials on
a hue hashed from the handle (FNV-1a, so it survives a relaunch and a rename),
which is what Nextcloud does server-side. A profile with no banner gets the same
colour as a gradient instead of a grey slab.

**Nothing moved.** Favouriting now springs and throws a short burst of sparks in
the action's own colour, boosting turns its arrows a full circle, counts roll
over rather than cutting, and both tap back through the Taptic Engine. Sending a
post gives a success haptic; the first post ever made from the app is met with
confetti, once and never again.

Also: a zoom transition carries a photograph out of the grid and back into it;
media picks up a hairline, and a shadow tinted with its own average colour taken
from the blurhash DC term (no decode pass needed); link cards take a wash of the
same; a cold launch shimmers three skeleton rows instead of showing nothing; the
Photos grid sits on near-black so pictures carry the colour; News reads in serif
at reader spacing; Shorts has scrims top and bottom and a heart that bursts on a
double tap; empty states have a tinted symbol and somewhere to go; the accent
colour is a choice of six; and emoji reactions — which Nextcloud has and
Mastodon does not — have a picker and a pop.

The iPhone's top-left corner, which held nothing, now holds the reader's own
avatar as the account switcher. The Mac already had one in its sidebar.

### Still not built

- **A Mastodon Web Push relay.** The subscription, key generation and RFC 8291
  decryption are written and tested, but a Mastodon server pushes to a Web Push
  endpoint rather than to APNs, so a relay would have to exist for it to reach a
  device. This path stays dormant — **Nextcloud's own push proxy covers the case
  that matters** (§7), and it is the one the official client uses.
- **Translations.** English is complete and every string carries a translator
  comment, enforced in CI by `tools/check-localisation.py`. Adding a language is
  a pull request against the String Catalogs.
Built since this list was written, and left here because a list that lies about
what is built is worse than no list:

- **The accessibility audit runs in CI**, over seventeen screens, in the `ui`
  job alongside the screen tours.
- **Places, starter packs, annual reports and memories** all exist —
  `PlaceView`, `StarterPacksView`, `AnnualReportView`, `MemoriesView`. The
  annual report is Mastodon's `#Wrapstodon`, which Nextcloud Social serves over
  the API and has no web page of its own for.


## 7. Nextcloud beneath Social

Signing in to Social yields a token from Social's own authorisation server. It
is resolved through `social_client_auth` and is **not a Nextcloud session** — so
WebDAV and the OCS APIs refuse it. Two features needed those, and both are now
unlocked by one optional step.

### Connecting

**Login Flow v2** (`POST /index.php/login/v2`, then poll the endpoint it
answers with) grants a Nextcloud **app password**. The person approves it in
their own browser, so this app never sees a password. Offered in
Settings → Nextcloud, skippable, and revoked on disconnect
(`DELETE /ocs/v2.php/core/apppassword`).

A plain Mastodon answers 404 to the first call, which the UI reports as "this
isn't a Nextcloud" rather than as a failure.

### Files browsing

`PROPFIND` with `Depth: 1` against
`/remote.php/dav/files/{loginName}/`, parsed with `XMLParser`. The browser shows
folders plus only the files this server's `supported_mime_types` would accept —
offering a `.docx` the upload will refuse is a wasted tap. Thumbnails come from
`/index.php/core/preview`, so showing a 200 MB video costs a few kilobytes.

Picking a file sends its **path** to `POST /api/v1/media/from-file`; the bytes
never touch the device. Without a connection the picker degrades to the path
field, which still works because the server resolves the path.

### Push, through Nextcloud's proxy

Modelled on `nextcloud/ios` (`NCPushNotification.swift`) and its `NextcloudKit`
endpoints:

1. RSA-2048 key pair, kept in the Keychain beside the token under the same
   `ThisDeviceOnly` class.
2. `POST /ocs/v2.php/apps/notifications/api/v2/push` with the SHA-512 of the
   APNs token, the public key as PEM **SubjectPublicKeyInfo**, and the proxy's
   address. Answers a device identifier, a signature over it, and the server's
   public key.
3. `POST {proxy}/devices?format=json` with those and the APNs token. The proxy
   refuses a user agent that does not declare `Strict VoIP`.
4. Each push carries a `subject` encrypted to the device key. The notification
   service extension tries every account's key, and OAEP before PKCS#1 v1.5 —
   servers of different vintages pad differently, and a push that cannot be
   decrypted says nothing.

Proxy default: `https://push-notifications.nextcloud.com`, as the official
client uses.

**This is why Social announcing no Web Push does not settle the question.**
Social has none, but the Nextcloud underneath it does, and where the person has
connected it the poller drops to a ten-minute safety net rather than driving the
app. It is not trusted absolutely: a push can be dropped, so polling continues
underneath, exactly as it does under a streaming socket.

Two things a real deployment still needs, neither of which is code here: an APNs
key for the bundle id, and either the community proxy or a self-hosted one
(`customerpush.nextcloud.com` for Enterprise, as the official client's
commented-out default shows).

**`aps-environment` is deliberately absent from the checked-in entitlements.**
Adding it breaks every build whose profile lacks the Push Notifications
capability, and a build signed with an entitlement its profile does not grant
misbehaves at launch rather than failing cleanly. Enable the capability in Xcode
when the App ID has it; until then the app polls, which is the documented
baseline anyway. See `Supporting/README.md`.
