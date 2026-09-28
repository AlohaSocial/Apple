# 03 — Authentication and accounts

## 1. The problem this solves

Mastodon's client protocol has no way to be told about a non-root API base.
Every client builds `https://<host>/api/v1/…` from the host a person types.

Nextcloud Social registers its routes under the app prefix, so they live at
`https://<host>/index.php/apps/social/api/v1/…`. Nextcloud Social's merged
PR #2250 ships Apache and nginx rules that internally proxy `/api` and `/oauth`
to the app — internally rather than by redirect, so the `Authorization` header
survives — plus a setup check that warns an administrator when the rules are
missing.

Those rules are **administrator-configured**. Many instances will not have them.
Aloha Social therefore **probes for the API base and stores it per account.**

This is the single most important thing to get right, because it is the
difference between "works with my Nextcloud" and "doesn't".

## 2. API base discovery

Given what a person typed (`cloud.example.com`, `https://cloud.example.com/`,
`cloud.example.com/nextcloud`, or `@alice@cloud.example.com`):

1. **Normalise.** Strip a leading `@handle@`. Strip whitespace. Lowercase the
   host. Default the scheme to `https`. Keep any path the person typed as a
   *hint* but do not assume it. Reject anything that is not a valid host.

2. **Candidate bases**, tried in order:

   | # | Candidate | Why |
   |---|---|---|
   | 1 | `https://<host>/` | Root. Real Mastodon, and Nextcloud Social with the rewrite rules. |
   | 2 | `https://<host>/index.php/apps/social/` | Nextcloud Social, no rewrite. |
   | 3 | `https://<host>/apps/social/` | Nextcloud with pretty URLs and no rewrite. |
   | 4 | `https://<host><typed path>/` | If the person typed a path, e.g. a Nextcloud in a subdirectory. |
   | 5 | `https://<host><typed path>/index.php/apps/social/` | Both of the above. |
   | 6 | user-entered override | Advanced field, see §3. |

3. **Probe** each candidate with `GET {candidate}api/v2/instance`, falling back
   to `api/v1/instance/` on 404. A candidate qualifies when the response is 200
   **and** decodes as an Instance entity with a non-empty `uri`/`domain`.
   Probes run **concurrently** with a 5-second per-candidate timeout; the
   lowest-numbered success wins. Total discovery budget: 10 seconds.

4. **Cross-check** with `GET https://<host>/.well-known/nodeinfo/2.1`
   (falling back to `2.0`), which Nextcloud Social serves at the true domain
   root regardless of the rewrite. This gives `software.name` and
   `software.version` and is what sets `ServerCapabilities.softwareName`.
   A nodeinfo failure is not fatal.

5. **Store** the winning base on the account. Every request for that account is
   built against it. Nothing in the app ever assumes the root.

6. **Re-probe** if any request against the stored base returns 404 for a route
   that should exist — an administrator may have added or removed the rewrite.
   Re-probe at most once per hour per account, and never in a loop.

### WebFinger

For "open this handle" flows, `https://<host>/.well-known/webfinger?resource=acct:user@host`
is served at the true root on Nextcloud Social. Use it to resolve a handle to a
profile URL before falling back to `/api/v2/search?resolve=true`.

### Failure UI

If no candidate answers, the sign-in sheet shows what was tried, in plain
language, with three actions: **Try again**, **Enter API address manually**, and
**Copy server setup instructions** — the last copies the Apache/nginx snippet
from Nextcloud Social's own documentation so the person can hand it to whoever
runs the server. This is a genuine outcome for a self-hoster and must not read
like a crash.

## 3. Advanced: manual base override

Behind a disclosure in the sign-in sheet: a single text field, "API address",
pre-filled with the best candidate found. Typing a value skips discovery and
uses it verbatim (normalised to end in `/`). Stored with the account and
editable later in account settings. Documented as unsupported.

## 4. OAuth 2 with PKCE

Nextcloud Social implements the authorisation-code grant with PKCE
(`code_verifier` on the token exchange), advertises
`/.well-known/oauth-authorization-server`, supports both
`client_secret_post` and `client_secret_basic`, and stores authorisations in a
table of their own — so **one registered app can hold many tokens**, and a
second person signing in no longer revokes the first. Revoking one token no
longer signs everybody out. Aloha Social relies on all of this.

### Flow

1. **Discover** `GET {base}.well-known/oauth-authorization-server` where
   available; use its `authorization_endpoint`, `token_endpoint`,
   `revocation_endpoint` and `code_challenge_methods_supported`. Fall back to
   `{base}oauth/authorize`, `{base}oauth/token`, `{base}oauth/revoke` and assume
   `S256`.

2. **Register** once per instance:
   ```
   POST {base}api/v1/apps
     client_name    = "Aloha Social"
     redirect_uris  = "alohasocial://oauth-callback"
     scopes         = "read write follow push"
     website        = "https://github.com/<owner>/AlohaSocial"
   ```
   The response carries `client_id`, `client_secret`, `redirect_uri` and an
   empty `vapid_key` (there is no Web Push here — that empty string is the
   server telling the client not to ask).

   Cache `client_id`/`client_secret` **per instance host** in the Keychain and
   reuse them for every subsequent account on that host. Re-register on a 401
   from the token endpoint.

   Note `redirect_uris` accepts several, newline-separated in one field, and
   Nextcloud Social splits on newlines. Send one.

