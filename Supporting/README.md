# Supporting files

## App group and Keychain sharing

Every process that reads what the app wrote shares two things:

| Target | Bundle id | Entitlements file | App group | Keychain group | Sandbox |
|---|---|---|---|---|---|
| AlohaSocial (iPhone, iPad, Vision, Mac) | `social.aloha.app` | `AlohaSocial.entitlements` | ✓ | ✓ | ✓ (Mac) |
| AlohaWidgets (iOS) | `social.aloha.app.widgets` | `AlohaWidgets.entitlements` | ✓ | ✓ | — |
| AlohaWidgets (Mac) | `social.aloha.app.mac.widgets` | `AlohaWidgets.entitlements` | ✓ | ✓ | ✓ + network client |
| AlohaShareExtension | `social.aloha.app.share` | `AlohaShareExtension.entitlements` | ✓ | ✓ | — |
| AlohaNotificationService | `social.aloha.app.notificationservice` | `AlohaNotificationService.entitlements` | ✓ | ✓ | — |
| AlohaSocialMac | `social.aloha.app.mac` | `AlohaSocialMac.entitlements` | ✓ | ✓ | ✓ + network client, user-selected files |

- App group: `group.social.aloha.app`, on every platform. Since macOS 15 an
  iOS-style `group.` identifier is valid on the Mac when the provisioning
  profile grants it, so the Mac does not need a team-prefixed variant.
- Keychain group: `$(AppIdentifierPrefix)social.aloha.app`. On the Mac the
  shared items live in the data protection keychain, the only one that honours
  an access group; items an older build left in the file-based keychain are
  moved over on first read.
- Each target that has the app group says so with `AlohaAppGroupEnabled` in
  its Info.plist. Without the key, `AppGroup` stays on the process's own
  container rather than claiming one it was never granted.

With automatic signing, building registers both capabilities on each App ID
(**App Groups** and **Keychain Sharing**, plus the group itself) and puts them
in the profiles. To check by hand: Certificates, Identifiers & Profiles →
Identifiers → each bundle id above → App Groups ✓ (with
`group.social.aloha.app` assigned) and Keychain Sharing ✓.

**Signing with another team.** An app group belongs to the team that
registered it, so another team cannot claim `group.social.aloha.app`. Either
change the group to one of your own — the string in each `*.entitlements`,
`AppGroup.identifier` and `StoreContainer.appGroupIdentifier` — or set
`AlohaAppGroupEnabled` to `false` in the Info.plists and remove
`com.apple.security.application-groups` from the entitlements. The second gives
an app that works alone, with widgets and extensions that see no accounts.

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
