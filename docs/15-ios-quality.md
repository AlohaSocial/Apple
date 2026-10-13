# iOS quality pass

The current priority is to finish and verify iPhone and iPad, with native iPad
sidebar/navigation and bounded loading buffers. Mac design work is deferred. Photos should open in an Instagram-style post feed. The overall
interface should use native Liquid Glass controls without crowding the content.
Changes are pushed to draft PR #8 from `SchBenedikt:codex/liquid-glass-quality`.

## Evidence recorded on 12 October 2026

| Area | Current evidence | Remaining checks |
| --- | --- | --- |
| Introduction | Standard and accessibility-size UI flows passed; vector logo visually inspected | Terms navigation and heading contrast passed on the smaller phone; the Welcome Continue control still requires audit diagnosis. Dark appearance remains open |
| Photos | Default feed, feed/grid switching and opening media passed; screenshot inspected | Multi-image gestures, loading failures, large text and dark appearance |
| Composer | Publishing, reply prefilling and additional-actions menu passed | Card creation, media/polls/scheduling, cancellation and accessibility |
| Account navigation | Account switching and search passed | Disabled active feed, sign-out, expired credentials and deep links |
| Feed preferences | UI choice passed; persisted settings survive a fresh database container | Changes through Settings and account-specific navigation |
| Themes | Theme test runner exited unexpectedly; no completed result bundle | Complete light/dark sheet checks and contrast audits |
| Other screens | Earlier navigation checks cover the main tabs and Settings | Notifications, conversations, profile/thread, safety and error states |
| iPhone sizes | Recent interaction checks used iPhone 18 Pro | iPhone 17e audit in progress; first-run contrast failures recorded. Landscape and large text remain open |
| iPad | Native sidebar and deep-content tour passed; Black/Warm Light feed canvas checked in portrait and landscape on iPad Pro 13-inch | Resizing, smaller iPads and large text remain open |
| Packages | 100 UI-package tests passed after the buffering, navigation and network-recovery changes; all eight suites passed in the earlier baseline | Re-run relevant suites when source changes require it |

A build, an empty test suite, and a test-runner restart do not prove that a
screen works. Runtime tests and screenshots must be evaluated against the
actual navigation and visible controls, including new menu locations. Mock
accounts use an in-memory store; persistence is verified separately against a
file-backed store instead of inferred from a mock app relaunch.

## Current loading and navigation improvements

- Timeline and photo views request another page while eight posts remain.
- Photo views use the existing bounded image prefetcher.
- End-of-history responses stop repeated older-page requests; a remaining
  server cursor is preserved when client-side filtering yields an empty page.
- Thread details paint cached posts before fetching fresh context and counts.
- iPad sidebar width is configured on the sidebar column. Compose controls
  are attached to navigation destinations so pushed profiles keep the action.

Buffered paging is also integration-tested with delayed responses: overlapping
near-end events issue one request, and a successful retry clears the offline
state while failed requests retain cached posts.

## iPad canvas and navigation repair (2026-10-13)

The theme now wraps a separate shell view before that shell reads its palette.
Previously the shell read the default Warm Light palette while the feed read the
selected dark palette, leaving bright gutters around a dark scrolling surface.
Reader columns also paint their surrounding canvas from the inherited palette.

The iPad home feed fills the detail column, with adaptive row insets limiting
reading width to 820 points. Other reading surfaces use an 820-point column on
iPad and retain the 680-point Mac column. The split detail uses a compact native
navigation title and the existing system sidebar, search and toolbar controls.

Validation: iPad Pro 13-inch simulator build and deep-content tour; a screenshot
luminance regression checks the home feed margin in Black and Warm Light in
portrait and landscape. The theme-tour helper now returns through the iPad
sidebar instead of accidentally toggling it while remaining in Settings.
