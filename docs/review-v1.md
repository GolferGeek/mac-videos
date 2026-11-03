# Version 1 self-review

Reviewed directly by Codex as the orchestrator, per the handoff's instruction to do Claude-only agent/skill work directly. No independent reviewer or subagent was used.

## Scope and correctness

Compared all source, tests, project configuration and documentation against the brief. Verified the new project targets macOS 27 and Swift 6, ships no dependencies/services/Actions, and keeps the main checkout untouched. The control UI/source pickers were launched and inspected through native computer use; final layout wraps its instructions without truncation.

Checked display filtering: exclude this process's application with exactly the camera panel as a window exception. Startup refuses to capture if it cannot locate that filter exception. Camera preview and window positions are left to the compositor so dragging/hiding is reflected in the selected display. The screen-only start does not request camera access. When enabled at start the camera session remains ready while hidden; a screen-only start cannot enable an unprepared camera mid-recording.

Checked lifecycle: countdown cancellation releases resources, device/display changes stop recording, callbacks ignore other stream/output identities, and startup/finalization have watchdogs. Stop installs its completion waiter before asking ScreenCaptureKit to finish. An already-ended output does not wait for a second completion. A stale asynchronous stop failure cannot resolve another run's waiter. Saved-file success requires a finalization callback, positive duration, video and AAC audio. Errors preserve any partial file for inspection and do not mark it saved. Quit is blocked while a run is active.

Checked source IDs/preferences and filenames: fallback to a connected/default device, preserve distinct devices sharing a name, UTC/local filename formatting independent of locale, unique UUID suffix, explicit folder selection, and missing external-volume protection.

## Privacy / local data access

Reviewed camera, microphone and screen permission gates, usage strings and System Settings recovery links. Checked the **built** app's Info.plist, not only build settings. Added a packaging check so required strings and external/Continuity camera opt-ins cannot silently disappear. No grants were changed during verification.

No networking, authentication, credentials, upload, telemetry, production access or shared database exists in v1. The app writes only its selected local recording folder and normal UserDefaults preferences. It is intentionally a non-sandboxed, ad hoc signed local build; it has no distribution/notarization claim. The upload document is a future plan, with PKCE/state, Keychain and explicit upload consent requirements, no actual credential material.

## Findings corrected before commit

- Fixed an async authorization expression that could not compile, removed deprecated audio discovery and Swift concurrency warnings, and enabled Swift 6.
- Moved privacy metadata to an explicit Info.plist after checking the built product showed that arbitrary generated INFOPLIST_KEY settings had been omitted. Corrected the AVFoundation camera opt-in key names against the installed SDK header.
- Fixed output-failure/finalization races, added timeouts, and guarded late stop errors by recording run ID.
- Wrapped the bubble instruction text after inspecting its truncated first layout.

## Verdict and limits

APPROVED for the local v1 implementation, subject to the documented manual capture check. Build, six unit tests, packaging/signature checks and native launch/source-picker inspection cover the implemented checks. No critical/high finding remains in this source/privacy self-review.

Actual screen capture, camera compositing and movement, USB mic audio, AAC playback, global shortcut stopping, permission-denial recovery and external SSD writes are **not verified**: those need Matt's interactive permissions/hardware smoke test in README.md and docs/matt-queue.md. Compile/unit success must not be described as proof of those behaviors. YouTube upload remains deliberately unimplemented.
