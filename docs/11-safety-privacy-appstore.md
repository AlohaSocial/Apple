# 11 — Safety, privacy and App Store requirements

Distribution: **App Store on all six platforms, plus a public MIT repository
from day one.** Both constrain the build; this document is the checklist.

## 1. User-generated content requirements

App Review's UGC rules (Guideline 1.2) require all four of these, and a
fediverse client shows content from anyone on any server, so they are not
optional.

### 1.1 Filtering objectionable material

- Server-side v2 filters, fully manageable in-app: create, edit, delete,
  keywords, contexts (home, notifications, public, thread, account), action
  (`warn` / `hide`), expiry.
- Client-side application of the same filters, so a filter takes effect
  immediately over cached content. See [04-data-model.md](04-data-model.md) §6.
- Sensitive media honours the account's `reading:expand:media` policy, including
  `hide_all` which does not draw the media at all.
- Content warnings collapse body and media together.
- A "Hide everything from accounts I don't follow in public timelines" local
  option.

### 1.2 Reporting

- **Report** is present on every status, every profile, and inside the media
  viewer. Never more than two taps away.
- `POST /api/v1/reports` with `account_id`, `status_ids`, `comment`,
  `forward` (to the remote instance), `category`
  (`spam` / `legal` / `violation` / `other`) and `rule_ids` where the instance
  publishes rules (`/api/v1/instance/rules`).
- The report sheet shows the instance's rules as selectable reasons when it has
  them, and a free-text field.
- After reporting, offer Block and Mute in the same sheet — the three decisions
  belong together.
- A confirmation states what happens next: the report goes to this instance's
  moderators, and optionally to the author's instance.

### 1.3 Blocking abusive users

- **Block** on every profile, status menu, and in the report flow.
- **Mute** with duration (indefinite / 1 day / 7 days / 30 days) and an
  "also hide their notifications" option.
- **Block domain** from any profile and from Settings.
- Management screens for all three: `GET /api/v1/blocks`, `/api/v1/mutes`,
  `/api/v1/domain_blocks`. Note blocks and mutes **take no cursor and send no
  `Link` header** — they page by `limit` alone (default 40) and are fetched in
  a bounded loop.
- Blocked and muted content disappears from every mode immediately, from cache,
  without waiting for a refresh.

### 1.4 A way to contact the developer

- Settings → About → Contact, with an email address and a link to the repository's
  issue tracker. Present on every platform including tvOS and watchOS (the watch
  points at the phone).

### 1.5 Terms of use

- First launch, before any content is shown, presents a short EULA covering
  zero tolerance for objectionable content and abusive users, with Accept /
  Decline. Declining exits onboarding.
- The accepted version and date are stored; a changed version re-prompts.
- Linked from Settings → About thereafter.
- The instance's own rules (`/api/v1/instance/rules`), privacy policy
  (`/instance/privacy_policy`) and terms (`/instance/terms_of_service`) are
  shown at sign-in and linked from account settings. **Both of the latter 404
  where the administrator has published none** — the row is hidden in that case,
  never shown broken.

## 2. Account deletion path

Required by Guideline 5.1.1(v) for any app with account creation — and while
this app creates no accounts, it must still offer a clear path:

- Settings → Account → "Sign out and remove from this device" removes
  everything local (token revoked, Keychain entry, all rows, all cached media,
  drafts, Spotlight entries, widget data).
- Settings → "Delete my Social account" deletes it **in the app** on Nextcloud
  Social, which serves `POST /api/v1/account/delete`: the posts go, the follows
  go, and a `Delete` goes out to every server that knew the account. The
  Nextcloud account is untouched. Typing the handle is the confirmation and is
  deliberately not a password — an account signed in through SSO has none to
  give, and asking for one would make this an administrator's job again for
  exactly the installations that federate most.
  - The route is `#[NoAdminRequired]`, meaning a Nextcloud session rather than a
    bearer token, so it goes out with the Nextcloud **app password** as HTTP
    Basic (`Endpoint.Authentication.nextcloudSession`). Without a connected
    Nextcloud the screen says so instead of offering a button that 401s.
- Everywhere else the account belongs to the server and there is no route for
  it, so the row links out to the instance's own settings with a sentence
  explaining why.

## 3. Privacy

### Privacy manifest (`PrivacyInfo.xcprivacy`)

Required in the app and in every extension.

| Key | Value |
|---|---|
| `NSPrivacyTracking` | `false` |
| `NSPrivacyTrackingDomains` | `[]` |
| `NSPrivacyCollectedDataTypes` | `[]` — the app collects nothing |
| `NSPrivacyAccessedAPITypes` | `UserDefaults` (`CA92.1`), `FileTimestamp` (`C617.1`), `DiskSpace` (`E174.1`), `SystemBootTime` (`35F9.1`) — each with its declared reason |

