# Coding mac-videos

Read AGENTS.md and README.md. This repo builds entirely on this MacBook, not the Mac Studio.

## Build

```sh
xcodebuild -project MacVideos.xcodeproj -scheme MacVideos -configuration Debug -derivedDataPath .build build
open .build/Build/Products/Debug/mac-videos.app
```

Xcode 27+, macOS 27+, Swift 6; Apple Development signing for Debug and automatic provisioned Release archives, exported with Developer ID (team `227GEZ2676`). The new local bundle identifier is `io.golfergeek.mac-videos`; it must stay stable for preferences and permission identity. App targets link a small MacVideosCore framework. Tests link only core and run without launching the app or asking for media permissions. The checked-in project has no external package dependencies. XcodeGen is only needed for project structure edits: update project.yml and run `xcodegen generate`.

Keychain access is lazy and MainActor-serialized. The local fallback uses a fresh service, explicit signed-app-only ACL and scoped interaction suppression; never read the original legacy service. Release uses provisioned data protection Keychain; Debug retains the file-Keychain fallback. See docs/releasing.md and docs/plans/keychain-no-prompts.md.

## Required checks

Run `./scripts/check.sh` (build + hostless tests). `MAC_VIDEOS_BUILD_DIR=/absolute/path` overrides `.build`. Check logs for BUILD SUCCEEDED and TEST SUCCEEDED. Run `./scripts/check-keychain.sh` after a Keychain change; it uses only a disposable synthetic test service, checks another app identity is denied, and removes its test item. Xcode can emit a harmless AppIntents metadata warning because the app does not use AppIntents. No CI workflows are expected.

For UI/capture edits follow README's permission-enabled smoke test. Compile/tests alone cannot prove screen capture, sound or camera compositing. Do not grant macOS privacy permissions silently or report an MP4 as tested when no recording was made.

## Boundaries

Settings and pure output/device logic live in MacVideosCore. The MainActor RecorderModel owns one SCStream/SCRecordingOutput per run and waits for finalization; CameraSession owns a serial queue for AVCaptureSession. CameraBubble owns the AppKit panel. StopShortcut owns the registered Carbon hotkey. SwiftUI windows/menu are in MacVideosApp.swift.

Optional YouTube uploads use system-browser OAuth, loopback/PKCE/state, Keychain and resumable chunked requests. No Google configuration is bundled; see docs/youtube-setup.md. Keep network/OAuth logic hostlessly testable in core. No keys, tokens, personal recordings, production changes or GitHub Actions in the repo. Use worktrees, stage explicit paths, and leave the shared checkout on its current branch. See workspace guardrails for review/merge gates.
