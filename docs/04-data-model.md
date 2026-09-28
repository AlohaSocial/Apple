# 04 — Data model

## 1. Two layers

**Wire types** (`AlohaModels`) are `Codable` structs mirroring the server's
entities exactly. They are `Sendable`, immutable, and never stored.

**Persisted models** (`AlohaStore`) are SwiftData `@Model` classes. They are
derived from wire types, carry an `accountID`, and hold only what the app needs
to render offline and to page.

Views bind to persisted models. The network layer produces wire types.
Repositories convert between them. Nothing else does.

## 2. Decoding rules

These are load-bearing. Nextcloud Social is a partial implementation and other
servers are forks of forks; a strict decoder will fail on real data.

1. **A malformed entity must never fail its page.** Arrays of entities decode
   element-by-element through a `LossyArray<T>` wrapper that collects successes
   and reports failures to the logger. A timeline page with one bad status shows
   nineteen.
2. **Every optional in Mastodon's documentation is optional here**, plus:
   - `Account.avatar` may be `""` on Nextcloud Social (a known defect:
     `Person::exportAsLocal()` falls through to a possibly-empty stored value).
     Decode avatar and header as `String`, and treat empty as "no image" rather
     than failing the whole account.
   - `Status.poll` is present-or-null on Nextcloud Social but may be absent on
     other servers.
   - `MediaAttachment.meta` is an object, never a list, on Nextcloud Social —
     but decode defensively against servers that send `[]`.
   - `Instance.urls`, `.stats`, `.configuration` are objects, never `[]`, on
     Nextcloud Social. Other servers are less careful.
3. **Unknown enum cases decode to a `.unknown(String)` case**, never throw.
   This applies to `Visibility`, `NotificationKind`, `AttachmentKind`,
   `FilterAction`, `FilterContext`. A notification kind the app does not know
   renders as a generic row with the account and a timestamp; it never crashes
   and never disappears silently without a log line.
4. **Ids are `String`**, always, everywhere, even where a server sends numbers.
   A custom decoder accepts both. Nextcloud Social uses numeric `nid`s; Mastodon
   uses snowflake strings. Never parse an id as an integer for ordering.
5. **Dates** are ISO 8601 with fractional seconds optional. One shared
   `JSONDecoder.dateDecodingStrategy` handles both forms plus Unix seconds
   (`/api/v1/instance/activity` keys weeks by unix time as strings).
6. **HTML is not decoded at decode time.** `Status.content` stays a `String`.
   Parsing happens lazily, off the main actor, cached by content hash.

## 3. SwiftData schema

One `ModelContainer`, stored in the app group container so the share extension
and widgets read the same data. `ModelConfiguration` with
`cloudKitDatabase: .none` — nothing syncs in 1.0.

```swift
@Model final class AccountRecord {
    #Unique<AccountRecord>([\.id])
    var id: UUID                     // client-generated, stable
    var instanceHost: String
    var apiBase: URL
    var handle: String               // alice@cloud.example
    var displayName: String
    var avatarURL: URL?
    var headerURL: URL?
    var serverAccountID: String      // the server's id for this account
    var capabilitiesData: Data       // encoded ServerCapabilities
    var needsReauthentication: Bool
    var sortIndex: Int
    var addedAt: Date
    var settingsData: Data           // encoded AccountSettings
    @Relationship(deleteRule: .cascade) var timelineEntries: [TimelineEntry]
    @Relationship(deleteRule: .cascade) var notifications: [NotificationRecord]
    @Relationship(deleteRule: .cascade) var drafts: [DraftRecord]
    @Relationship(deleteRule: .cascade) var markers: [MarkerRecord]
}

@Model final class StatusRecord {
    #Unique<StatusRecord>([\.accountID, \.serverID])
    #Index<StatusRecord>([\.accountID, \.createdAt], [\.accountID, \.serverID])
    var accountID: UUID
    var serverID: String
    var uri: String
    var url: URL?
    var createdAt: Date
    var editedAt: Date?
    var content: String              // raw HTML
    var plainText: String            // derived, for search and AI
    var spoilerText: String
    var visibilityRaw: String
    var sensitive: Bool
    var language: String?
    var repliesCount, reblogsCount, favouritesCount: Int
    var favourited, reblogged, bookmarked, pinned, muted: Bool
    var inReplyToID: String?
    var inReplyToAccountID: String?
    var reblogOfID: String?          // points at another StatusRecord.serverID
    var authorData: Data             // encoded Account entity
    var attachmentsData: Data        // encoded [MediaAttachment]
    var mentionsData, tagsData, emojisData, cardData, pollData: Data?
    var reactionsData: Data?         // Nextcloud emoji reactions
    var quoteOfID: String?
    // Derived classification, computed once on insert — see 06 §4
    var contentKindRaw: String       // text | photo | video | short | audio | news
    var primaryMediaAspect: Double?
    var primaryMediaDuration: Double?
    var cachedAt: Date
}

@Model final class TimelineEntry {
    #Unique<TimelineEntry>([\.accountID, \.timelineKey, \.statusServerID])
    #Index<TimelineEntry>([\.accountID, \.timelineKey, \.position])
    var accountID: UUID
    var timelineKey: String          // "home", "public:local", "tag:swift", "list:3", "mode:video", …
    var statusServerID: String
    var position: Int64              // monotonically decreasing insertion order
    var insertedAt: Date
    var isGapMarker: Bool            // a hole between two fetched ranges
}

@Model final class NotificationRecord {
    #Unique<NotificationRecord>([\.accountID, \.serverID])
    var accountID: UUID
    var serverID: String             // v1 id, or v2 group_key
    var isGroup: Bool
    var kindRaw: String
    var createdAt: Date
    var groupCount: Int
    var sampleAccountsData: Data
    var statusServerID: String?
    var dismissed: Bool
    var seen: Bool
}

@Model final class DraftRecord { … }          // see 07 §7
@Model final class MarkerRecord { … }         // home / notifications last_read_id
@Model final class WatchPositionRecord { … }  // see 06 §3
@Model final class StoryRecord { … }          // see 06 §6, TTL ≤ 24 h
@Model final class RelationshipRecord { … }   // cached follow/block/mute state
@Model final class FilterRecord { … }         // v2 filters, applied client-side too
@Model final class InstanceRecord { … }       // per-host instance entity + rules
@Model final class SearchHistoryRecord { … }
```

