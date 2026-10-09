# 08 — Notifications and sync

## 1. The constraint

Nextcloud Social serves **no streaming API** and **no Web Push**. It says so
explicitly rather than leaving a client to time out: `instance.urls` is an empty
object, and `vapid_key` is an empty string. Both are deliberate signals meaning
"do not wait for a socket, do not offer push".

So the baseline is **polling**, and the app is designed around polling being the
normal case rather than a degraded one. Where a server *does* advertise
streaming or a VAPID key — real Mastodon today, Nextcloud Social later — the app
upgrades automatically.

## 2. Three tiers

```
                 ┌──────────────────────────────────────┐
  best           │ Nextcloud push proxy (connected)     │  → APNs via Nextcloud's own proxy
                 ├──────────────────────────────────────┤
  best           │ Web Push  (vapid_key non-empty)      │  → APNs, instant, no battery cost
                 ├──────────────────────────────────────┤
  better         │ Streaming (urls.streaming_api set)   │  → WebSocket while foregrounded
                 ├──────────────────────────────────────┤
  baseline       │ Polling   (always)                   │  → adaptive foreground + BGAppRefresh
                 └──────────────────────────────────────┘
```

Tier selection is per account, from `ServerCapabilities`, re-evaluated when
capabilities refresh. **Social announcing no Web Push does not settle it**: the
Nextcloud underneath has the notifications app and a push proxy, and connecting
it is a real push path — see [14-open-questions.md](14-open-questions.md) §7. Tiers compose: streaming handles the foreground, polling
still runs in the background where there is no Web Push.

## 3. Polling

`SyncEngine` is an actor owning one `PollScheduler` per signed-in account.

### Intervals

| State | Active account | Other accounts |
|---|---|---|
| Foreground, screen on, user interacting | 30 s | 180 s |
| Foreground, idle > 2 min | 60 s | 300 s |
| Foreground, idle > 10 min | 120 s | 600 s |
| Low Power Mode | ×2 all intervals | ×2 |
| Cellular + "Wi-Fi only sync" enabled | notifications only | notifications only |
| Background | `BGAppRefreshTask`, system-scheduled | same task |

Intervals are user-adjustable in Settings (Frequent / Normal / Battery Saver /
Manual), with Normal as the table above.

### What is polled

Per tick, in priority order, with a total budget of 3 requests per account:

1. `GET /api/v2/notifications/unread_count` (or v1) — cheapest, drives the badge.
2. `GET /api/v1/timelines/home?min_id={newestCachedID}&limit=40` — only when the
   Home mode is visible or was visible in the last 5 minutes.
3. `GET /api/v2/notifications?min_id={newestCachedID}&limit=40` — only when
   step 1 reported a change.

The currently-visible timeline (whichever mode) is polled instead of Home when
it differs. No other timeline is polled; they refresh on appear.

### Backoff and etiquette

- Exponential backoff with full jitter on any failure, capped at 15 minutes.
- On 429, honour `Retry-After`; absent it, back off and halve the frequency for
  an hour.
- A per-host token bucket shared across accounts on the same host, so five
  accounts on one small instance behave like one.
- All polling stops for an account in `needsReauthentication`.
- All polling stops when the device reports `NWPath` unsatisfied and resumes on
  the path update, not on a timer.

## 4. Background refresh

- One `BGAppRefreshTaskRequest` with identifier
  `com.nextcloud.alohasocial.refresh`, `earliestBeginDate` = now + the
  configured interval, re-submitted at the end of every run.
- The handler has a hard 25-second budget and sets an expiration handler that
  cancels in-flight work and saves what it has.
- It polls notifications for every account, posts local notifications for what
  is new (§5), updates widget timelines via `WidgetCenter.reloadAllTimelines()`,
  and updates the app badge.
- It does **not** fetch timelines — a background refresh exists to tell somebody
  something happened, not to warm a cache.
- A `BGProcessingTaskRequest` (`…​.maintenance`) runs cache sweeping and image
  cache eviction, requiring external power and no network.

## 5. Local notifications

Because the server cannot push, the app raises its own from what polling finds.

- Notification categories: `mention`, `reply`, `favourite`, `reblog`, `follow`,
  `follow_request`, `poll`, `status`, `update`, `moderation_warning`,
  `severed_relationships`. Each individually toggleable per account.
- Content: author's display name and avatar (via
  `UNNotificationAttachment` from the image cache), the status text truncated,
  and the account's handle in the subtitle when more than one account is
  signed in.
