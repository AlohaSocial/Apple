# 09 — Platforms and system integrations

## 1. iOS / iPadOS

**iPhone** is the reference platform. `TabView` shell, sheet-based composer,
full-screen media viewer, all six modes.

**iPad** adds:
- `NavigationSplitView` with a persistent sidebar; sidebar collapsible.
- Full keyboard support: `⌘1`–`⌘6` for modes, `⌘N` compose, `⌘R` refresh,
  `⌘F` search, `J`/`K` to move between rows, `L` favourite, `B` boost,
  `R` reply, `↩` open, `esc` back. Every shortcut discoverable via the
  hold-⌘ overlay.
- Pointer interactions with hover effects on rows, buttons and media.
- Multiple scenes: a status, a profile, or the composer can be dragged out
  into its own window.
- Drag and drop: images and video into the composer; a status out as a URL;
  a profile out as a handle.
- Stage Manager and external display: the split view expands to three columns.

## 2. macOS

Native SwiftUI on AppKit. **Not Catalyst.**

- Window management: a main window per account-and-route, `⌘N` new window,
  `⌘⌥N` new compose window, full window restoration.
- A complete menu bar: File (New Post, New Window, Open Link…), Edit, View
  (mode switching, density, theme), Post (Reply, Boost, Favourite, Bookmark,
  Translate), Account (switch, add, sign out), Window, Help.
- Toolbar with a real search field, not a pushed screen.
- Sidebar with disclosure groups, drag-to-reorder for lists and hashtags.
- Menu bar extra (optional, off by default): unread count and a compact
  notifications popover.
- Services menu integration: "Post to Aloha Social" for selected text and images.
- Dock badge, Dock menu (New Post, accounts), and bounce-free notifications.
- Full pointer and keyboard parity with iPad, plus right-click context menus
  everywhere a long-press exists on iOS.
- Sandboxed, hardened runtime, notarised. Entitlements: outgoing network,
  user-selected files read-only, Photos (add-only), camera and microphone for
  capture, app group.

## 3. visionOS

- Main window as the split view; media viewer and video player open as separate
  windows so a video can be parked in space while reading continues.
- Shorts mode as a full ornamented window, not immersive — a vertical feed in an
  immersive space is uncomfortable and nobody asked for it.
- Hover effects on every interactive element, `.hoverEffect(.highlight)` on rows.
- Glass background materials as the platform provides; no custom translucency.
- Depth used sparingly: the media viewer elevates, nothing else does.
- No immersive spaces in 1.0.

## 4. watchOS

Companion, not a client. It never authenticates on its own; the phone hands it
the active account's token and API base over `WatchConnectivity`, and it stores
that in the watch Keychain (`…AfterFirstUnlockThisDeviceOnly`).

- Home timeline (text and image thumbnails only; no video).
- Notifications list with grouped notifications collapsed to their summary.
- Actions: favourite, boost, bookmark, follow-back.
- Reply composer: dictation, Scribble, emoji, and up to 8 user-defined canned
  responses edited on the phone.
- Complications (`AlohaWatchWidgets`, a WidgetKit extension embedded in the
  watch app): unread notification count (`.accessoryCircular`,
  `.accessoryCorner`, `.accessoryInline`, `.accessoryRectangular`) and the
  latest mention (`.accessoryRectangular`, showing the content warning rather
  than the post where there is one). A tap opens the mention, or the
  mentions list. Unread direct messages (`.accessoryCircular`,
  `.accessoryCorner`, `.accessoryInline`, `.accessoryRectangular`): a paper
  plane and the number of conversations with something unread. A tap opens
  the watch app, which has no messages list of its own.
- The complications draw from one snapshot in the watch's app group
  (`WatchComplicationSnapshot`), kept current three ways: the watch app
  refreshes it whenever it comes to the front; the phone pushes the paired
  account's unread count with `transferCurrentComplicationUserInfo` when it
  changes, only while a complication is on the face and within the daily
  budget, with the active account's unread conversation count
  (`AppGroup.unreadConversationsKey`) riding along, sent again when only
  that count changes; and the complication's own timeline asks the server
  directly when the snapshot is older than fifteen minutes, with the token
  the watch app keeps in the shared Keychain group.
- No modes, no media viewer, no settings beyond notification toggles.

