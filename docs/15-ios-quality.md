# iOS quality pass

The current priority is to finish and verify the iOS application. Mac design work
is deferred. Photos should open in an Instagram-style post feed. The overall
interface should use native Liquid Glass controls without crowding the content.
Changes are pushed to draft PR #8 from `SchBenedikt:codex/liquid-glass-quality`.

## Evidence recorded on 12 October 2026

| Area | Current evidence | Remaining checks |
| --- | --- | --- |
| Introduction | Standard and accessibility-size UI flows passed; vector logo visually inspected | Small-phone audit reports contrast failures; investigate the reported controls and terms navigation. Dark appearance remains open |
| Photos | Default feed, feed/grid switching and opening media passed; screenshot inspected | Multi-image gestures, loading failures, large text and dark appearance |
| Composer | Publishing, reply prefilling and additional-actions menu passed | Card creation, media/polls/scheduling, cancellation and accessibility |
| Account navigation | Account switching and search passed | Disabled active feed, sign-out, expired credentials and deep links |
| Feed preferences | UI choice passed; persisted settings survive a fresh database container | Changes through Settings and account-specific navigation |
| Themes | Theme test runner exited unexpectedly; no completed result bundle | Complete light/dark sheet checks and contrast audits |
| Other screens | Earlier navigation checks cover the main tabs and Settings | Notifications, conversations, profile/thread, safety and error states |
| iPhone sizes | Recent interaction checks used iPhone 18 Pro | iPhone 17e audit in progress; first-run contrast failures recorded. Landscape and large text remain open |
| iPad | Native iOS build compiles | Runtime layout, split navigation and presentations |
| Packages | 344 tests passed across all eight package suites | Re-run relevant suites when source changes require it |

A build, an empty test suite, and a test-runner restart do not prove that a
screen works. Runtime tests and screenshots must be evaluated against the
actual navigation and visible controls, including new menu locations. Mock
accounts use an in-memory store; persistence is verified separately against a
file-backed store instead of inferred from a mock app relaunch.
