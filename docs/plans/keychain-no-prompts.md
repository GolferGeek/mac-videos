# YouTube Keychain without password prompts

Goal: launch without Keychain access; Settings and upload preparation read only the app's data protection items. End-to-end proof: a provisioned signed app writes, reads, updates and deletes a disposable test-service item without touching real setup.

Files: YouTubeAccount.swift (store), YouTubeModel.swift (lazy load), YouTubeViews.swift (entry/copy), project.yml and generated project/entitlements (automatic team signing), scripts/check.sh, tests and setup/queue docs.

Approach: explicitly select data protection, a team-prefixed access group and device-only accessibility for every item. MainActor serializes synchronous Keychain calls; load one snapshot on first Settings/upload entry. Never migrate by reading legacy items. Leave legacy items untouched rather than risking an ACL prompt during cleanup. Never fall back to legacy reads. Automatic signing supplies the entitlement-authorizing profile; verify at runtime using a separate test service.

Risks: provisioning may need an Xcode account; fail closed rather than saving secrets outside Keychain. Existing Google setup and sign-in must be entered again. Focused security review required before merge. Recording and real Google upload remain permission/account-dependent.

Tests: query policy tests, local build/hostless suite twice (final SHA), signed native test-service round trip, native Settings layout inspection and installed signature/profile inspection. No real credentials in tests. Size: small multi-file change, no new dependency. No review-lessons catalog exists.

## Local provisioning outcome and shipped fallback

`xcodebuild ... -allowProvisioningUpdates CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development"` failed: the saved Xcode Apple account login was rejected and no matching Mac development profile exists. Existing local Mac profiles belong to other app IDs and cannot authorize this app. A `keychain-access-groups` entitlement without a matching profile is not a valid fix; do not ship it.

The brief explicitly permits the closest prompt-free option when provisioning cannot be done headlessly. The shipped local build retains manual Apple Development signing and uses only a fresh file-Keychain service (`.signed-v2`). Every operation runs synchronously on MainActor with process Keychain UI disabled and restored afterward. New items have an explicit ACL trusting only the signed executable, never all applications. This fallback does not offer data protection's device-only accessibility semantics; the file-based Keychain ignores those attributes. Keep the installed path and signing identity stable. Moving the app may cause a safe access error. No legacy cleanup is attempted because it cannot be guaranteed prompt-free. No runtime fallback or automatic migration reads old items.

Data protection implementation is included, but is not the installed mode. After the Xcode account is repaired, build with a fresh derived data directory and:

```sh
xcodebuild -project MacVideos.xcodeproj -scheme MacVideos -configuration Debug \
  -derivedDataPath .build-data-protection -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
  MAC_VIDEOS_KEYCHAIN_ENTITLEMENTS=Sources/MacVideos/MacVideos.entitlements \
  MAC_VIDEOS_KEYCHAIN_CONDITION=DATA_PROTECTION_KEYCHAIN build
```

Verify the app's embedded profile, team-prefixed access group and application identifier, then run a signed app-bundle synthetic-service round trip. Do not declare data protection working based only on compilation or `codesign` output. Switching modes requires re-pasting setup again; no secret migration is attempted. Hostless query-policy tests can exercise this mode with the compilation condition and signing disabled, but cannot prove provisioned runtime access.

Apple references: [TN3137: Mac keychains](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains), [TN3125: provisioning profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles), [data protection selector](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain). App group containers without provisioning do not substitute for Keychain access-group authorization.

## Release follow-up (2026-11-04)

Xcode account provisioning now succeeds for a Release development archive with the data protection access group. The v1.0.0 release branch selects data protection for Release and retains the existing Debug fallback. Developer ID export reached distribution signing, but codesign failed with `errSecInternalComponent` while signing the embedded framework. The Developer ID certificate is installed; private-key use still needs Matt's local Keychain authorization. The provisioned development archive passed synthetic data protection create/update/relaunch/read/delete and other-identity denial; native launch and empty Settings also worked without a password prompt. Distribution runtime access and notarization remain unverified until Developer ID signing succeeds. See [release procedure](../releasing.md); do not ship the development archive.