## 5. tvOS

Video only. Video mode and Shorts mode, nothing else.

- Sign-in by out-of-band code (see [03-auth-and-accounts.md](03-auth-and-accounts.md) §7).
- Browse UI: shelves for Continue Watching, Following, Local, Global,
  Trending. Focus-driven, with a preview that starts muted after 1.2 s of focus.
- Full-screen player with the standard tvOS transport, subtitle and audio
  selection, and watch-position reporting.
- Shorts mode as a full-screen pager driven by swipe-up/down on the remote.
- Actions limited to favourite, boost and follow. No composer, no text entry
  beyond search.
- Search via the system keyboard and dictation, backed by `/api/v2/search`
  narrowed to statuses with video.
- **Top Shelf** (`AlohaTopShelf`, `social.aloha.app.tv.topshelf`): when the
  app sits in the top row, the shelf shows *Continue watching* (with each
  video's progress) and the newest videos from *Following*. The TV app writes
  what its Video tab loaded into the app group (`TopShelfSnapshot`) and asks
  the system to redraw only when that changed; the extension reads it, and
  goes to the server itself only when the snapshot is missing or older than
  half an hour, with the account the app keeps in the shared Keychain group
  (`TVAccountStore`). Posts with sensitive media or a content warning are left
  off: the shelf draws stills full size on the home screen, with no way to
  hide them. Select and Play open `alohasocial://tv/show|play/<id>?t=<s>`,
  which starts the video where it was left.

## 6. Share extension

Target: `AlohaShareExtension`, available on iOS, iPadOS and macOS.

- Accepts: plain text, URLs, images (multiple), video, and file URLs.
- Presents the real composer — the same SwiftUI view from `AlohaUI`, not a
  reduced one — with the shared content pre-attached and the account picker
  available.
- Reads accounts from the app group SwiftData store and tokens from the shared
  Keychain access group.
- Uploads through the same background `URLSession` configuration, so an upload
  started in the extension completes even after the extension is gone; the
  host app picks up the completion via
  `application(_:handleEventsForBackgroundURLSession:)`.
- A share made while offline writes a `DraftRecord` with `queuedForSend = true`
  and tells the person so.
- Memory budget is tight: the extension must not build the full model container
  with every relationship warm. It uses a dedicated lightweight fetch path.
- One target builds for both: on the Mac it is `social.aloha.app.mac.share`
  (an embedded extension's id must start with its app's), embedded in
  `AlohaSocialMac`, sandboxed with outgoing network, the app group and the
  Keychain group (`AlohaShareExtensionMac.entitlements`). Only the hosting
  controller differs; the Mac's share sheet owns its window's toolbar, so the
  composer draws Cancel and Post itself there (`composerHost`).
- Shared media goes up in the first type a server stores (JPEG, PNG, HEIC, GIF,
  WebP; MPEG-4 or QuickTime for video). An image offered only as something
  else — a Mac's TIFF — is handed to the composer as it is, typed by its
  bytes, and the uploader converts it for the account's server: to HEIC, or
  to JPEG only for a server without HEIC (docs/07 §4).

## 7. App Intents and Shortcuts

Target: `AlohaIntents`.

| Intent | Parameters | Behaviour |
|---|---|---|
| `PostStatusIntent` | text, visibility, media, account | Posts directly, or opens the composer when `requestValueDialog` is needed. Donatable. |
| `OpenTimelineIntent` | mode, source | Opens the app on that timeline. |
| `SearchIntent` | query, type | Opens search results. |
| `LatestMentionsIntent` | count, account | Returns mentions as an entity list, usable in Shortcuts, and Siri reads the first three aloud with their authors ("Read my mentions"). |
| `PostLastPhotoIntent` | caption, visibility, account | "Post my last photo" (iPhone, iPad, Vision Pro): the newest picture in the library, with the caption, after a confirmation naming the account. Goes the composer's way: no location, HEIC kept, spatial kept. |
| `LatestPostsFromPersonIntent` | person | "What's new from <person>?": their latest posts, the first three read aloud. The people Siri knows are the ones the account follows, refreshed with the Spotlight index (`updateAppShortcutParameters`). |
| `FavouriteStatusIntent` | status entity | For automations. |
| `NextShortIntent` | — | Opens Shorts mode. |

- `AppEntity` conformances for `AccountEntity`, `StatusEntity`, `TimelineEntity`
  with `DisplayRepresentation` and `EntityQuery`, so Shortcuts can browse them.
- `AppShortcutsProvider` with phrases for the most useful: "Post to Aloha
  Social", "Show my Aloha mentions" / "Read my mentions in Aloha Social",
  "Search Aloha Social", "Open Aloha Shorts", "Post my last photo to Aloha
  Social" and "What's new from <person> in Aloha Social".
- Intents are donated on use so Spotlight and Siri suggestions learn them.
- Control Center control (iOS): a compose control and a "latest mention" control.

## 8. Widgets

Target: `AlohaWidgets`. All widgets are configurable via `AppIntent`
configuration (account, timeline, list).

| Widget | Families |
|---|---|
| Latest posts | `systemSmall`, `systemMedium`, `systemLarge`, `systemExtraLarge` (iPad/Mac) |
| Unread notifications | `systemSmall`, `accessoryCircular`, `accessoryRectangular`, `accessoryInline` |
| Mentions | `systemMedium`, `systemLarge` |
| Quick compose | `systemSmall` (deep-links into the composer) |
| On this day | `systemSmall`, `systemMedium`, `systemLarge` (Aloha Social servers) |
| Direct messages | `systemSmall`, `accessoryCircular`, `accessoryRectangular`, `accessoryInline` |
| Next scheduled post | `systemSmall`, `accessoryRectangular`, `accessoryInline` |
| Requests (follow and message requests) | `accessoryCircular`, `accessoryRectangular`, `accessoryInline` |
| Open reports (moderators, Aloha Social servers) | `accessoryCircular`, `accessoryRectangular`, `accessoryInline` |
| Weekly stats | `accessoryCircular`, `accessoryRectangular`, `accessoryInline` |
| Conversations | `systemMedium`, `systemLarge` |
| Photo frame (Home, a hashtag, a person or a list) | `systemSmall`, `systemMedium`, `systemLarge`, `systemExtraLarge` |
| People (up to four) | `systemSmall`, `systemMedium` |
| Live poll | `systemMedium`, `systemLarge` |
| Creator dashboard | `systemMedium` |
| What's happening (server trends) | `systemMedium`, `systemLarge` |

Controls: New post, New story, Messages.

- Timelines are built from the SwiftData store in the app group, never from the
  network inside the widget extension.
- **Favourite from the widget**: post and mention rows carry a heart that runs
  an intent in the extension. It reads the token from the shared Keychain
  group, favourites on the server, and records the tap in the shared defaults
  (`WidgetFavourites`) so the row redraws filled before the next sync.
- **On this day**: memories are a server query rather than a cached timeline,
  so the app writes the day's snapshot — text and one small picture each, none
  from behind a content warning — into the app group when it becomes active
  and on background refresh (`MemoriesWidgetWriter`), and the widget reads
  only that.
- **Snapshot widgets**: direct messages, requests, reports, scheduled posts,
  statistics, polls, trends, people and photos are server queries too. The app
  writes one snapshot per account (`WidgetSnapshotWriter` into
  `WidgetSnapshotStore`) when it becomes active, at most every ten minutes,
  and in what is left of a background refresh. Each section is fetched on its
  own and keeps its last answer when its request fails. Pictures are shrunk
  once by the app; none comes from behind a content warning.
- **What the widgets want**: a widget's configuration lives in the extension,
  so each provider records the account, people and photo sources it shows in
  the shared defaults (`WidgetWants`), and the writer fetches those. A want not
  renewed for three days belonged to a removed widget and is dropped.
- **Account links**: a snapshot widget opens its screen as
  `alohasocial://<screen>/<account UUID>`, so a tap switches to the account the
  widget shows.
- **Smart Stack**: entries carry a `TimelineEntryRelevance` — high while
  something is unread or waiting, during the hour before a scheduled post and
  the hours before a poll closes, and zero when there is nothing.
- **Bookmark from the widget**: post and mention rows carry a bookmark beside
  the heart, recorded in `WidgetBookmarks` the same way.
- Reload triggered from the app's background refresh and after any post.
- Images come from the shared disk cache; a widget never downloads.
- Lock Screen and StandBy variants use the accessory families with the
  vibrant rendering mode handled explicitly.
- macOS widgets in Notification Centre and on the desktop: the same extension
  target builds for the Mac (bundle id `social.aloha.app.mac.widgets`, under
  the Mac app's) and is embedded in `AlohaSocialMac`. The Lock Screen
  accessory families are iPhone-only and left out there.

## 9. Live Activities

`ActivityKit`, iOS and iPadOS.

- **Media upload**: shown for any upload over 5 MB or any video. Per-file
  progress, total progress, cancel action, and a completion state that persists
  8 seconds. Dynamic Island compact, minimal and expanded presentations.
- **Countdowns to the account's own poll closing and its next scheduled post
  going out** (`EventLiveActivity`, `EventActivityAttributes`): started while
  the app is in front, when either happens within the next 60 minutes, for
  the active account. They read the widget snapshot that the app has just
  refreshed. Where that snapshot is missing or older than 15 minutes (for
  example, a build without the app group), the app asks the server for the
  scheduled posts and its own recent posts. The Lock Screen and the Dynamic
  Island (compact, minimal, expanded) show the poll's question or the post's
  text, and a countdown drawn with `Text(timerInterval:)`. It runs by itself,
  so nothing pushes an update.
  - Each activity is stale at its moment, so it says the poll closed or the
    post went out instead of freezing at 0:00. While the app runs, a timer
    ends it. Otherwise the next activation or background refresh ends it,
    with five minutes left on the Lock Screen.
  - A countdown whose post was rescheduled or deleted ends at the next
    activation.
  - A tap opens the poll's post, or the scheduled posts list.
  - Settings → Notifications → Live Activities has an off switch. The switch
    is disabled, with an explanation, when the system has Live Activities
    turned off for the app.
- Nothing else gets a Live Activity. They are for work in progress and
  moments that are about to happen, not for content.

## 10. Deep links and universal links

Custom scheme `alohasocial://`:

```
alohasocial://oauth-callback?code=…&state=…
alohasocial://timeline/{mode}/{source}
alohasocial://status/{accountID}/{statusID}
alohasocial://profile/{accountID}/{handle}
alohasocial://tag/{name}
alohasocial://compose?text=…&visibility=…&in_reply_to=…
alohasocial://search?q=…
```

Universal links: the app associates with **nothing by default** — it cannot
claim other people's domains. Instead:

- Any fediverse URL opened from elsewhere (share sheet, "Open in…", pasted) is
  resolved through `GET /api/v2/search?q={url}&resolve=true` on the **active
  account's** server, so a remote post opens with the reading account's
  relationship state and action buttons that work. This is the single most
  valuable link behaviour in a fediverse client and it must be the default.
- Where resolution fails, the URL opens in the browser with an explanation.
- In-app links to `@handle@host` and `#tag` route internally, resolved against
  the status's `mentions`/`tags` arrays first and `/api/v2/search` second.
- An "Open in Aloha Social" Safari extension is out of scope for 1.0.

`RouteResolver` is the one place any of this is parsed. Every entry point —
scheme, universal link, Handoff, Spotlight, intent, notification — produces a
`Route` and goes through it.

## 11. Handoff

- `NSUserActivity` per route with `isEligibleForHandoff`,
  `isEligibleForSearch` and `isEligibleForPrediction`.
- Activity types: `…​.viewingTimeline`, `…​.viewingStatus`, `…​.viewingProfile`,
  `…​.composing`.
- The composing activity carries the draft text, so a post started on a phone
  continues on a Mac. Media is **not** handed off (it may not exist on the other
  device); the activity says so.
- Continuation resolves through `RouteResolver` and falls back gracefully when
  the target account is not signed in on the receiving device.

## 12. Spotlight

- `CoreSpotlight` indexing of: signed-in accounts, followed accounts,
  bookmarked statuses, and saved searches. **Not** the general timeline —
  indexing a stranger's posts onto the device's search index is not something
  anybody consented to.
- Index updates on bookmark, on follow, and during the maintenance background
  task.
- Index entries are deleted when the account is removed, immediately and
  completely.
- `CSSearchableItemAttributeSet` with thumbnail, title, content description, and
  the `alohasocial://` URL as `relatedUniqueIdentifier`.
