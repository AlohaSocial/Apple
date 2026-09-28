# Supporting files

## Push notifications

`aps-environment` is **deliberately not** in `AlohaSocial.entitlements`.

Adding it to a checked-in entitlements file breaks every build whose
provisioning profile lacks the Push Notifications capability — which is every
profile until somebody enables it on the App ID — and a build signed with an
entitlement its profile does not grant misbehaves at launch rather than failing
cleanly.

To turn push on:

1. Enable **Push Notifications** for `com.nextcloud.alohasocial` in the Apple
   Developer portal, and let Xcode regenerate the profile.
2. Add the capability in Xcode (Signing & Capabilities → + → Push
   Notifications), which writes `aps-environment` for you.

Until then the app runs normally and simply polls: `registerForNextcloudPush`
never receives a device token, and `AppDelegate` treats the registration
failure as a degradation rather than an error. Nothing else changes.

See [docs/14-open-questions.md](../docs/14-open-questions.md) §7 for the
Nextcloud proxy flow itself.
