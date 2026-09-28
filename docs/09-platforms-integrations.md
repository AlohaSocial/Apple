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
- Complications (`WidgetKit` on watchOS): unread notification count
  (`.accessoryCircular`, `.accessoryCorner`) and latest mention
  (`.accessoryRectangular`, `.accessoryInline`).
- Data arrives via `WCSession` transfer from the phone's background refresh,
  plus an independent `URLSession` fetch when the watch is on Wi-Fi and the
  phone is unreachable.
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

## 7. App Intents and Shortcuts

Target: `AlohaIntents`.

| Intent | Parameters | Behaviour |
|---|---|---|
| `PostStatusIntent` | text, visibility, media, account | Posts directly, or opens the composer when `requestValueDialog` is needed. Donatable. |
| `OpenTimelineIntent` | mode, source | Opens the app on that timeline. |
| `SearchIntent` | query, type | Opens search results. |
| `LatestMentionsIntent` | count, account | Returns mentions as an entity list, usable in Shortcuts and readable by Siri. |
| `FavouriteStatusIntent` | status entity | For automations. |
| `NextShortIntent` | — | Opens Shorts mode. |

- `AppEntity` conformances for `AccountEntity`, `StatusEntity`, `TimelineEntity`
  with `DisplayRepresentation` and `EntityQuery`, so Shortcuts can browse them.
- `AppShortcutsProvider` with phrases for the three most useful:
  "Post to Aloha Social", "Show my Aloha mentions", "Open Aloha Shorts".
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

- Timelines are built from the SwiftData store in the app group, never from the
  network inside the widget extension.
- Reload triggered from the app's background refresh and after any post.
- Images come from the shared disk cache; a widget never downloads.
- Lock Screen and StandBy variants use the accessory families with the
  vibrant rendering mode handled explicitly.
- macOS widgets in Notification Centre and on the desktop.

## 9. Live Activities

`ActivityKit`, iOS and iPadOS.

- **Media upload**: shown for any upload over 5 MB or any video. Per-file
  progress, total progress, cancel action, and a completion state that persists
  8 seconds. Dynamic Island compact, minimal and expanded presentations.
- **Scheduled post countdown**: optional, shown in the 15 minutes before a
  scheduled post goes out, with an Edit action.
- Nothing else gets a Live Activity. They are for work in progress, not for
  content.

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
