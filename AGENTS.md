# mac-videos agent rules

## Scope and layout

Personal macOS 27+ app, Swift 6, SwiftUI + AppKit, ScreenCaptureKit and AVFoundation. Read README.md and CODING.md first. See docs/plans/v1.md for architecture and docs/matt-queue.md for pending hands-on checks. Sources/MacVideos owns UI, capture, permissions, camera panel and stop shortcut. Sources/MacVideosCore contains independently testable logic; Tests contains hostless XCTest tests.

## Workflow

- Use an isolated worktree and branch; never switch branches or edit the shared checkout. Do not alter unrelated work.
- Follow workspace/global guardrails. No GitHub Actions, Docker, remote services, telemetry or secrets. Do not commit recordings or personal device inventories.
- Use the existing Xcode project to build. If changing project layout/settings, update project.yml, run xcodegen generate, and commit both the spec and generated project. No manual project drift.
- Run ./scripts/check.sh before opening/readying a PR and again on its exact head before merge. Review the diff and record review/check results on the PR. Only merge/push when the task authorizes it.
- UI changes require a native app launch and layout inspection. Screen, camera and mic consent is a user action; report actual capture as unverified unless a permission-enabled recording has been played and inspected.
- Keep all AVFoundation camera session mutations on its serial queue; all UI/model transitions on MainActor. Callbacks must ignore stale recording objects.
- Exclude every app window from capture except the camera bubble. Never replace this with excluding the whole app without the bubble exception. Do not claim success until SCRecordingOutput finishes and the file has valid media tracks.
- Keep credentials out of the repo, settings and logs. Future OAuth refresh tokens belong in Keychain. V1 makes no network calls.
- Questions/actions needing Matt belong in docs/matt-queue.md, with a pointer in workspace agent-communication.md. Report tests and permission/hardware limits honestly.
