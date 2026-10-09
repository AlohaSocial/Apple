# 05 — Core UI

## 1. Structure

Six modes, one shared chrome.

**iPhone** — `TabView` with a bottom bar. Default tabs: **Home**, **Photos**,
**Video**, **Shorts**, **Notifications**, **Profile**. Search and Settings are
reached from Home's toolbar. The mode set and its order are user-configurable;
News and Audio are off by default and enabled in Settings. A compose button
floats above the tab bar on Home, Photos and News.

**iPad, Mac, Vision Pro** — `NavigationSplitView`, three columns.

- *Sidebar*: the modes, then Direct messages and Discover; then Lists, My
  interests and Subscriptions. The search field is at the top, as it is on the
  web, and the account drawer is at the bottom.
- *Account drawer*: My profile, **Activities**, Follow requests, Liked posts,
  Bookmarks, Archived posts, Statistics, Blocking, Settings, and the other
  accounts to switch to.

  Activities lives here rather than in the sidebar above: the sidebar is feeds —
  things to read — and Activities is about you, like everything else in the
  drawer. It is the one row that answers "what happened to me", so it sits
  directly under the profile it happened to.
- *Content*: the selected timeline.
- *Detail*: the selected status's thread, or a profile, or a media viewer.

**Mac** additionally: multiple windows (`⌘N` for a new window on the current
route, `⌘⌥N` for a new compose window), a full menu bar, and every navigation
action available as a keyboard shortcut.

Navigation state is a `Codable` `Route` enum per column, which gives state
restoration, Handoff and deep-linking for free.

## 2. Visual identity

Aloha Social has its own look. It is not an Ice Cubes clone.

### Direction

Warm, high-contrast, content-forward. The chrome recedes; media and text do not
compete with it. The iOS/macOS 27 material system is used as intended — floating,
translucent controls layered over content that scrolls beneath them, with the
concentric corner radii the platform provides rather than hand-picked numbers.
No custom blur stacks, no reimplemented navigation bars.

### Colour

- Semantic roles only in view code: `Aloha.background`, `.surface`,
  `.surfaceRaised`, `.separator`, `.label`, `.secondaryLabel`, `.tertiaryLabel`,
  `.accent`, `.accentMuted`, `.destructive`, `.boost`, `.favourite`,
  `.bookmark`, `.mention`, `.hashtag`.
- Every role defined for light and dark, and for increased-contrast variants of
  both. Asset catalog colour sets with all four appearances; never a literal
  colour in a view.
- The accent is a warm coral-to-amber; boost is green, favourite is amber,
  bookmark is violet — kept distinct at the smallest size a badge is drawn and
  distinguishable under the common colour-vision deficiencies, verified by the
  contrast test in [12-conventions-quality.md](12-conventions-quality.md) §5.
- **Themes**: a small set of built-in themes (System, Warm Light, Warm Dark,
  High Contrast Light, High Contrast Dark, Dim, Black) plus a custom theme with
  a user-chosen accent. Themes change colour roles only, never layout or type
  scale.

### Typography

- System font throughout, with a rounded design for numerals and counts and a
  serif option for status body text as a reading preference.
- Type scale bound to Dynamic Type at every size, including the accessibility
  sizes. No fixed point sizes anywhere.
- User-adjustable body-text size offset (−2…+4 steps) and line spacing, applied
  on top of Dynamic Type.

### Motion

Every animation respects `accessibilityReduceMotion`, which replaces slides and
scales with cross-fades and disables the Shorts auto-advance animation. Haptics
respect the system setting and have a separate app toggle.

### The accent colour

**The server's, not a preference.** Read from Nextcloud's own `theming`
capability — `GET /ocs/v2.php/cloud/capabilities` at the Nextcloud root, which
is public and which the Social API does not duplicate. An administrator who has
themed their Nextcloud has already chosen the colour their people know that
server by; asking again in here gets two answers to one question.

