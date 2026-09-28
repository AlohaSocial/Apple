# 06 — Media modes

The product's differentiating idea. Six modes, each a distinct top-level
destination with its own navigation model, layout and gestures.

## 1. Why modes rather than filters

A photo post, a 40-minute talk, a 12-second vertical clip and a linked article
want four different screens. A single list that renders all four is what every
Mastodon client already does, and it is why people install Pixelfed's and
PeerTube's apps alongside it.

Each mode owns:

- its own timeline key and cache (`mode:photos:home`, `mode:video:public`, …),
- its own source selection (Home / Local / Global / a list / a hashtag),
- its own layout, gestures and player behaviour,
- its own Explore surface where the server has one.

What they share: the account list, the status model, the composer, the media
viewer, the action set, and the moderation tools. A post boosted in Shorts is
boosted in Home.

## 2. Sourcing

| Mode | Nextcloud Social | Any other server |
|---|---|---|
| Home | `/timelines/{home,public}` | same |
| Photos | `+ only_media=true` | fetch normally, filter to statuses whose attachments are all images, over-fetch ×3 to fill a page |
| Video | `+ only_video=true` | filter to statuses carrying a `video` attachment, over-fetch ×5 |
| Shorts | `+ only_video=true`, then client-side short classification | as Video, then classification, over-fetch ×8 |
| News | `+ only_news=true` | **mode hidden** — there is no client-side equivalent worth faking |
| Audio | filter to `audio` attachments | same |

Client-side filtering rules:

- Over-fetching is capped: at most 5 upstream pages per user-visible page, and
  the loop stops early if a page returns fewer than `limit` rows.
- A filtered-out status is still cached as a `StatusRecord` (it may be needed by
  Home) but gets no `TimelineEntry` in the mode's timeline.
- The `Link` header cursor from the **last upstream page fetched** is what the
  mode pages from, so no rows are skipped.
- The UI says, once, in the mode's empty state, that this server does not
  support media filtering and results may be sparse.

## 3. Video mode

For PeerTube-style long-form video.

### Layout