There is no analytics SDK, no crash reporter that phones home, no telemetry of
any kind. Crash reports reach the developer only through Apple's own opt-in
sharing.

### Nutrition label

"Data Not Collected" across the board. This is only true if it stays true —
any future addition of analytics requires changing this document first.

### Usage descriptions

| Key | String |
|---|---|
| `NSCameraUsageDescription` | "Aloha Social uses the camera when you take a photo or record a video to post." |
| `NSMicrophoneUsageDescription` | "Aloha Social uses the microphone when you record a video to post." |
| `NSPhotoLibraryUsageDescription` | "Aloha Social reads photos and videos you choose to attach to a post." |
| `NSPhotoLibraryAddUsageDescription` | "Aloha Social saves images and videos to your photo library when you ask it to." |
| `NSUserTrackingUsageDescription` | **Absent.** The app does not request tracking. |

### Network security

- ATS left at its defaults. No exceptions, no arbitrary loads. An instance
  without HTTPS cannot be added, and the sign-in screen says so plainly.
- No third-party analytics, ad, or attribution network can be added without
  amending this document.
- Media is loaded from the instance's own host (and, for federated video, from
  the instance's proxy routes — never from the origin). This matters: it is
  why reading a post does not announce the reader to a server they never chose
  to talk to.
- Remote avatars and header images **are** loaded from their origin hosts,
  because Mastodon servers cache them and Nextcloud Social serves cached copies
  via `/document/get`. Prefer the local cache URL when the entity offers one.

## 4. Age rating

- Rated **17+** / "Frequent/Intense Mature or Suggestive Themes" and
  "Unrestricted Web Access", as every fediverse client must be: the app shows
  content from arbitrary servers.
- The App Store description states plainly that content comes from servers the
  app does not control.

## 5. Export compliance

- Uses only standard HTTPS/TLS and the platform Keychain. No custom
  cryptography.
- `ITSAppUsesNonExemptEncryption = false` in Info.plist, with the exemption
  claimed on the standard grounds.

## 6. Open-source repository requirements

- MIT `LICENSE` at the root, and an SPDX header comment (`// SPDX-License-Identifier: MIT`)
  at the top of every source file.
- **No secrets in the repository.** There are none to hold: OAuth clients are
  registered at runtime per instance via `POST /api/v1/apps`, so there is no
  app-wide client id or secret to leak. This is worth stating explicitly in the
  README, because it is unusual and good.
- A `CONTRIBUTING.md` covering build requirements (Xcode 27, Swift 6.4), the
  dependency policy, and the test/accessibility bar.
- A `CODE_OF_CONDUCT.md`.
- Build must succeed from a clean clone with no configuration beyond a signing
  team: no API keys, no `.xcconfig` the repository does not carry, no manual
  steps.
- The App Store build and the repository build are the same code. Any
  App-Store-only configuration is a build setting, documented in
  `CONTRIBUTING.md`.
- Third-party asset licences (SF Symbols are Apple's and may not be redrawn;
  any custom icon must be original work) recorded in `ACKNOWLEDGEMENTS.md`.

## 7. Moderation

A moderator surface, over Mastodon's `/api/v1/admin/*`, which Nextcloud Social
serves from `AdminApiController`. The server's own `/moderation/*` routes need a
Nextcloud session **and** a CSRF token, which no API client has and none can
obtain — so before this a moderator could act from a browser and from nowhere
else.

- **Reports.** The unresolved queue and the handled one; one report shows who
  reported, who was reported, the posts, and the moderator's note. Take it,
  hand it back, resolve, reopen.
- **Accounts.** Filtered by origin and standing, searched by username.
  Silence, suspend, lift either, and stop forcing warnings on their media.
  A decision taken from a report resolves that report in the same call
  (`report_id`), because two calls could disagree.
- **Trends.** Hashtags, posts and links, with approve and reject. Rejecting
  hides; approving grants nothing — everything nobody has objected to trends
  already, which is the server's own arrangement, and the screen says so rather
  than implying a queue that does not exist.

Every route is gated on the caller being a **Nextcloud administrator**, checked
by the server on each one, whatever scope the token carries. A 403 hides the
whole section rather than showing empty lists to everybody else.

### Still deliberately excluded

- No local "AI content warning" or automated content classification.
- No client-side blocklist subscriptions.
- No instance configuration: storage, retention, relays, email and IP blocks,
  domain allow lists, setup checks ([00-overview.md](00-overview.md) §6).
