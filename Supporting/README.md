# Supporting files

## One Mac app

The Mac is `AlohaSocialMac` (`social.aloha.app.mac`) and nothing else. The
`AlohaSocial` target builds for iPhone, iPad and Vision only: it used to list
`macosx` too, which made it a second, native Mac app with its own bundle,
store and Keychain and none of the Mac app's menu bar, window or notification
wiring. "Designed for iPad" on Apple silicon Macs is off for the same reason
(`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO`): the store should offer the
Mac app, not the iPad one, to Mac users.

The UI tests follow: on macOS they drive `AlohaSocialMac`
(`TEST_TARGET_NAME[sdk=macosx*]`), elsewhere `AlohaSocial`.

Because the Mac app has its own bundle id, it is a separate App Store record.
Universal purchase (one record, one purchase across iPhone and Mac) would need
the Mac app to share `social.aloha.app`, and its widgets and share extension
to move under that id — a decision for App Store Connect, not for this file.

## App group and Keychain sharing

One build setting decides whether the app and its extensions share anything:
`ALOHA_SHARED_CONTAINER`, set in [`Aloha.xcconfig`](Aloha.xcconfig), which
the project's Debug and Release configurations are based on.

- **`NO` (the default for Debug): every target is standalone.** No
  `application-groups` or `keychain-access-groups` entitlement anywhere, and
  `AlohaAppGroupEnabled` / `AlohaKeychainSharingEnabled` off in every
  Info.plist. Any Apple ID — a free one included — can sign any target, and
  CI builds with `CODE_SIGNING_ALLOWED=NO` need no profile. Each process keeps
  its store and tokens in its own container, so **widgets, the share sheet,
  the notification service and complications see no accounts**.
- **`YES` (the default for Release): every target shares**
  `group.social.aloha.app` and the keychain group
  `$(AppIdentifierPrefix)social.aloha.app`, and its Info.plist says so.
  Release is what gets archived for TestFlight and the App Store, so a
  shipped build has working widgets and share sheet without anyone
  remembering a switch; only a team that owns the group can sign it anyway.

To turn sharing on for Debug as well — on a team that owns the group —
create `Supporting/Local.xcconfig` (git-ignored, included by `Aloha.xcconfig`
when it exists, and winning over it for both configurations) containing

    ALOHA_SHARED_CONTAINER = YES

(`= NO` there makes Release standalone too, for archiving under another team)

or pass `ALOHA_SHARED_CONTAINER=YES` to `xcodebuild`. Nothing else changes by
hand. The setting drives two things, so they cannot disagree:

- `CODE_SIGN_ENTITLEMENTS` names `<Target>$(ALOHA_ENTITLEMENTS_SUFFIX).entitlements`:
  the plain file when off, the `-Shared` one beside it when on. The two files
  of a pair differ only by the two groups; keep them in step.
- Each Info.plist writes `$(ALOHA_SHARED_CONTAINER)` into both keys, and
  `AppGroup` reads the string `YES` as on and anything else as off. Without
  the key, `AppGroup` stays on the process's own container rather than
  claiming one it was never granted.

| Target | Bundle id | Entitlements (`NO` / `YES`) | Sandbox |
|---|---|---|---|
| AlohaSocial (iPhone, iPad, Vision) | `social.aloha.app` | `AlohaSocial` / `AlohaSocial-Shared` | — |
| AlohaWidgets (iOS and Mac) | `social.aloha.app.widgets`, `social.aloha.app.mac.widgets` | `AlohaWidgets` / `AlohaWidgets-Shared` | ✓ + network client (Mac) |
| AlohaShareExtension (iOS) | `social.aloha.app.share` | `AlohaShareExtension` / `AlohaShareExtension-Shared` | — |
| AlohaShareExtension (Mac) | `social.aloha.app.mac.share` | `AlohaShareExtensionMac` / `AlohaShareExtensionMac-Shared` | ✓ + network client |
| AlohaNotificationService | `social.aloha.app.notificationservice` | `AlohaNotificationService` / `AlohaNotificationService-Shared` | — |
| AlohaSocialMac | `social.aloha.app.mac` | `AlohaSocialMac` / `AlohaSocialMac-Shared` | ✓ + network client, user-selected files |
| AlohaSocialWatch | `social.aloha.app.watch` | `AlohaSocialWatch` / `AlohaSocialWatch-Shared` | — |
| AlohaWatchWidgets (complications) | `social.aloha.app.watch.widgets` | `AlohaWatchWidgets` / `AlohaWatchWidgets-Shared` | — |

The iOS and Mac share extensions are one target with per-SDK entitlements and
one Info.plist; the iOS and Mac widgets are one target with one of each. Both
follow the switch like everything else, so the Mac is no longer half shared.

- App group: `group.social.aloha.app`, on every platform. Since macOS 15 an
  iOS-style `group.` identifier is valid on the Mac when the provisioning
  profile grants it, so the Mac does not need a team-prefixed variant.
- Keychain group: `$(AppIdentifierPrefix)social.aloha.app`. On the Mac the
  shared items live in the data protection keychain, the only one that honours
  an access group; items an older build left in the file-based keychain are
  moved over on first read.
