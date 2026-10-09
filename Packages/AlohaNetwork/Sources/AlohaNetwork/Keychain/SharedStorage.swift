// SPDX-License-Identifier: MIT

import Foundation

/// The one app group every process in this app shares.
///
/// Getting this wrong is invisible: writing to `UserDefaults.standard` from the
/// app and reading it from an extension silently returns nothing, because each
/// process has its own standard domain. Naming it once removes the chance.
public enum AppGroup {
    public static let identifier = "group.com.nextcloud.alohasocial"

    /// Whether this binary may use the shared app group.
    ///
    /// Personal-development signing cannot claim a production app group, so
    /// each shipped target opts in through its Info.plist only when the
    /// matching entitlement is actually present. The default is **off**: a
    /// process without the key (a unit-test runner, a tvOS/watchOS target
    /// with a generated plist) must not claim a container it was never
    /// granted — claiming it fails every `UserDefaults` and Keychain call.
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
            ? "com.nextcloud.alohasocial"
            : nil

    // Keys shared across processes.
    public static let activeAccountKey = "aloha.activeAccount"
    public static let unreadTotalKey = "aloha.unreadTotal"
    public static let pendingRouteKey = "aloha.pendingRoute"
}

extension CredentialStore {
    /// The store every process should use. A `CredentialStore()` with no access
    /// group is private to the process that made it, which is why the service
    /// extension could not read the push keys.
    public static let shared = CredentialStore(accessGroup: AppGroup.keychainAccessGroup)
}
