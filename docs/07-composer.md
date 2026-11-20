# 07 — Composer

## 1. Shape

One composer, presented as a sheet on iPhone, a sheet or a dedicated window on
iPad, and always a separate window on Mac (`⌘⌥N` from anywhere — `⌘N` is a new
main window there, docs/09 §2 — and `⌘⏎` to post).
Not available on tvOS. On watchOS only a reduced reply composer (dictation,
scribble, emoji, canned responses).

On iPhone and iPad the sheet **grows out of the "New post" button** — the
system's zoom transition, from the toolbar's glass button
(`matchedTransitionSource`) into the sheet (`navigationTransition(.zoom)`) —
and shrinks back into it when it closes. Only for the button: a reply or a
quote comes from a post, not from it. Under Reduce Motion the sheet arrives
the plain way (`ComposerZoom`).

```
┌─────────────────────────────────────────────┐
│ Cancel        [avatar ▾ account]      Post  │
├─────────────────────────────────────────────┤
│ ⚠ Content warning                          │  ← shown when enabled
├─────────────────────────────────────────────┤
│ Replying to @bob — "original text…"        │  ← reply context, collapsible
├─────────────────────────────────────────────┤
│ What's happening?                           │
│                                             │
├─────────────────────────────────────────────┤
│ [thumb][thumb][+]           ALT ALT         │  ← media strip
├─────────────────────────────────────────────┤
│ ▣ Poll                                      │  ← when added
├─────────────────────────────────────────────┤
│ 📷 🎞 📊 ⚠ 🌐 😀 ✨ 📎        1 ▾    4 812  │  ← toolbar, thread index, counter
└─────────────────────────────────────────────┘
```

Toolbar, left to right: add media · record video · poll · content warning ·
visibility · emoji · Intelligence · attach from Nextcloud. Right: thread
position, character counter.

## 2. Text entry

- `TextEditor` with a custom `NSTextContentStorage`-backed highlighter that
  colours mentions, hashtags and URLs live without re-laying out on every
  keystroke.
- **Autocomplete** triggered by `@`, `#` and `:`:
  - `@` → `GET /api/v1/accounts/search?q=…&resolve=false&limit=8`. This route
    specifically — no client substitutes `/api/v2/search` for it, and Nextcloud
    Social serves it precisely because a composer needs it.
  - `#` → `GET /api/v2/search?type=hashtags` plus local recent tags.
  - `:` → the instance's `/api/v1/custom_emojis`, cached 24 h, grouped by
    `category` where present. Only emojis marked `visible_in_picker` are listed
    — but a hidden shortcode typed by hand still renders, so never reject one.
  - Debounced 250 ms, cancelled on further typing, results cached per query for
    the session.
- **Character counter** reads `configuration.statuses.max_characters` (5000 on
  Nextcloud, 500 on stock Mastodon) and
  `characters_reserved_per_url`, and counts a URL as that fixed cost. The
  spoiler text counts against the same budget, as Mastodon does. Over-length
  disables Post and the counter turns destructive.
- Language: defaults from `preferences["posting:default:language"]`, falls back
  to the device language, overridable per post from a picker.

### The three games

`/dice`, `/flip` and `/pick`, a port of Nextcloud's
`src/utils/composerCommands.js` and deliberately a faithful one — a post written
here and a post written in the web app must say the same thing.

Each is **replaced by its result before the post is sent**, so what travels is
plain text ("🎲 4", "🪙 heads", "🎯 pizza") and a Mastodon reader sees exactly
what a reader here sees. Nothing is rolled on the server and nothing can be
re-rolled afterwards: the result is part of what was posted. A command is only a
command at the start of a line or after a space, so a link containing `/dice` is
left alone; `/dice` takes an optional number of sides, clamped to 2…1000;
`/pick` runs to the end of its line and takes commas, or " or " when there are
none, up to 20 options, and is not a game with fewer than two. A hint under the
box says which games a post has to play; it never shows a number, because the
roll happens once, at the moment of posting.

### A short post as a card

Up to 120 characters, with nothing attached and no poll, can go out drawn big on
colour — six backgrounds, the first in the writer's own hue. Nextcloud's
`ShortComposerDialog.vue` and `textCard.js`.