A plain Mastodon, and a Nextcloud with the Theming app off, leave the app's own
warm accent in place.

The colour is taken as an intention rather than used raw. Nextcloud publishes
the primary darkened for a light background and lightened for a dark one, and
the app picks the right one per scheme — then checks it against *its* ground,
which is not the one Nextcloud computed against, and walks the lightness until
it reaches 4.5:1. The hue and saturation are held, because those are what make
it their colour. Nextcloud's own default blue needs this: it is 4.0:1 on the
app's light ground. A colour that still cannot be rescued is declined and the
app's accent stays, because an unreadable accent is worse than one that is not
quite theirs.

`onAccent` follows the same rule, measured against the *adjusted* colour, and
prefers the server's `color-text` only where that passes too. Boost green,
favourite amber and bookmark violet never move: they carry meaning.

The **app icon** is still a choice (`AlohaIconVariant`), because an icon is
about finding the app on a crowded Home Screen rather than about the server.

## 3. Timeline

The most-used screen. It must be fast and it must never lie about ordering.

### The row

```
┌───────────────────────────────────────────────┐
│ ⟳ Boosted by Alice                            │  ← context line, only when present
│ ┌──┐  Display Name  @handle@host  ·  2h  ···  │
│ │AV│  ┌─────────────────────────────────────┐ │
│ └──┘  │ Content warning: election talk      │ │  ← only when spoiler_text
│       ├─────────────────────────────────────┤ │
│       │ Body text, parsed rich text, with   │ │
│       │ mentions and #hashtags routed       │ │
│       │ in-app and custom emoji inline.     │ │
│       └─────────────────────────────────────┘ │
│       ┌─────────────────────────────────────┐ │
│       │        media / poll / card          │ │
│       └─────────────────────────────────────┘ │
│       ↩ 3     ⟳ 12     ★ 40     🔖     ···    │
└───────────────────────────────────────────────┘
```

Rules:

