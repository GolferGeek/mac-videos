# Notarized release review (2026-11-04)

Performed directly by Codex in code-steward and security roles, per the handoff's instruction to do Claude-only agent work directly. Verdict: CHANGES NEEDED before ready/merge/publication; draft preparation may be committed.

## Scope and threat model

Reviewed scripts/release.sh, scripts/check-release-keychain.sh, scripts/keychain-smoke.swift, Release.entitlements, ExportOptions.plist, project.yml/generated project/Info.plist and guides. A download recipient must receive a verified Developer ID app, not a development archive. Another local app must not read the app's Keychain group. Release tools must not expose or change real Google credentials, widen app access, or publish an unstapled ZIP.

## Findings and checks

- No blocking code/security finding identified in the reviewed preparation. Release-specific verification is still blocked: Developer ID export failed with errSecInternalComponent at framework signing. No notarization, stapling, Gatekeeper acceptance, download round trip or released-app Keychain test has passed yet. Do not mark ready, merge or publish until those pass.
- Corrected during review: exported frameworks omit Swift modules, so the probe now compiles against the matching archive's build-products modules and runs against the exported embedded framework. A failed-to-launch probe does not count as other-app denial; it must execute and return the expected synthetic Keychain failure. The probe explicitly requires the compiled data protection mode. Both architectures are checked before packaging.
- Release gets camera/audio-input plus the team-scoped Keychain group; no get-task-allow or disabled library validation is accepted. Hardened runtime and Developer ID authority are checked before submission; final ZIP is recreated after stapling. Private signing/notary material stays in Keychain/Xcode-managed storage. No secrets are arguments or repository content.
- Data protection uses an explicit access group and noninteractive LAContext. No file-Keychain migration or deletion occurs. Debug keeps signed-v2. New users have no Google client bundled and launch does not read Keychain. Existing users paste setup/sign in once. Core/capture/OAuth/upload source remains unchanged.
- Development-signed universal Release archive succeeded. The same synthetic helper with only the signing identity replaced by Apple Development passed provisioned create/update/relaunch/read/delete and denial of a different unentitled identity. This proves development provisioning, not Developer ID distribution. Native launch and empty Settings were inspected without password dialogs; no real setup was saved.
- Debug check.sh passed 29 tests; check-keychain.sh passed file-Keychain create/update/relaunch/delete/signed replacement and different-identity denial. History secret scan passed. Exact-head verification and PR verdicts will record remaining results.

## Security checklist

1. Authz/tenant routes: n/a, native local app; no route or tenant changes.
2. Privilege escalation: group scoped to this team/app; other-identity denial tested with a development profile. Developer ID runtime test pending.
3. Injection/SSRF/deserialization: numeric version/build validation; shell paths quoted; no new runtime network destinations. Fixed Apple notarization service only.
4. Secrets: no credentials read/exported; keychain profile referenced by name; synthetic service only in tests. History scan passed; staged diff scan recorded on PR.
5. Dependencies: none added; system frameworks/tools only, no lockfile audit applicable.
6. RLS/grants: n/a, no database.
7. Payments/ledger: n/a.
8. Rate limits: n/a, no new remote runtime endpoint; user runs release tool locally.
9. Audit logging: local signature/archive/notary evidence retained under ignored .build; no credential logging.
10. Sessions/CSRF/uploads/fail closed: app OAuth unchanged; release requires Accepted and validation before final download. No automatic publishing/installing. Real upload/playback and capture unverified in this run.

## To pass

Matt resolves local Developer ID private-key access; resume scripts/release.sh, verify the exported distribution profile/Keychain behavior and notarization/stapler/Gatekeeper, then rerun exact-head checks/review. Merge and publish the exact source only after those pass; install and verify the downloaded artifact. Do not publish the development archive.
