# Stable local signing plan

- Goal: installed Debug/Release builds retain certificate-based identity across rebuilds; verify identical designated requirements, authority and team across two clean builds, then install merged main.
- Files: project.yml and regenerated Xcode project; scripts/check.sh signing gate; README.md and CODING.md signing guidance; docs/matt-queue.md recovery check. Preserve bundle ID and existing YouTube Keychain service/accounts. No credentials, privacy resets or Keychain deletions.
- Approach: manual signing with the existing Apple Development identity and team 227GEZ2676. Automatic provisioning adds unnecessary account/profile dependencies for this local unsandboxed Mac app. Retain the fixed generic-password service instead of introducing a new access group that could strand existing items.
- Risks: transition from ad hoc signing may require a one-time macOS permission repair and Google setup re-entry. Existing Keychain ACL migration and real capture require Matt; do not inspect secret values. Security review covers signing, Keychain scope and accidental secret exposure.
- Tests: full local check twice on exact PR head; clean Debug builds, Release build, strict signature verification and designated-requirement comparison; inspect installed app state before quitting, install merged build and launch. No UI layout changes.
- Size: small configuration/docs change. No review-lessons catalog exists. All roles performed directly in Codex as requested.

Certificate inspection: the current identity is valid May 2026–May 2027. Its subject OU (actual team) is 227GEZ2676; Q95DF7CUGG is part of its common name, not the team. The initially requested team fails Xcode certificate matching, so use the certificate’s actual team.