Drawn to a 1080×1080 picture and uploaded as an ordinary attachment rather than
invented as a new kind of post, so it federates as what it looks like. The words
travel three ways: as the post, as the picture's description, and in the picture
— so nothing is lost on a server that only sees text, and a screen reader gets
the post rather than "image". The same SwiftUI view is both the preview and what
is rendered, so the two cannot drift. **A card that cannot be drawn stops the
post**, as the web's does: quietly becoming a plain post the writer did not
choose is worse than saying so.

## 3. Visibility and content warnings

- Visibility: Public · Unlisted · Followers only · Direct. Default from
  `preferences["posting:default:visibility"]`. A reply **cannot be less
  restrictive than the post it replies to**; the picker clamps and says why.
- Direct replies lock to Direct and show the participant list.
- Content warning: a toggle that reveals the `spoiler_text` field; a setting
  makes it always visible. `sensitive` is set automatically when a CW is present
  and can be set independently for media.
- Interaction policy (`PUT /api/v1/statuses/{nid}/interaction_policy`) where
  the capability is present: who may reply, boost, quote. Presented as three
  pickers behind a disclosure, not on the main surface.

## 4. Media

- Up to `configuration.statuses.max_media_attachments`, enforced before the
  picker opens.
- Sources: Photos picker (`PhotosPicker`, limited-library aware), Files, camera
  (photo and video), screen-recorded clips on Mac, drag-and-drop on iPad/Mac,
  paste, and **Nextcloud Files** (§6).
- **Pre-flight against the server's real limits** before upload: MIME type in
  `configuration.media_attachments.supported_mime_types`, size under
  `image_size_limit` (10 MB default) for images and `video_size_limit`
  (2048 MB default) for video. Two different ceilings, because the server reads
  an image whole into memory and copies a video a chunk at a time. Exceeding
  either produces an in-app explanation and an offer to downscale or trim —
  never a server 422 the person has to interpret.
- **Originals go up as they are.** A picture whose type the server lists —
  HEIC and HEIF included — is sent unchanged apart from its personal
  metadata (below). Only a type the server does not list is written again:
  as **HEIC** where the server takes HEIC, and as **JPEG only for a server
  that takes neither** — the one, explicit fallback
  (`ImageFormat.target(for:)`). GIF and WebP are never converted, since they
  would arrive as their first frame. A picture over `image_size_limit` is
  shrunk once, to 2048 pixels, in the same format a conversion would use.
  The decisions are one pure function, `UploadPreflight.imagePlan`, tested
  case by case. Live Photos post as the still. The camera hands over HEIC,
  the share sheet hands over what it was given, and Shortcuts go the same
  way as the composer (`MediaPreparer.prepareForUpload`).
- **Location never leaves the device.** GPS, IPTC, maker notes and the EXIF
  and TIFF fields that name a person or a device are removed from every
  picture before upload — a post's, a Shortcut's (which used to send the file
  as it came) and a profile picture or header (which did too); the
  orientation stays. JPEG, HEIC/HEIF, PNG and TIFF
  are copied with `CGImageDestinationCopyImageSource` and replacement
  metadata, so nothing is recompressed and nothing in the container that is
  not metadata is lost — a spatial photo's second eye, a depth map, a gain
  map, the colour profile. (`kCGImageMetadataShouldExcludeGPS` alone, without
  replacement metadata, leaves the GPS where it was.) Other kinds are drawn
  again without it. There is no setting to keep a location.
- **Spatial photos** (a stereo pair group in a HEIC, from an iPhone 15 Pro or
  later or Apple Vision Pro) go up with both eyes on a server that takes HEIC,
  and the composer marks them **Spatial**. One is never written again to make
  it smaller — that would keep one eye — so a spatial photo over the limit is
  refused, with the limit named. On a server that takes no HEIC at all it
  cannot stay spatial whatever is done, and goes up as an ordinary picture.
  Filters are not offered on one, for the same reason.
- Upload via `POST /api/v2/media` (fall back to `/api/v1/media` on 404), one at
  a time with a concurrency cap of 2, on a **background `URLSession`** so an
  upload survives the app being suspended, driving a **Live Activity** on iOS
  showing per-file progress.
- Uploaded media is not public until a post attaches it and that post is public
  or unlisted — the server decides this, and the composer must not imply the
  file is already shared.
- Note the server's mime sniffing runs **after** the declared-type check, so a
  file that lies about its type is refused at upload with a 422. Surface it as
  "That file isn't the type it claims to be."