- **iPhone**: a vertical list of large 16:9 cards — thumbnail with duration
  badge and a watched-progress bar, title (the first line of the status body
  or the post's `spoiler_text`), channel/author row, view context, and the
  action row. Tapping opens the player screen.
- **iPad / Mac / Vision Pro**: a grid (adaptive, minimum 320 pt) with the same
  cards; the detail column holds the player, description, and comment thread.
- **tvOS**: a shelf-based browse UI — Continue Watching, Trending, Following,
  Local, Global — with focus-driven previews.

### Sections

1. **Continue watching** — `GET /api/v1/videos/continue`, shown only when the
   capability is present and the list is non-empty. Excludes anything under 10 s
   watched and anything past 95 % (the server drops those itself).
2. The selected timeline.

### Player

`AVPlayer` in an `AVPlayerViewController`-backed view (`VideoPlayer` on
platforms where it suffices), with:

- **Source selection**, in order:
  1. `attachment.hls_url` — the local transcoding ladder's master playlist, when
     the administrator enabled `video_ladder` and the job has run. Adaptive
     bitrate, so it is always preferred.
  2. For a federated PeerTube video, `GET /media/playlist/{nid}` — the rewritten
     HLS playlist that proxies every segment back through the Nextcloud.
     **Never point the player at the origin host**: Nextcloud's CSP forbids it,
     and it would announce every viewer to a server they did not choose.
  3. `attachment.url` — the plain file. `GET /media/{uuid}` honours `Range` and
     always sends `Accept-Ranges: bytes`, so seeking works.
- **Fallback is mandatory**: a 404 on the master playlist means no ladder
  exists, and the correct response is to play `url`. A ladder that fails to load
  mid-stream falls back to `url` at the current position.
- Poster frame: the attachment's `preview_url`, which for a video is its poster
  frame served as `image/jpeg`.
- PiP, AirPlay, external playback, `AVAudioSession` `.playback` category,
  background audio continuation, Now Playing metadata, and lock-screen controls.
- Playback rate control (0.5×–2×), subtitle/audio track selection where the
  media has them, and a chapter list where the description contains timestamps.

### Watch positions

- Report `POST /api/v1/statuses/{nid}/watched` with `position` and `duration`
  **every 10 seconds of playback and on pause, background, and dismissal** —
  coalesced, never more than once per 5 s (the server allows 600/min; this is
  well inside it).
- Never report for a video under 10 s of watched time.
- Mirror locally in `WatchPositionRecord` so the progress bar is right offline.
- A video watched past 95 % is forgotten by the server; the client mirrors that
  and clears its local row too.
- "Remove from Continue Watching" calls `DELETE /api/v1/statuses/{nid}/watched`.
- This is per-reader, never federated, never shown to anyone else. The UI must
  not imply otherwise.

### Comments

The status's `/context` descendants, rendered as a threaded comment list below
the player. Posting a comment is an ordinary reply through
`POST /api/v1/statuses`.

### Dislikes are read-only

A federated PeerTube video carries `dislikes_count` and `disliked`, and the row
shows the count. It is **not** a button: the server publishes the field and
serves no route to write one (`DislikeService` is wired to no controller), so a
button there 404s on every video that has one. `Endpoint.statusExtras.dislike`
exists against the day the server grows the route.

## 4. Shorts mode

For Loops-style short vertical video. **This is the mode with no server-side
support anywhere**, so its classification rules are part of the contract.

### Classification

A status is a **short** when it carries exactly one attachment of kind `video`
(or `gifv`) and:

```
duration ≤ 180 s            // from meta.original.duration
AND aspect ratio ≤ 1.0      // from meta.original.{width,height}; portrait or square
```

Additional signals, any of which promotes a status that fails the aspect test:

- the status or its tags contain `#loops`, `#short`, `#shorts`, `#reel`;
- the attachment's `meta.original.duration ≤ 60 s` regardless of aspect.

Where `meta` is missing — which happens, since Nextcloud Social fills `meta`
only for what it probed — the classification is deferred: the status is
provisionally excluded from Shorts, and reclassified once the player reports
`AVAsset` dimensions and duration. The reclassification is persisted on
`StatusRecord.contentKindRaw` so it costs nothing twice.

Classification is a pure function in `AlohaModels` (`ContentClassifier`) with
unit tests over a fixture corpus. It is the single place the rule lives.

> **Server opportunity, not a requirement:** an `only_short` narrowing on
> `/api/v1/timelines/{timeline}/`, decided on the write the same way `only_video`
> and `only_news` are, would make this mode exact instead of heuristic. Worth
> proposing upstream; the app must work without it.

### Experience

- Full-screen vertical pager, one short per page, edge to edge, ignoring safe
  areas except for the action rail and the caption.
- Autoplay on appear, loop, **start muted with a persistent mute toggle whose
  state is remembered** across sessions and modes.
- Preload: the next **3** items' first segments and the previous 1. At most 3
  live `AVPlayer` instances (the `VideoPlayerCoordinator` pool); everything
  else is a poster image.
- Gestures: vertical swipe advances, double-tap favourites (with a heart burst
  that respects Reduce Motion), long-press pauses and reveals the scrubber,
  horizontal swipe from the right edge opens the author's profile.
- Action rail on the trailing edge: avatar (tap → profile, with a follow badge),
  favourite, boost, comment count → thread sheet, share, more.
- Caption overlay at the bottom: author handle, the status body truncated to two
  lines and expandable, hashtags tappable.
- Sensitive shorts are **not** autoplayed under `default` or `hide_all` policy;
  they show the blurhash and a tap-to-play.
- Reduce Motion replaces the paging animation with a cross-fade and disables
  auto-advance at the end of a loop.
- Battery: pause all playback when the app backgrounds, and when the pager is
  scrolled past 3 items in under a second (fast-scrubbing). Low Power Mode does
  **not** stop autoplay — see the policy below.

### Autoplay policy

**Autoplay is always on, everywhere, on every network.** Shorts, video cards in
Video mode, video and GIFV attachments in Home and Photos — all of them play on
appear, on Wi-Fi and on cellular alike. There is no network condition under
which the app declines to play a video.

This is a deliberate product decision, and it costs cellular data. What follows
from it:

- **No "Wi-Fi only" autoplay setting.** A single Settings toggle, *Autoplay
  video*, defaults on and exists for the person who wants silence rather than
  for the network. Turning it off stops autoplay everywhere; there is no
  per-network middle state to reason about.
- **Low Power Mode does not stop autoplay.** It reduces the preload depth in
  Shorts from 3 items to 1 and stops the poster-preview autoplay on
  focus in tvOS shelves, and that is all.
- **Adapt the bitrate, not the decision.** Where a video has an HLS ladder
  (`hls_url`, or `/media/playlist/{nid}` for federated PeerTube), `AVPlayer`'s
  ABR is left to choose the rung, with
  `AVPlayerItem.preferredPeakBitRateForExpensiveNetworks` set on a cellular or
  hotspot path so the same video plays at a smaller rung rather than not at all.
  A video with no ladder plays its single file.
- **Preload stays bounded** so "always on" does not mean "always downloading":
  at most 3 items ahead and 1 behind in Shorts, and only the visible card in
  every other mode. Preload is cancelled on scroll-direction change.
- **Honour Low Data Mode for preloading only.** When
  `NWPath.isConstrained` is true, preload drops to 1 item ahead. The currently
  visible video still autoplays.
- **Sensitive media is still not autoplayed** under the `default` or `hide_all`
  reading policy — that is a consent decision, not a network one, and it stands.
- **Audio never starts unmuted.** Autoplay means picture; sound is the person's
  choice, and the mute state persists across sessions and modes.

The settings screen states the cost in one line under the toggle: "Videos play
automatically, including on cellular."

## 5. Photos mode

For Pixelfed-style image posts.

### Layout

- **Grid** (default): a 3-column square grid on iPhone, adaptive on larger
  screens, blurhash placeholders, multi-attachment posts carrying a stack badge.
- **Feed**: a single-column large-image feed with full captions and the action
  row — the layout people expect from a photo app.
- The toggle lives in the mode's toolbar and is remembered.

### Detail

Tapping a cell opens the media viewer (§8) with the caption, alt text, author,
action row, and a "View post" affordance that pushes the thread.

### Collections

Where `capabilities.collections`: an Albums section in the mode and on profiles,
backed by `/api/v1/collections`. Create, rename, delete, add and remove posts
(`POST /api/v1/collections/{id}/items`). This is a real Nextcloud/Pixelfed
feature and a good reason for the mode to exist.

### Explore

Where the Pixelfed routes are present: trending posts
(`/api/v1.1/discover/posts/trending`), trending hashtags
(`/api/v1.1/discover/posts/hashtags`), network trending
(`/api/v1.1/discover/posts/network/trending`), popular accounts
(`/api/v1.1/discover/accounts/popular`). These are backed by the same
`TrendService` and `SuggestionService` as the Mastodon trend routes, so nothing
can be popular on one and absent from the other — do not merge or dedupe them,
just pick the Pixelfed shape here because it is image-first.

## 6. Stories

Where `capabilities.stories`.

- A horizontal carousel at the top of **Photos mode** and on profiles: own
  stories first, then followed accounts', oldest first — the order the server
  returns from `/api/v1/stories/carousel`, which is the order to play them in.
  Unseen ones ring-highlighted from the `seen` flag.
- Tapping opens a full-screen story player: tap-forward, tap-back, hold-to-pause,
  swipe-down to dismiss, segment progress bars across the top.
- `POST /api/v1/stories/{id}/seen` fires as each story becomes visible;
  it is idempotent, so a repeat is a no-op rather than a second view.
- Own stories additionally show `view_count`, which the server fills in only on
  `/stories/carousel` and `/stories/self` — how many people watched is told to
  the poster and to nobody else. Who they were, and what they said back, are
  Pixelfed's `v1.2` routes: `/stories/viewers`, `/stories/reactions`,
  `/stories/react` and `/stories/comment`. **Pixelfed names the story in a `sid`
  parameter rather than in the path** — `PixelfedController` serves no
  `/api/v1/stories/{id}/…` shape at all, so a path-style call 404s however
  reasonable it looks.
- Posting: one image or video from the composer's Story affordance —
  `media_id` required, `caption` ≤ 500 characters, `duration` clamped to 3–30
  seconds, max 40 live at once.
- Expiry: never longer than 24 h from insert, enforced client-side as well as by
  the server, because the promise of the feature is that the thing goes away.
  Ending one early is `DELETE /api/v1/stories/{id}`, falling back to Pixelfed's
  own `POST /api/v1.1/stories/self-expire/{id}` on a 404 — a server that serves
  its story routes and not Mastodon's answers there instead, and a 404 on the
  first must not read to the poster as "could not be deleted".
- **Expect the carousel to be sparse.** Pixelfed only fans stories out to
  instances it has identified as Pixelfed, so stories from Pixelfed accounts do
  not arrive at a Nextcloud Social instance at all. The empty state says
  "No stories right now", never anything that reads as an error.

## 7. News and Audio modes

Both off by default, enabled in Settings.

**News** — only where `capabilities.onlyNewsFilter`. A reading-oriented list:
large link cards from `Status.card` (title, description, provider, image),
the poster's comment above, and a reader-friendly row height. Tapping the card
opens the link in `SFSafariViewController` (iOS) / the default browser (Mac),
with a Reader-mode preference. Tapping anything else opens the thread.

**Audio** — statuses whose attachments are `audio`. A list with inline players,
a persistent mini-player docked above the tab bar / in the sidebar footer,
background playback, `MPNowPlayingInfoCenter` metadata (title from the status
body's first line, artist from the author, artwork from the attachment preview
or the author's avatar), lock-screen and CarPlay-less remote commands, and a
playback queue built from the visible list.

## 8. The shared media viewer

One component, used from every mode and from the thread view.

- Full-screen, edge to edge, over a dimmed backdrop.
- **Pinch to zoom** (to 5×), pan when zoomed, double-tap to toggle fit/fill.
- **Drag to dismiss** with interactive scaling and backdrop fade; a matched
  geometry transition from the source cell.
- **Swipe horizontally** between a status's attachments, with an index indicator.
- **Alt text**: an "ALT" badge on any attachment carrying a `description`;
  tapping shows it in a sheet. Where a description is missing the badge is
  absent — never a fake one.
- Actions: Save to Photos (with the usage description and a permission-denied
  path), Share, Copy, Open in Browser, and — for video — PiP and AirPlay.
- Video attachments inside the viewer use the same source-selection ladder as
  Video mode (§3).
- Keyboard on Mac/iPad: arrows to move, space to play/pause, `+`/`-` to zoom,
  escape to dismiss.
- The viewer is a single `MediaViewerScene` taking `[MediaAttachment]` and a
  start index, and knows nothing about which mode opened it.

## 9. Cross-mode rules

1. **One status, one truth.** An action taken in any mode updates the shared
   `StatusRecord` and every mode showing it, in the same frame.
2. **Modes never disagree about visibility.** Filters, blocks, mutes and the
   sensitive-media policy apply identically everywhere.
3. **A mode with no server support is hidden, not broken.** News on a
   non-Nextcloud server simply does not appear in the tab bar or sidebar.
4. **No mode invents content.** Nothing is re-ranked, re-ordered, or injected.
   Ordering is the server's, filtering is the reader's.