3. **Authorise** via `ASWebAuthenticationSession` (all platforms;
   `ASWebAuthenticationSession` is available on macOS, visionOS and tvOS, and
   the watch app never authenticates on its own — see §7):
   ```
   GET {authorization_endpoint}
     ?response_type=code
     &client_id=…
     &redirect_uri=alohasocial://oauth-callback
     &scope=read+write+follow+push
     &state=<32 bytes base64url>
     &code_challenge=<S256(verifier)>
     &code_challenge_method=S256
   ```
   `prefersEphemeralWebBrowserSession = false` so an existing Nextcloud session
   is reused — this is the difference between one tap and typing a password.

4. **Exchange**:
   ```
   POST {token_endpoint}
     grant_type    = authorization_code
     code          = …
     client_id     = …
     client_secret = …
     redirect_uri  = alohasocial://oauth-callback
     code_verifier = …
   ```
   Note there is deliberately **no `scope` parameter** on this request — RFC
   6749 §4.1.3 has none, and Nextcloud Social refuses requests that send one
   against a stale app row. Do not send it.

   A code is spent in the same statement that writes the token, so a duplicated
   exchange fails safely. Never retry an exchange automatically.

5. **Verify** with `GET {base}api/v1/accounts/verify_credentials` to get the
   account entity, and `GET {base}api/v1/apps/verify_credentials` to confirm the
   token names this app.

6. **Store** and run capability detection.

### Scopes

Request `read write follow push` always. `push` costs nothing on a server with
no Web Push and is needed on servers that have it. Nextcloud Social checks
granular scopes on several routes (`read:lists`, `read:notifications`,
`write:notifications`, `read:stories`, `write:stories`), all of which are
covered by the coarse grants.

### Revocation

Signing out calls `POST {revocation_endpoint}` with `client_id`,
`client_secret` and `token`, then deletes everything local for that account —
Keychain entry, SwiftData rows, cached media, drafts, widget timeline entries.
A revocation failure does not block local sign-out, but is retried once on next
launch.

## 5. Token storage

- Access tokens, client ids and client secrets live in the **Keychain**,
  `kSecClassGenericPassword`, access group
  `$(AppIdentifierPrefix)com.nextcloud.alohasocial` so the share extension and
  widgets can read them.
- `kSecAttrAccessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
  **`ThisDeviceOnly` is deliberate**: tokens must not sync to iCloud Keychain
  or transfer in an encrypted backup to a different device.
- Service: `com.nextcloud.alohasocial.token`; account key:
  `<accountUUID>` (not the handle, which can change).
- Non-secret account metadata (handle, display name, avatar URL, API base,
  capabilities) lives in SwiftData, not the Keychain.
- Nothing is logged that contains a token, a code, or a verifier. The network
  logger redacts `Authorization`, `client_secret`, `code`, `code_verifier` and
  `access_token` unconditionally.

## 6. Multi-account

- Unlimited accounts, any mix of servers. The same handle on two servers, or
  two accounts on one server, are distinct — keyed by a client-generated UUID.
- Every model row, cache entry, draft, and widget entry carries `accountID`.
  There is no global timeline table.
- Exactly one **active account** at a time in 1.0. Switching is a first-class
  gesture: long-press the avatar in the navigation bar (iOS), a menu in the
  sidebar (iPad/Mac), the account row in Settings.
- Switching must be instantaneous from cache: the new account's cached home
  timeline paints before any network call.
- Per-account settings: default visibility, default language, default sensitive,
  NSFW/expand-media policy, autoplay preference, notification preferences,
  which modes appear and in what order.
- A background poll runs for **every** signed-in account, not only the active
  one, so the unread badge is accurate. Non-active accounts poll at a longer
  interval — see [08-notifications-sync.md](08-notifications-sync.md) §3.
- An account whose token is revoked stays in the list, marked, with its cache
  intact, until the person removes it or signs in again.

## 7. Per-platform authentication

| Platform | How |
|---|---|
| iOS / iPadOS / macOS / visionOS | `ASWebAuthenticationSession` as above. |
| tvOS | `ASWebAuthenticationSession` is not available. Use the **device-code style handoff**: show a QR code and short URL for the instance's authorise URL with the app's `client_id`, and poll `{base}api/v1/accounts/verify_credentials` against a token the phone app hands over via the shared iCloud keychain… **which is not available** (`ThisDeviceOnly`). Therefore: tvOS signs in by showing a QR code that opens the authorise page on a phone, where the person copies the resulting out-of-band code (`urn:ietf:wg:oauth:2.0:oob`, which Nextcloud Social's OAuth controller supports) and types it into the TV. Six characters, on screen, once. |
| watchOS | Never authenticates. Receives the active account's token and API base from the phone over `WatchConnectivity` on pairing and on token change, and stores it in the watch's own Keychain with the same accessibility class. |

tvOS's out-of-band path depends on Nextcloud Social honouring
`urn:ietf:wg:oauth:2.0:oob` as a redirect URI, which its `OAuthController`
does (`denyUrl` and `authorizing` both special-case it). Real Mastodon supports
it too. If an instance rejects it, tvOS falls back to a message asking the
person to sign in on another device — tvOS is the lowest-priority target.

## 8. Sign-in screen

One screen, three states.

**Empty:** a single field, "Your server", placeholder
`cloud.example.com`. Below it, one line: "Aloha Social works with Nextcloud
Social, Mastodon, and any server that speaks the Mastodon API." Below that, a
link: "What is Nextcloud Social?"

**Probing:** the field is disabled, an indeterminate progress view, and the
candidate currently being tried in small text. This is honest about what is
happening and makes the 10-second budget feel intentional.

**Found:** the instance's thumbnail, title, short description, user count,
and its rules if it has any (`/api/v1/instance/rules`). A "Sign in" button that
opens the web session. If `registrations` is false — which it always is on
Nextcloud Social, since an account there is a Nextcloud account — there is no
"Create account" button, only a link to the instance's own sign-up or
information page.