- The watch's group and Keychain are the watch's own: the identifiers are the
  same strings, but nothing crosses to the phone except over
  `WatchConnectivity`. The watch app keeps the pairing in the shared Keychain
  group so its complications can read the token; a pairing an older build
  stored privately is moved over on first launch (`WatchPairingStore`).

With automatic signing and the switch on, building registers both
capabilities on each App ID (**App Groups** and **Keychain Sharing**, plus the
group itself) and puts them in the profiles. To check by hand: Certificates,
Identifiers & Profiles → Identifiers → each bundle id above → App Groups ✓
(with `group.social.aloha.app` assigned) and Keychain Sharing ✓.

**Signing with another team.** An app group belongs to the team that
registered it, so another team cannot claim `group.social.aloha.app` — and a
free Apple ID cannot use app groups or keychain sharing at all. Leave the
switch off and the build runs under any Apple ID once your team is in
`Supporting/Local.xcconfig`:

    DEVELOPMENT_TEAM = ABCDE12345
    ALOHA_APP_BUNDLE_IDENTIFIER = com.example.aloha

The second line only if `social.aloha.app` is registered to a team that is
not yours: an App ID belongs to one team, and every target's id is that
prefix plus its own suffix. The project itself names no team and no
personal id. **Don't pick a team in Signing & Capabilities** — Xcode writes
it into `project.pbxproj`, which is how one contributor's team and ids kept
replacing the last one's for everybody. To share under a team of
your own, register a group, change the string in the `-Shared` entitlements,
`AppGroup.identifier` and `StoreContainer.appGroupIdentifier`, and turn the
switch on.

**Switching changes where data lives.** A process reads the group's container
only while the switch is on. The first launch with it on moves what the app
kept in its own container into the group (below); turning it off again does
not move anything back, so the app starts from its own, older container. The Mac
app was shared before the switch existed; it still is in Release, and is
standalone in a Debug build unless the switch is turned on.

The first launch of a build with the group moves what the app kept in its own
container — the SwiftData store and the `aloha.*` defaults — into the group
once, so updating does not sign anybody out. The exception is
`AlohaSocialMac`, which ran without the sandbox before: its old store sat in
`~/Library/Application Support`, outside the sandbox it now has, and cannot be
reached to move. Its token in the file-based keychain usually still can be;
where it cannot, that Mac signs in once more.

## Push notifications

`aps-environment` is **deliberately not** in `AlohaSocial.entitlements`.

Adding it to a checked-in entitlements file breaks every build whose
provisioning profile lacks the Push Notifications capability — which is every
profile until somebody enables it on the App ID — and a build signed with an
entitlement its profile does not grant misbehaves at launch rather than failing
cleanly.

To turn push on:

1. Enable **Push Notifications** for `social.aloha.app` in the Apple
   Developer portal, and let Xcode regenerate the profile.
2. Add the capability in Xcode (Signing & Capabilities → + → Push
   Notifications), which writes `aps-environment` for you.

Until then the app runs normally and simply polls: `registerForNextcloudPush`
never receives a device token, and `AppDelegate` treats the registration
failure as a degradation rather than an error. Nothing else changes.

See [docs/14-open-questions.md](../docs/14-open-questions.md) §7 for the
Nextcloud proxy flow itself.

## MusicKit

"Share what's playing" in the composer and the song cards in timelines use
MusicKit. It needs no entitlement, so nothing here switches: the code asks
at runtime and degrades.

- Reading the song playing in Apple Music needs the person's permission,
  asked once with `NSAppleMusicUsageDescription` (in `Info.plist`; the Mac
  app's says what the catalog lookup is for). The Mac has no system player
  MusicKit can read, so it has no "Share what's playing".
- Looking a song up in the Apple Music catalog — a song card's artwork and
  30-second preview, and a link for a song from the person's own library —
  needs the **MusicKit** App Service on the App ID: Certificates,
  Identifiers & Profiles → Identifiers → `social.aloha.app` and
  `social.aloha.app.mac` → App Services → **MusicKit** ✓. MusicKit makes its
  developer token from that; there is no key to keep in the repository.
  Until it is enabled every lookup fails, and song links stay ordinary link
  cards.

## SharePlay

"Watch together" (a video post, the watch page, a run of shorts) uses
SharePlay, which needs the **Group Activities** entitlement
(`com.apple.developer.group-session`), which needs that capability on the
App ID. A profile without it cannot sign a build that claims it, so the
entitlement is behind its own switch, `ALOHA_SHAREPLAY` in
[`Aloha.xcconfig`](Aloha.xcconfig), **off by default** for both
configurations:

- **`NO`**: the apps' entitlements are the files above, and
  `AlohaSharePlayEnabled` is `NO` in their Info.plists, so no Watch together
  button is drawn. Everything else works.
- **`YES`**: `AlohaSocial` and `AlohaSocialMac` take
  `<Target>[-Shared]-SharePlay.entitlements` — the same file plus the
  group-session key — and their Info.plists say `YES`. The widgets and
  extensions are unaffected.

To turn it on: Certificates, Identifiers & Profiles → Identifiers →
`social.aloha.app` and `social.aloha.app.mac` → **Group Activities** ✓, then
`ALOHA_SHAREPLAY = YES` in `Supporting/Local.xcconfig` (or in
`Aloha.xcconfig` once the capability is on for the team that ships). Keep
each `-SharePlay` file in step with the file it extends.