### Adjustments

The seven Nextcloud offers, with the same names and the same numbers as
its `imageFilters.js`: Original, Mono, Noir, Warm, Cool, Vivid, Faded, Sepia.
Deliberately mild — a filter that cannot be undone after upload should not be
the kind that ruins a photograph.

The preview is a shader over the thumbnail already on screen, so flicking
through the row costs nothing; only Save redraws the pixels, through Core Image.
JPEG stays JPEG and PNG stays PNG, so a screenshot does not gain a black
background where its alpha was; a HEIC or TIFF comes back as HEIC, or JPEG on a
server without HEIC; all at quality 0.92 and with their orientation; GIF and animated WebP are left alone,
since they would come back as their first frame. Never throws: a filter is a
decoration, and losing somebody's upload because Core Image would not cooperate
is not a trade worth making.

The picture as it was chosen is kept **on disk**, not in memory — ten at this
server's ceiling is a hundred megabytes — so a second filter is applied to the
original rather than stacked on the first. Baking one in is a second upload,
because no route replaces the bytes behind a media id; the description is
carried across and the old attachment is simply dropped for the server's own
media sweep to collect.

### Alt text

- Every attachment shows an **ALT** badge: in the accent when a description
  exists, in the destructive colour when it does not, and muted with a
  sparkle when only a generated **suggestion** is waiting for review.
- A setting, **on by default** ("Warn about missing descriptions"), nudges
  once before posting when any attachment lacks a description. The nudge
  offers to add one (opening the first undescribed attachment), to have this
  device suggest them where on-device description is available
  ([10-ai-features.md](10-ai-features.md) §4), and "Post anyway", always one
  tap. It nudges **once per post**: Post pressed again goes out as it is. It
  warns; it never blocks.
- The one exception to "once": while a suggestion is waiting for review, Post
  asks again — with the setting off too — offering "Review suggestions"
  instead of "Add a description". The person asked for those descriptions,
  and posting would silently leave them behind. "Post anyway" is still one
  tap, and posts without them.
- Statistics shows the share of the account's pictures that carry a
  description, near the top of the page. It is the server's own count
  (`media.images` and `media.described` in `GET /api/v1/statistics`, per
  picture over the chosen window). A server that does not send it gets a
  count made on the device from the account's latest forty posts with media,
  and the card says so.
- Editing an alt text after upload uses `PUT /api/v1/media/{id}`.
- Alt text travels as the ActivityPub `name`, both directions — so what is
  written here is what a remote reader gets.
- The AI alt-text generator ([10-ai-features.md](10-ai-features.md) §4)
  writes **suggestions**, never descriptions: each waits in the editor,
  marked as generated, for Accept, Edit or Discard, and nothing generated is
  sent to the server until it is accepted.

### Video and short video

- **Record** from the composer: standard camera for landscape/long video, and a
  dedicated **vertical capture** mode for shorts (portrait-locked, 15/30/60 s
  presets, a hold-to-record button, tap-to-flip).
- **Trim** before upload with an `AVPlayer`-backed scrubber and handle pair,
  exported with `AVAssetExportSession` at a preset chosen from the file size
  ceiling. A video that cannot be brought under the ceiling is refused with the
  ceiling stated.
- Optional client-side downscale presets (Original / 1080p / 720p) shown with
  their resulting file size before upload.
- A short posted from vertical capture gets `#shorts` appended only if the
  person opts in, once, with a remembered choice — never silently.

### Now playing

"Share what's playing" (iPhone, iPad, Vision Pro) inserts the song playing in
Apple Music — "Listening to <title> by <artist>" and its music.apple.com link
— read from `SystemMusicPlayer.shared.queue.currentEntry` after the person
allows Apple Music access once. A song from their own library has no
catalog link, and is found in the catalog by title and artist. The Mac has
no system player MusicKit can read, so it has no such action.

In timelines a card whose link is an Apple Music song (`/song/…/<id>`, or
`/album/…?i=<id>`) becomes a song card: artwork, title, artist, and a button
that plays Apple's 30-second preview (`previewAssets`), holding the app's
audio session as a track in Audio mode does. It needs the MusicKit service
on the App ID (Supporting/README.md); until then, or when Apple Music access
is turned off in Settings, the card stays the ordinary link card.