### Why `TimelineEntry` is separate from `StatusRecord`

A status appears in several timelines and must be stored once. Ordering is
per-timeline. Deleting a timeline's cache must not delete statuses another
timeline still shows. `position` is assigned from a per-timeline descending
counter rather than from `createdAt`, because boosts sort by boost time and the
server's order is authoritative.

### Gap handling

When a refresh returns a full page (`limit` rows) and the newest cached entry is
older than the oldest row returned, a `TimelineEntry` with `isGapMarker = true`
is inserted between them. The UI renders it as a "Load more" row. Tapping it
pages `max_id`/`min_id` inward until the gap closes. **Never silently join two
disjoint ranges** — that produces a timeline with invisible holes, which is the
single most common bug in clients of this kind.

## 4. Cache policy

| Data | Retention |
|---|---|
| Home timeline entries | newest 500 per account |
| Other timelines / modes | newest 200 per timeline key |
| Statuses | kept while referenced by any `TimelineEntry`, thread cache, or bookmark; orphans swept after 7 days |
| Notifications | newest 500 per account |
| Relationships | 24 h |
| Instance entity + rules | 24 h |
| Custom emojis | 24 h |
| Stories | until `expires_at`, hard ceiling 24 h from insert |
| Drafts | forever, until sent or deleted |
| Watch positions | mirrored from the server; local copy 30 days |
| Images on disk | LRU, 512 MB default ceiling |
| Video segments | `URLCache`, 1 GB ceiling, purged on low disk |

Sweeping runs on a background `ModelActor` at launch and after each successful
full refresh, never on the main actor, and is budgeted (max 2000 deletions per
pass) so it cannot stall a launch.

Settings offer "Clear cache" (media only) and "Clear all cached content"
(everything except accounts and drafts), both with a size readout.

## 5. Migrations

- `VersionedSchema` per release, `SchemaMigrationPlan` with explicit stages.
  Lightweight migrations only for additive changes.
- Encoded `Data` blobs (`authorData`, `attachmentsData`, …) are versioned
  independently: each carries a one-byte version prefix. A blob whose version
  the app does not understand is discarded and refetched, never crashed on.
- **The cache is disposable.** Any migration that cannot be done cleanly drops
  every cached timeline, status and notification and refetches. It must never
  drop accounts, drafts, or settings. Write the destructive path first and test
  it — it is the safety net for everything else.

## 6. Client-side filtering

Server-side v2 filters are authoritative, but the app also applies them locally
so that cached content stays consistent after a filter changes and before the
next refresh:

- `FilterRecord` holds each filter's keywords, contexts, action (`warn` /
  `hide`), and expiry.
- Applied at render time in the timeline data source, not at insert time — a
  filter that expires must stop hiding without a refetch.
- `hide` removes the row. `warn` collapses it behind the filter's title with a
  "Show anyway" control.
- Expired filters are ignored and swept.

## 7. What is never persisted

Tokens, client secrets, code verifiers, the contents of the composer before it
is saved as a draft, AI prompt inputs or outputs, search queries beyond the
explicit search history, and any analytics of any kind — there are none.
