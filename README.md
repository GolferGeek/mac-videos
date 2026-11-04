# mac-videos

A small native Mac app for recording project walkthroughs. Choose a display, microphone and camera, then record a full-screen H.264 MP4 with a round camera bubble you can drag. Recordings stay on your Mac. You can optionally upload an unlisted copy to YouTube after confirming each upload.

## Build and run

Requires **macOS 27 or later** and **Xcode 27 or later**, with Xcode's command-line tools selected. This version targets Matt's MacBook Pro (macOS 27.2). There are no third-party runtime dependencies, package downloads, Docker services or GitHub Actions.

From this repository:

```sh
xcodebuild -project MacVideos.xcodeproj -scheme MacVideos \
  -configuration Debug -derivedDataPath .build build
open .build/Build/Products/Debug/mac-videos.app
```

Alternatively, open `MacVideos.xcodeproj` in Xcode, choose the **MacVideos** scheme and **My Mac**, and click Run. Debug and Release builds use Matt’s existing Apple Development certificate (team `227GEZ2676`) from the login Keychain. Keep the bundle ID `io.golfergeek.mac-videos` and installed path consistent so rebuilds retain the same permission identity. The signing certificate and private key must be available locally. No notarization or App Store distribution is included.

If macOS still says Screen Recording is off after an update, quit mac-videos, remove it with the minus button in **System Settings → Privacy & Security → Screen & System Audio Recording**, add `/Applications/mac-videos.app` back, and reopen the app. After the switch from ad hoc to Apple Development signing, you may need to re-enter your Google client ID (and desktop client secret if supplied) once. YouTube setup and tokens keep the stable Keychain service `io.golfergeek.mac-videos.youtube`; existing items are not automatically deleted or reset.

## Make your first recording

1. Pick your display (defaults to the main display), USB or other microphone, and camera. **Refresh sources** discovers newly connected devices. Device choices, display, bubble size/visibility and save folder are remembered. Identical device names have a short identifier to distinguish them.
2. Leave **Show camera bubble** on, or turn it off for screen-only recording. Choose Small, Medium or Large. Enable the bubble before starting if you want it in this recording; when enabled at start, you can hide/show and resize it during recording.
3. Click **Start recording**, or use the mac-videos menu bar icon. On the first attempt, macOS asks for **Microphone**, **Camera** (only with the bubble on), and **Screen & System Audio Recording** access. Allow the permissions you want. If denied, the app explains the problem and has buttons to open the matching System Settings pane. Enable **mac-videos** under **System Settings → Privacy & Security**, then quit and reopen the app. Some first grants require a second start after relaunch.
4. During the three-second countdown, move the circle where you want it. Drag it anywhere on the **selected display**, including while recording. If moved onto another display, it is outside the recorded area. The controls and other app windows are excluded; the bubble is explicitly included. The screen's menu bar remains part of the full-display recording.
5. Stop with **⇧⌘S** (Shift–Command–S), **Stop** in the controls, or the menu bar. The hotkey works while another app is active and needs no Accessibility permission. If the shortcut is already taken, the app tells you to use the menu bar or controls. The shortcut also cancels the countdown.
6. Wait for finishing to complete, then click **Show in Finder**. Open the file in QuickTime Player to play it. The app checks that the finalized file has video, audio and a positive duration before marking it saved. Stop before quitting; the app prevents an accidental quit during capture.

The default folder is `~/Movies/mac-videos`. Use **Change…** to choose a different folder, including one on an external SSD. Filenames include local date/time and a unique suffix, such as `mac-videos_2026-11-03_14-30-00_<unique-id>.mp4`. A disconnected drive produces an error rather than silently saving somewhere else. Disk/write failures can leave a partial file; the app reports the failure and preserves it for inspection.

Video records at 30 fps, SDR, up to 3840 pixels on the longest edge (larger Retina displays are scaled to fit H.264 limits, preserving the whole display). MP4 microphone audio uses ScreenCaptureKit's AAC encoder. System audio is off. The camera uses AVFoundation; hiding its bubble keeps the camera session ready until Stop, and the camera is released after recording. The menu bar icon changes while recording. Capture ends on selected device loss or display reconfiguration, with a message to check the partial recording.

## Checks

```sh
./scripts/check.sh
```

This runs `xcodebuild build` and `xcodebuild test` locally. Core unit tests cover settings persistence/defaults, missing-device fallback, device deduplication, filename uniqueness and video sizing. To put build artifacts elsewhere, set `MAC_VIDEOS_BUILD_DIR` to an absolute path. Tests are hostless and do not request screen, camera or microphone access.

Before relying on a walkthrough, do this manual smoke test:

- Grant permissions; select the USB mic and camera; record 10 seconds while speaking. Drag the bubble, change size, hide/show it, switch to another app, and stop with ⇧⌘S.
- Open the MP4 in QuickTime and confirm sound, circular bubble, its moved location, and the absence of the control window. Check a screen-only recording, countdown cancellation, menu-bar start/stop and a second recording.
- Change to an external SSD folder; record again and reveal it in Finder. Reopen the app to confirm choices persist. Disconnect a selected device and confirm a clear error. Deny a permission and check the recovery instructions.

The build, unit checks and native launch/source-picker inspection have been verified during development. Actual capture, bubble compositing, AAC playback, global stopping and external-SSD recording need the permission-enabled manual smoke test above.

## Project

- `Sources/MacVideos/`: SwiftUI controls/menu, AppKit camera panel, AVFoundation discovery/preview, ScreenCaptureKit recording and Carbon global hotkey.
- `Sources/MacVideosCore/`: settings, device-selection rules, file naming and video dimensions.
- `Tests/`: non-UI XCTest checks.
- `MacVideos.xcodeproj`: checked-in Xcode project. `project.yml` is its XcodeGen source; only changing the project structure requires XcodeGen (`xcodegen generate`). Normal build/run needs only Xcode.
- `docs/youtube-setup.md`: one-time Google setup and upload instructions. **Move to YouTube** uploads a copy, asks for confirmation and keeps your MP4. Google client configuration and refresh tokens stay in macOS Keychain; no Google setup is bundled. Retry continues a retained resumable upload. **Unlisted: anyone with the link can watch.** No editing or trimming.
- `docs/youtube-upload-plan.md`: original design; `docs/plans/youtube-upload.md`: implementation decisions.

Built for fun and learning by GolferGeek.
