# 12 — Conventions and quality bar

## 1. Swift conventions

- Swift 6 language mode, strict concurrency **complete**, warnings as errors in
  CI for **every** target and package, not a chosen four: the isolation warnings
  that matter turned up in the view layer and the extensions, which the narrower
  rule would have kept letting through.
- Default actor isolation `MainActor` (`SWIFT_DEFAULT_ACTOR_ISOLATION`), so view
  code needs no annotation and anything off the main actor says so explicitly.
- `@Observable`, not `ObservableObject`. No Combine.
- `async`/`await` throughout. No completion handlers, no `DispatchQueue`.
- Value types by default; `final class` only for SwiftData models, actors, and
  where reference identity is genuinely needed.
- No force unwraps, no force tries, no `fatalError` outside of `preconditionFailure`
  for genuine programmer error. The seed project's
  `fatalError("Could not create ModelContainer")` must be replaced with a
  recovery path that rebuilds the store.
- No `AnyView` in hot paths. No `GeometryReader` where a layout modifier works.
- Typed throws where the error set is closed (`APIError`).
- `// SPDX-License-Identifier: MIT` as the first line of every file.

### Naming

- Types: `UpperCamelCase`. Protocols name capability (`ImageLoading`) or
  conformance (`Paginated`), never `…Protocol`.
- Wire types keep the server's word (`Status`, `reblog`, `favourites_count`);
  UI-facing strings use the product's word (post, boost, favourite). The
  translation happens once, in the view model.
- Files are named for their primary type. One primary type per file.
- Feature folders, not layer folders: `Timeline/`, `Composer/`, `Shorts/`, each
  containing its views, view models and helpers.

### Comments

Comment *why*, not *what*. Every non-obvious server workaround gets a comment
naming the behaviour it works around and, where possible, the route:

```swift
// Nextcloud Social can send "" for avatar (Person::exportAsLocal falls through
// to a possibly-empty stored value), so decode as String and treat empty as nil
// rather than failing the whole Account.
```

## 2. Testing

Framework: **Swift Testing** (`import Testing`). XCTest only for UI tests.

### Required coverage

| Area | Requirement |
|---|---|
| Wire-type decoding | Every entity, from real fixture JSON captured from both a Nextcloud Social instance and mastodon.social. Including the known-malformed cases: empty `avatar`, absent `poll`, `meta` as `[]`, ids as numbers and as strings. |
| `LossyArray` | A page with one bad element decodes the rest. |
| `Link` header parsing | Every documented form, plus absent, malformed, and single-rel. |
| API base discovery | Each candidate order, first-wins, all-fail, timeout, and the re-probe trigger. |
| OAuth | PKCE challenge derivation, state validation, the no-`scope`-on-token rule, redirect parsing with a pre-existing query string and with a fragment. |
| `AlohaHTML` | A corpus of real status HTML: mentions, hashtags, custom emoji, nested formatting, malformed tags, entity edge cases, and a 50 KB pathological input with a time bound. |
| `ContentClassifier` | The short/photo/video/audio/news decision over a fixture corpus, including the missing-`meta` deferral path. |
| Timeline merge | Gap insertion, gap closing, no-duplicate insertion, position stability, deletion propagation. |
| Filters | `warn` vs `hide`, expiry, context matching. |
| Character counting | URL cost, spoiler inclusion, against both a 500- and a 5000-character server. |
| Capability detection | Each flag's detection path, and the "unknown means absent" rule. |
| Composer thread posting | Mid-thread failure leaves no duplicate and resumes correctly. |
| Idempotency | Same key on retry, new key on content change. |

### Mock server

A `MockAPIServer` in a test support package, serving the fixture corpus over a
`URLProtocol` subclass. It can be configured to behave as:

- Nextcloud Social with the root rewrite,
- Nextcloud Social **without** the rewrite (API only under `/index.php/apps/social/`),
- stock Mastodon 4.3,
- a server that 404s the extension routes,
- a server that rate-limits,
- a server that returns malformed entities.

Every one of those configurations must produce a working app in the integration
tests. **The no-rewrite configuration is the most important test in the suite.**

### UI tests

A small, stable set on iOS and macOS only: sign in (mocked), read the home
timeline, open a thread, compose and post, open the media viewer, switch
accounts. They exist to catch wiring breakage, not to assert layout.

### Performance tests

- Timeline scroll: 500 cached rows, measured frame time, asserted under 8 ms
  p99 on the CI simulator.
- Cold launch to first paint, asserted under 400 ms with a warm cache.
- `AlohaHTML` parse of the corpus, asserted under a fixed total.

## 3. Accessibility

Non-negotiable, on every screen, verified before a feature is called done.

- **Dynamic Type** at every size including the five accessibility sizes. No
  fixed font sizes. Layouts reflow rather than truncate; anything that must
  truncate is reachable another way.
- **VoiceOver**: every element labelled. Status rows are a single element whose
  label reads "«author», «time ago», «content»", with the action row exposed as
  custom actions (reply, boost, favourite, bookmark, share, more) rather than as
  six separate elements. Media carries its alt text as the label, or "Image
  without a description" where there is none.
- **Rotor** support: headings in threads, links in status bodies.
- **Reduce Motion**: every transition has a cross-fade alternative; Shorts
  auto-advance and the favourite burst are disabled.
- **Reduce Transparency** and **Increase Contrast**: honoured by the colour
  role definitions, which carry high-contrast variants.
- **Differentiate Without Colour**: boost/favourite/bookmark states carry a
  shape change, not only a tint.
- **Bold Text**: honoured through the system font.
- **Full Keyboard Access** on iPad and Mac: every action reachable, visible
  focus rings, logical focus order.