## 5. Polls, threads, drafts, scheduling

- **Polls**: 2 to `configuration.polls.max_options` options,
  `max_characters_per_option` enforced, multiple choice toggle, hide-totals
  toggle, expiry picker bounded by `min_expiration`/`max_expiration`.
  A poll and media are mutually exclusive, as Mastodon requires.
- **Threads**: a segmented composer. Each segment is its own text area with its
  own media, CW and poll. Posting chains them: the first `POST /api/v1/statuses`
  returns an id, each subsequent post sends `in_reply_to_id` of the previous.
  A failure mid-thread stops, keeps what posted, and offers Retry from the
  failed segment — it must never post a duplicate. Optional auto-numbering
  ("1/5") appended at post time, off by default.
- **Drafts**: `DraftRecord` in SwiftData, autosaved every 2 s of inactivity and
  on dismissal. A dismissed non-empty composer offers Save Draft / Discard /
  Keep Editing. Drafts list is reachable from the composer and from Settings.
  Drafts carry their media as **local file references plus any already-uploaded
  `media_id`s** — re-opening a draft does not re-upload what is already on the
  server unless the id has expired. Where the account's Nextcloud is
  connected, drafts also sync through it, one JSON file per draft in
  `Aloha Social/Drafts/`; the merge rules are in
  [14-open-questions.md](14-open-questions.md) §7.
- **Scheduled posts**: `POST /api/v1/statuses` accepts `scheduled_at` at least
  five minutes ahead, and answers 422 for anything sooner or malformed
  (`ScheduledStatusService::requestedTime`); a cron publishes them. A date picker with a minimum of
  +5 minutes. Scheduled posts are managed from a list backed by
  `GET/PUT/DELETE /api/v1/scheduled_statuses` — note this route sends **no
  `Link` header**, so it is fetched whole and not paged.
- **Idempotency**: every `POST /api/v1/statuses` carries an
  `Idempotency-Key` header holding a UUID generated when the composer opened
  and regenerated only when content changes. This is what makes retry-on-timeout
  safe, and it is not optional.

## 6. Attach from Nextcloud Files

Where `capabilities.mediaFromNextcloudFiles`.

`POST /api/v1/media/from-file` with `path` relative to the person's own user
folder and `description`. The bytes are copied server-side, so a picture already
on the Nextcloud never travels to the phone and back — on a 200 MB video over a
mobile connection this is the difference between possible and not.

- Where the person has connected their Nextcloud (Settings → Nextcloud, which
  runs Login Flow v2 and grants an app password), the picker is a real WebDAV
  browser over `/remote.php/dav/files/{loginName}/`: folders, thumbnails from
  Nextcloud's own preview endpoint, and only the file types this server's
  `supported_mime_types` accepts. A file over the server's size ceiling for
  its type is shown but marked and not pickable. The browser opens in the
  folder the last attachment came from, falling back to the top when that
  folder has gone, and it browses the Files of the account the composer
  posts as, not of whichever account happens to be active. See
  [14-open-questions.md](14-open-questions.md) §7.
- Without that connection it degrades to a path field with recent paths, which
  still works because the server resolves the path itself.
- A traversal, a folder, or a missing file is a 422 — surfaced as "That file
  isn't in your Nextcloud files".
- The same MIME filter, size ceiling and resizing apply as to an upload.

## 7. Offline and failure

- Posting offline queues the status in `DraftRecord` with `queuedForSend = true`
  and a visible "Will post when you're back online" state.
- The send queue drains on connectivity return, in order, one at a time, with
  the stored idempotency key.
- A queued post can be edited or cancelled before it sends.
- A send that fails with 422 surfaces the server's message and reopens the
  composer with everything intact.
- A send that fails with 401 pauses the queue for that account and prompts
  re-authentication rather than discarding anything.

## 8. Editing

- `PUT /api/v1/statuses/{id}` with the same fields, plus `media_attributes` for
  alt-text-only changes.
- The composer in edit mode fetches `/api/v1/statuses/{id}/source` for the
  original plain text and spoiler — never the rendered HTML.
- Editing shows a note that followers will see the post was edited, and the
  edit appears in `/history`.
- **Delete & Redraft** is a distinct action: it fetches `/source`, opens a fresh
  composer prefilled, and deletes the original only after the new one posts
  successfully.
