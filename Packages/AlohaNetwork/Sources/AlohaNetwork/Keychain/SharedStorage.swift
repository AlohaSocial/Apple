// SPDX-License-Identifier: MIT

import Foundation

/// The one app group every process in this app shares.
///
/// Getting this wrong is invisible: writing to `UserDefaults.standard` from the
/// app and reading it from an extension silently returns nothing, because each
/// process has its own standard domain. Naming it once removes the chance.
public enum AppGroup {
    public static let identifier = "group.social.aloha.app"

    /// Whether this binary may use the shared app group.
    ///
    /// Every target that carries `com.apple.security.application-groups` in
    /// its entitlements says so in its Info.plist (`Supporting/README.md`
    /// lists them). The default is **off**: a process without the key (a
    /// unit-test runner, a tvOS/watchOS target with a generated plist) must
    /// not claim a container it was never granted — claiming it fails every
    /// `UserDefaults` and Keychain call. A contributor signing with another
    /// team either registers the group under their team or sets the key to
    /// false, and gets an app that works alone.
    ///
    /// The same `group.` identifier serves the Mac: since macOS 15 an
    /// iOS-style group is valid there when the provisioning profile grants
    /// it, which automatic signing does, so the Mac app and its widgets share
    /// one name with the iPhone instead of a team-prefixed variant.
    public static let isEnabled =
        Bundle.main.object(forInfoDictionaryKey: "AlohaAppGroupEnabled") as? Bool ?? false

    /// Falls back to `.standard` where the entitlement is missing — an unsigned
    /// local build — so the app still works alone even though sharing does not.
    /// `UserDefaults` is thread-safe by contract; the compiler cannot see
    /// that, hence the annotation rather than a lock.
    nonisolated(unsafe) public static let defaults: UserDefaults =
        isEnabled ? (UserDefaults(suiteName: identifier) ?? .standard) : .standard

    /// The Keychain access group. Must be passed to every `CredentialStore`,
    /// or an extension cannot read what the app wrote.
    ///
    /// Keychain sharing (`keychain-access-groups`) is an entitlement of its
    /// own, independent from the shared container app group above: the build
    /// can share credentials with its extensions without sharing
    /// `UserDefaults`. Gating it on `isEnabled` silently disabled a capability
    /// the app was still entitled to.
    public static let keychainAccessGroup: String? =
        Bundle.main.object(forInfoDictionaryKey: "AlohaKeychainSharingEnabled") as? Bool ?? true
        ? "social.aloha.app"
        : nil

    /// Moves what this process wrote to `.standard` while the group was off
    /// — the active account, the Nextcloud push registration, the Focus
    /// state — into the group, once.
    ///
    /// Only the app does this: an extension's standard domain was always its
    /// own and empty, and one that ran first would mark the move done before
    /// the app had made it. A key the group already has wins, because the
    /// group is what the app has been writing since.
    public static func adoptStandardDefaultsIfNeeded(
        from standard: UserDefaults = .standard, into group: UserDefaults? = nil,
        isApp: Bool = Bundle.main.bundleURL.pathExtension == "app"
    ) {
        let group = group ?? defaults
        guard isApp, group !== standard, !group.bool(forKey: adoptedStandardKey) else { return }
        for (key, value) in standard.dictionaryRepresentation()
        where key.hasPrefix("aloha.") && group.object(forKey: key) == nil {
            group.set(value, forKey: key)
        }
        group.set(true, forKey: adoptedStandardKey)
    }

    static let adoptedStandardKey = "aloha.adoptedStandardDefaults"

    // Keys shared across processes.
    public static let activeAccountKey = "aloha.activeAccount"
    public static let unreadTotalKey = "aloha.unreadTotal"
    /// How many conversations are unread, per account id. The sidebar's
    /// badge on "Direct messages" reads it, and it is written by the
    /// messages list — the one place that already holds the answer.
    public static let unreadConversationsKey = "aloha.unreadConversations"
    public static let pendingRouteKey = "aloha.pendingRoute"
}

extension CredentialStore {
    /// The store every process should use. A `CredentialStore()` with no access
    /// group is private to the process that made it, which is why the service
    /// extension could not read the push keys.
    public static let shared = CredentialStore(accessGroup: AppGroup.keychainAccessGroup)
}