- **Switch Control**: no gesture-only actions. Every swipe action and every
  long-press menu item exists in the `···` menu too. This is what makes the
  Shorts mode's gesture set acceptable.
- **Voice Control**: every button has a name that can be spoken.
- Automated checks: the accessibility audit API
  (`XCUIApplication.performAccessibilityAudit()`) runs over the main screens in
  CI and fails the build on contrast, hit-region and label issues.

## 4. Localisation

- **String Catalogs** (`.xcstrings`), one per package plus one for the app.
- Every user-facing string goes through `String(localized:)` with a comment
  explaining context for translators. No string literals in views.
- English (`en`) complete and is the development language. No other language
  ships in 1.0, but the structure is complete so a translation is a pull request
  and nothing else.
- Pluralisation via the catalog's plural variations, never string concatenation.
  Counts ("3 replies") are always plural-aware.
- Dates and relative times via `Date.FormatStyle` and
  `RelativeDateTimeFormatter`, never hand-built.
- Numbers via `.formatted(.number.notation(.compact))` for counts.
- **RTL**: layout uses leading/trailing throughout, never left/right. Directional
  SF Symbols use the `.mirrored` variants. Tested with the RTL pseudolanguage.
- Pseudolocalisation (`en-XA`, `ar-XB`) run in CI screenshots to catch truncation
  and hardcoded direction.

## 5. Design system checks

A test target asserts:

- Every colour role resolves in light, dark, high-contrast light and
  high-contrast dark.
- Text-on-background contrast for every role pair meets WCAG AA (4.5:1 for body,
  3:1 for large text and UI components).
- The boost/favourite/bookmark tints remain distinguishable under simulated
  protanopia, deuteranopia and tritanopia.

## 6. CI

GitHub Actions, on every push and pull request.

| Job | Does |
|---|---|
| `build` | Builds every target for every platform (iOS, iPadOS, macOS, visionOS, watchOS, tvOS), release configuration, `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`. |
| `test` | Every package with a `Tests` directory, on macOS. Discovered by walking `Packages/*/`, so a new package cannot be quietly left untested — a hand-written list had already lost `AlohaDesign` and `AlohaIntelligence`. |
| `test-simulator` | The same suites on the iOS simulator, where the `#if os(iOS)` paths are the ones that run. |
| `ui` | The screen tours and the accessibility audit on the iOS simulator, with the screenshots kept as an artefact. |
| `accessibility` | The localisation gate and the design-token suite. |
| `lint` | `swift-format --strict` with `.swift-format` at the repository root. |
| `licence` | Asserts the SPDX header on every source file and that no SPM dependency has been added. |

There is **no app unit-test target**: the app target is a shell around the
packages, and every piece of logic lives in one of them. "The app's unit tests"
are the package suites, which is why `test` and `test-simulator` are the whole
of it.

`lint` names its source directories explicitly rather than recursing over
`Packages`, which would walk `Packages/*/.build` and fail on SwiftPM's own
checkouts.

Two `swift-format` rules are deliberately off in `.swift-format`:

- `TypeNamesShouldBeCapitalized`, because `Endpoint.statuses.status(id)` reads
  as the path it builds, and the lowercase namespace enums are the API.
- `AllPublicDeclarationsHaveDocumentation`, because a `public` member of a
  namespace enum whose own docblock explains the group does not need its own.

A pull request that fails any job does not merge. There are no exceptions for
"just a small change".

### What the gates caught

Wiring `ui` up found five failures, none of them cosmetic:

| Was | Turned out to be |
|---|---|
| Three "contrast failures" on timeline rows | Measured **through** the floating tab bar and the source toggle. `palette.label` is 16.73:1 — no colour the app picks can fail there. The audit's bottom-chrome exclusion now covers anything the app floats over the content, not just `tabBars.minY`. |
| Tapping **My feed** did not return to the home timeline | A real bug. A freshly built `TimelineModel` refreshed with `min_id` whenever the cache had rows, so it only ever asked for what was *newer* — and rendered a cache another source had written. Fixed: a model that has never fetched asks for the head. |
| Discover "has no trends" | The test waited for a hashtag that only exists on the Tags tab, on a screen that opens on People. It could never have passed. |
| The thread audit timing out | The test tapped `labelled(…)`, which matches the whole row, so a tap at a tenth of its width opened a *profile* — the thread was never audited. Once it was, the lazy link-preview fetch was mutating the screen after it appeared and the audit could not finish walking it. The card is now fetched beside the status and applied before the first draw. |

The last one is the useful one: an accessibility audit timing out is a screen
that will not settle, and a screen that will not settle is one that moves under
the reader.

## 7. Logging

- `OSLog` with a subsystem per package (`com.nextcloud.alohasocial.network`, …)
  and categories per area.
- Privacy annotations on every interpolation: `.public` only for things that are
  genuinely not personal (status codes, route templates, durations). Handles,
  content, URLs with ids, and anything from a token are `.private` by default,
  which is also `OSLog`'s default — never override it to `.public` to make
  debugging easier.
- A debug-only network inspector screen behind a five-tap gesture in Settings →
  About, showing recent requests with redacted headers. Not present in release
  builds (`#if DEBUG`).

## 8. Performance budgets

| Metric | Budget |
|---|---|
| Cold launch → first painted row (warm cache) | 400 ms |
| Timeline scroll frame time, p99 | 8 ms |
| Shorts mode frame time, p99 | 8 ms |
| Memory, timeline with 500 cached rows | < 250 MB |
| Memory, share extension | < 60 MB |
| Background refresh wall time | < 25 s, hard |
| Disk, image cache | 512 MB default ceiling |

Budgets are asserted where testable and measured with Instruments where not.
Regressions are treated as bugs.