- **The context line** carries boost attribution, reply attribution ("Replying
  to @bob"), pin markers, and filter warnings. One line, never two.
- **Handles show the host** when it differs from the reading account's host.
- **Content warnings collapse the body and the media**, both, and the
  disclosure state is per-status and remembered for the session only.
- **Sensitive media** obeys the account's `reading:expand:media` preference:
  `show_all` renders it, `default` blurs it with the blurhash and one tap
  reveals, `hide_all` does not draw it at all and requires opening the status.
- **Counts** are hidden when zero, and the whole action row is a single
  accessibility element group with per-action actions.
- **Long-press** on a row opens a context menu with every action including
  Share, Copy Link, Open in Browser, Translate, Report, Mute Conversation, and
  (own posts) Edit, Delete, Delete & Redraft, Pin.
- **Swipe actions** are configurable: leading pair and trailing pair, each
  chosen from reply / boost / favourite / bookmark / share / none.

### Performance requirements

- `List` with `.id`-stable rows, no `ForEach` over recomputed arrays.
- Rich text parsed off the main actor and cached by content hash; a row that
  scrolls into view with an uncached parse renders plain text for one frame
  and upgrades — never blocks.
- Images requested at the exact target size; blurhash placeholder painted
  immediately; no layout shift when the real image arrives (aspect ratio comes
  from `meta.original.aspect`, or from the blurhash's own dimensions, or a
  4:3 default).
- Prefetch the next 10 rows' media; cancel on scroll direction change.
- Target: 120 Hz sustained on ProMotion devices, no frame over 8 ms.

### Loading and refresh

- Paints from cache instantly. Refresh is implicit on appear (if older than
  60 s) and explicit on pull.
- New content arriving above the current scroll position **never moves it**.
  Instead a floating "N new posts" pill appears; tapping it scrolls to top and
  inserts. This is a hard requirement.
- "Load more" gap rows as described in [04-data-model.md](04-data-model.md) §3.
- Infinite scroll pages on `next` from the `Link` header, triggered 10 rows from
  the end, one request in flight at a time.
- **Remember position across launches** per timeline, restored only if the
  cached entry is still present.

### Keyboard

On **macOS** the timeline takes the web app's keys, with the web app's guard:
they fire only while the list itself has keyboard focus, so a letter typed into
a search field or the composer is a letter.

macOS only, because `.focusable()` is what delivers the keys, and on iOS it also
makes the whole list a single focusable, activatable element — enough to change
hit-testing and to put a container in the accessibility tree that VoiceOver must
then be driven through. The `⌘` shortcuts work everywhere.

`J`/`K` move a focus ring through the posts and scroll it into view; `L` or `F`
likes the one in focus, `B` boosts it, `R` replies, `O` or `Return` opens it;
`?` shows the list of them. `⌘N`, `⌘F` and `⌘⏎` work anywhere. The list is
generated from one table, so a shortcut cannot be documented without existing or
exist undocumented.

## 4. Thread view

- Fetches `/api/v1/statuses/{id}/context` and renders ancestors above, the
  focused status enlarged in the middle, and descendants below as an indented
  tree.
- The focused status scrolls to a stable position on open, with ancestors
  already laid out above it — no jump.
- Indentation is capped at 5 levels with a thread line; deeper replies collapse
  behind "Show N more replies".
- Edit history (`/history`) is available from the status's menu when
  `edited_at` is non-nil, shown as a diff between versions.
- Favourited-by / boosted-by / quotes / reactions lists are pushed views.

## 5. Profile

- Header image, avatar, display name with custom emoji, handle, bot badge,
  join date, fields table with verified-link checkmarks, note (rich text),
  follower/following/post counts, and the relationship state.
- Relationship controls: Follow / Unfollow / Cancel request, a **bell** for
  post notifications, a **hide boosts** switch (Nextcloud Social honours
  `reblogs` on `POST /accounts/{id}/follow` and enforces it in the timeline
  query, not by filtering a page), Add to list, Mention, Direct message,
  Block, Mute (with duration and "also mute notifications"), Report, Block
  domain, Add note.
- Tabs: Posts · Posts & Replies · Media · Videos · Collections (where the
  server has them) · Stories (where present and visible).
- Own profile additionally: Edit profile (`PATCH /accounts/update_credentials`
  — name, avatar, header, note, fields, bot, locked, discoverable, and
  `source[privacy]`). **A Nextcloud with an external identity backend (LDAP,
  SAML) answers 422 for name and avatar**; the UI must show that as "Your
  server manages your name and picture" rather than as a failure.

## 6. Notifications

- Prefers `GET /api/v2/notifications` (grouped) where
  `capabilities.groupedNotifications`; falls back to v1.
- Groups render as one row: "Alice, Bob and 34 others favourited your post",
  with a stacked avatar row. Tapping the count opens
  `/api/v2/notifications/{group_key}/accounts`.
- Mentions never group. Polls, edits and moderation decisions never group.
- Filter chips across the top: All · Mentions · Boosts · Favourites · Follows ·
  Polls · Updates. Backed by `types`/`exclude_types`.
- Unread count from `/api/v2/notifications/unread_count` (groups, not rows) or
  the v1 route, both capped at 99 by the server.
- The read marker is `POST /api/v1/markers` with `notifications[last_read_id]`.
  **Markers never move backwards** — the server enforces it and so must the
  client, so two devices do not un-read each other.
- **Notification policy** (`/api/v2/notifications/policy`, v1 fallback): a
  settings screen with the five decisions (`for_not_following`,
  `for_not_followers`, `for_new_accounts`, `for_private_mentions`,
  `for_limited_accounts`), each `accept` / `filter` / `drop`. Note that on
  Nextcloud Social **`drop` behaves as `filter`** — the UI says so in a footnote
  rather than pretending otherwise. The policy screen is reachable from both
  Settings → Notifications and the Notifications screen; when there are
  pending filtered requests, their count is shown next to the policy link.
- **Requests inbox** (`/api/v1/notifications/requests`): one row per held
  sender with their count and latest post, with Accept / Dismiss, and bulk
  accept/dismiss for a screenful. Unknown senders must be easy to clear.
- **Conversation mute** — on mention and reply notifications, a context menu
  action and a push-notification action to mute (or unmute) the conversation.
  The post menu reads "Unmute conversation" when the conversation is already
  muted.
- **"Show numbers" switch** (Settings → Notifications) — hides reply/boost/
  favourite counts on posts, follower/following/post counts on profiles, the
  "and N others" tail of grouped notifications, story view counts, and the
  follower figures in the year-in-review. Poll results, unread counts and
  character limits stay.

## 7. Search and Explore

One screen, segmented.

- **Search** — `/api/v2/search` with `type` narrowing, `resolve=true` when the
  query looks like a URL or a handle. Results in three sections: Accounts,
  Hashtags, Posts. Recent searches stored locally and clearable.
  `/api/v1/accounts/search` is used for the composer's `@` autocomplete, since
  no other route substitutes for it.
- **Explore** — Trending hashtags (`/trends/tags`, with the period selector the
  server supports: `1h`, `12h`, `1d`, `3d`, `10d`), trending posts
  (`/trends/statuses`), trending links (`/trends/links`), suggested accounts
  (`/api/v2/suggestions`, dismissible via `DELETE /suggestions/{id}`), and the
  directory (`/api/v1/directory`).
  Note Nextcloud Social's `Tag.history` carries a single bucket and
  `accounts` is always `0` — the UI must not draw a sparkline from one point or
  claim a participant count. Show uses only.
- **Other servers' directories** (`/api/v1/directories`, `/directories/search`)
  appear as an extra section where the capability is present.
- **The directory** — this instance's own, the accounts here that opted in,
  ordered by most recently active or most recently joined. Nobody appears
  without opting in, and the footer says so.
- **The follow constellation.** The same walk the suggestion list uses
  (`/api/v1/follow_graph`), drawn instead of listed: you in the middle,
  everybody the walk found on rings around you, each star sized by how many of
  your follows follow them. Tapping one opens who it came through and a Follow
  button. Laid out deterministically — golden-angle placement rather than a
  physics simulation — because the same graph has to draw the same way twice, or
  dragging it becomes a way of losing somebody you had just spotted. Capped at
  24 stars, past which the rings overlap into a smudge. A per-device switch, off
  by default: the list answers "who should I follow", the constellation answers
  "who is around me", and the web app offers both for that reason.

### Messages

A new message opens on **mutual follows** (`/api/v1.1/direct/compose/mutuals`)
rather than an empty search field: most messages go to somebody already
followed, and making a person search for them first is a step that answers its
own question. Search is still there underneath, and the section simply does not
appear on a server without the route.

A conversation can be deleted and the whole list marked read. Deleting takes the
conversation off the list and leaves the messages alone on both sides — a later
message brings it back — which the row says, because "delete" reads stronger
than what it does.

## 8. Lists, hashtags, bookmarks, favourites, conversations

- **Lists**: CRUD, membership management, per-list `replies_policy` and
  `exclusive` where supported. A list's timeline is
  `/api/v1/timelines/list/{id}` and accepts the same media filters, so a
  "Photos from this list" view is free.
- **Followed hashtags**: `/api/v1/followed_tags`, with follow/unfollow from any
  hashtag chip. Note hashtags normalise to lowercase, no `#`, ≤127 characters —
  `#NextCloud` and `nextcloud` are one tag. Something that normalises to nothing
  is a 422, which the UI reports as "That isn't a hashtag".
- **Tag groups**: a local-only feature — several hashtags viewed as one
  timeline, merged client-side from parallel requests, deduplicated by status
  id, ordered by `created_at`.
- **Bookmarks** and **Favourites**: plain timelines.
- **Conversations** (`/api/v1/conversations`): a chat-shaped view of direct
  messages, one row per conversation with the last message and unread state;
  opening it shows the thread and a reply field pre-filled with the
  participants and visibility locked to direct. Mark read via
  `POST /conversations/{id}/read`.

## 9. Settings

Grouped, searchable (on platforms with settings search).

- **Accounts** — list, add, reorder, sign out, per-account settings.
- **Appearance** — theme, accent, text size offset, line spacing, serif body,
  avatar shape (circle/rounded square), compact/comfortable/spacious density,
  show/hide counts, hide the app badge.
- **Modes** — which modes appear, in what order, on which platforms.
- **Timeline** — default timeline on launch, restore position, show boosts,
  show replies, swipe actions, tap-to-open behaviour, "N new posts" pill on/off.
- **Media** — autoplay video (on by default, and on every network — there is no
  Wi-Fi-only state; see [06-media-modes.md](06-media-modes.md) §4), loop shorts, start muted,
  sensitive-media policy (writes `PUT /api/v1/preferences` where supported,
  otherwise local-only), image quality on cellular, download quality.
- **Composer** — default visibility, default language, default sensitive,
  always show content-warning field, confirm before posting, thread numbering.
- **Notifications** — per-type local notification toggles, polling frequency,
  quiet hours, the server-side policy screen, the requests inbox.
- **Intelligence** — the on-device AI toggles. See
  [10-ai-features.md](10-ai-features.md).
- **Filters** — v2 filter management: a filter is a title, the contexts it
  applies in, warn or hide, an optional expiry and the words that match. **v2
  only**: a filter of three words is three ids in v1 and one in v2, and an
  editor that mixed the two would delete the wrong row. Keywords are edited in
  place with Rails' `keywords_attributes[n][…]`, which is the shape both
  Mastodon and Nextcloud Social take; a removed one is sent with `_destroy`
  rather than left out, because the server leaves what it is not told about
  alone. Saving refreshes the local store too, so a new filter takes effect over
  cached content immediately.
- **Sound & touch** — a tick on a like, a breath of air on a post, a two-note
  chime for a direct message, and a tap in the hand. Device-local, never sent to
  the server. Sound is off until it is turned on; touch follows Reduce Motion.
- **Moderation** — the moderator's screens, where the account is an
  administrator of the Nextcloud. See
  [11-safety-privacy-appstore.md](11-safety-privacy-appstore.md) §7.
- **Privacy & Safety** — blocked accounts, muted accounts, blocked domains,
  data & storage, clear cache.
- **Your year** — the annual report, under Your account. Mastodon's
  `#Wrapstodon` over `/api/v1/annual_reports`: an archetype in a sentence, a
  month-by-month chart of posts and arrivals, the hashtags, and the three posts
  that travelled furthest. Nextcloud Social serves this and its own web client
  has no page for it, so the app is the first place it can be read. `generate`
  is still called before reading — this server answers instantly with nothing to
  do, and a server that does need it will act on it.
- **About** — version, licences, source link, the keyboard shortcuts, the
  server's privacy policy and terms (`/instance/privacy_policy`,
  `/instance/terms_of_service`, both of which 404 where the administrator has
  published none — the row is then hidden, not shown broken), and **About this
  server**: the weekly activity series, the instances it has heard of, and the
  servers it refuses where the administrator publishes that list
  (`/instance/activity`, `/instance/peers`, `/instance/domain_blocks`). Each of
  the three can legitimately answer with nothing, so each section hides itself
  rather than showing a broken row.

## 10. Empty, error and offline states

Every list has three non-default states and each is designed, not a spinner:

- **Empty** — an illustration-free, one-line explanation and, where possible, a
  primary action ("Follow some people", "Find your first server").
- **Error** — what failed, in plain language, with Retry. Never a status code
  alone. A 422's message is shown verbatim after a lead-in.
- **Offline** — cached content plus a persistent inline strip, not a blocking
  overlay. Actions taken offline queue and say so.
