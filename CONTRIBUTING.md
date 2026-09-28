# Contributing to Aloha Social

## Requirements

- **Xcode 27** and **Swift 6.4**. Nothing older builds this.
- A signing team for device builds. Simulator and `CODE_SIGNING_ALLOWED=NO`
  builds need nothing.
- No other setup. There are no API keys, no `.xcconfig` the repository does not
  carry, and no manual steps: OAuth clients are registered at runtime per
  instance through `POST /api/v1/apps`, so there is no app-wide secret to hold.

```sh
git clone <this repository>
cd AlohaSocial
open AlohaSocial.xcodeproj
```

## Running the tests

Each package tests independently:

```sh
for package in AlohaModels AlohaHTML AlohaNetwork AlohaStore AlohaMedia; do
  (cd "Packages/$package" && swift test)
done
```

## The dependency policy

**Zero third-party runtime dependencies.** Apple frameworks only, plus the
local packages under `Packages/`. CI fails a pull request that adds a
`.package(url:)`.

Adding one requires a written justification in the pull request and an
MIT-compatible licence. The default answer is no. The reasoning is in
[docs/01-architecture.md](docs/01-architecture.md) §1.

## Conventions

The full set is in [docs/12-conventions-quality.md](docs/12-conventions-quality.md).
The short version:

- Swift 6 language mode, strict concurrency complete.
- `@Observable`, not `ObservableObject`. No Combine.
- No force unwraps, no force tries, no `fatalError` outside genuine programmer
  error.
- `// SPDX-License-Identifier: MIT` as the first line of every file. CI checks.
- Comment *why*, not *what*. Every server workaround names the behaviour it
  works around, and the route where there is one.
- Feature folders, not layer folders.

## Where things live

`Packages/` holds eight local Swift packages in a strict DAG; the app target is
a thin shell over them. [docs/01-architecture.md](docs/01-architecture.md) §3
has the graph and what each package owns.

## The one thing not to break

API base discovery ([docs/03-auth-and-accounts.md](docs/03-auth-and-accounts.md) §2).
Nextcloud Social's Mastodon API is only at the domain root when an
administrator has applied the web-server rewrite rules, and many instances have
not. `ServerProbe` finds it either way. The test that pins this is
`"A Nextcloud WITHOUT the rewrite rules still resolves"` in
`Packages/AlohaNetwork/Tests`. If it fails, the app has stopped working for
self-hosters.