- Thread identifier per conversation so replies group in Notification Centre.
- `interruptionLevel`: `.active` for mentions and DMs, `.passive` for
  favourites, boosts and follows.
- Notification actions: Reply (text input), Favourite, Boost, Open.
- **Deduplicate ruthlessly.** A notification is raised at most once per
  `serverID`; the raised set is persisted. Grouped (v2) notifications raise one
  local notification per group and update it in place as the group grows, using
  the same request identifier.
- **Quiet hours**: a user-set window during which nothing is raised and the
  badge still updates.
- The badge is the unread **group** count where v2 is available, capped at 99 by
  the server.

## 6. The upgrade paths

### Streaming

When `capabilities.streamingURL != nil`:

- Open a `URLSessionWebSocketTask` to `{streaming}?access_token=…&stream=user`
  while the app is foregrounded and the account is active.
- Handle `update`, `delete`, `notification`, `status.update`, `filters_changed`.
- Reduce the poll interval for that account to 5 minutes as a safety net; do not
  stop it entirely, because a socket can be silently dead.
- Reconnect with exponential backoff and a hard stop after 5 failures, falling
  back to polling and logging the reason.
- Close the socket on background, immediately.

### Web Push

When `capabilities.webPushVAPIDKey != nil`:

- Register for remote notifications, generate a P-256 key pair and an auth
  secret, and `POST /api/v1/push/subscription` with the endpoint, keys and the
  per-type `data[alerts][…]` preferences.
- Decrypt incoming payloads per RFC 8291 in a **notification service
  extension**, so the notification carries real content rather than "New
  activity".
- Disable the corresponding local-notification raising for that account so
  nothing is shown twice.
- Unsubscribe on sign-out.
- **This path is written but dormant for Nextcloud Social.** Do not delete it
  and do not let it bit-rot: it is what makes the app correct the day the server
  gains push, and it is what makes the app good on mastodon.social today.

## 7. Markers and read state

- `GET /api/v1/markers?timeline[]=home&timeline[]=notifications` on launch and
  on foreground.
- `POST /api/v1/markers` when the person scrolls past unread content, debounced
  to at most once per 10 seconds and once on background.
- **A marker never moves backwards.** The server enforces it; the client must
  too, so a phone that is behind cannot un-read what an iPad has read.
- The marker is what drives the "N new posts" pill, the unread dot in the
  sidebar, and the badge.
- **Home timeline "You're caught up" divider** — on launch the home marker
  (`home.last_read_id`) is read from the local store. If that post is in the
  current timeline, a divider is inserted below it with the text "You're caught
  up". When the reader scrolls past the divider (the first post below it
  appears), the marker advances to that post locally and is synced to the
  server. The notifications timeline has an identical divider driven by the
  `notifications` marker (flat list only for now).

## 8. Notification digests

- **Per-account delivery mode**: "As they arrive" (immediate, default) or
  "In a digest" at 1–4 configured hours (local time, minutes always zero).
- **Digest times** are managed with add/remove steppers; up to 4 times.
- **Quiet hours** (existing `quietHoursStart`/`End` fields, now exposed in
  Settings) win over digest times: a digest time that falls within quiet hours
  is skipped, and the badge updates at the next digest time.
- **Direct messages and mentions from followed accounts** always break through
  immediately, even in digest mode.
- **LocalNotifier** schedules notifications at the next digest time using
  `UNCalendarNotificationTrigger`; quiet hours are skipped (the next digest
  time outside quiet hours is used). If all digest times fall in quiet hours,
  the notification is delivered immediately.
- The in-app Notifications list is unaffected — it stays real-time.

## 9. Sync correctness rules

1. **Never insert a status into a timeline without an anchor.** Every fetch is
   either `min_id` from the newest cached entry, `max_id` from the oldest, or a
   cold load. Anything else risks an invisible gap.
2. **A full page from a `min_id` fetch means there may be more** — insert a gap
   marker rather than joining.
3. **Deletions** (`delete` over streaming, or a 404 on refetch) remove the
   `StatusRecord` and every `TimelineEntry` pointing at it.
4. **Edits** replace the `StatusRecord` in place, keeping timeline positions, and
   mark it edited.
5. **Optimistic local actions** (favourite, boost, bookmark, follow) write
   immediately, carry a pending flag, and are reconciled against the server's
   response. A failure reverts and explains.
6. **One refresh in flight per timeline key.** A second request coalesces onto
   the first.
