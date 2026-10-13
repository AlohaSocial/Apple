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
| iPad | Native sidebar routing and deep-content tour passed: thread, profile, publishing, discovery, lists, conversations, search and account drawer | Landscape, resizing, large text and appearance checks |
| Packages | 96 UI-package tests passed after the buffering and navigation changes; all eight suites passed in the earlier baseline | Re-run relevant suites when source changes require it |

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
