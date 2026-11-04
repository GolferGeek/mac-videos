# YouTube upload: direct code and security review

Reviewer: Codex, acting directly in code-steward and security roles as requested by the handoff. No independent subagent review is claimed. Scope: the complete feat/youtube-upload change against origin/main, including all new source, tests, docs, project spec and generated project.

## Code review — APPROVED

- Upload is an explicit action after account identity, metadata and audience selection. Missing configuration leads to setup. The original MP4 is opened read-only; no recording is moved or removed. Local links are remembered only after a final response confirms unlisted and embeddable status. Processing/playback is not claimed complete.
- Retry queries the retained session before sending bytes; a lost final response can resolve to the original video. Session state is saved before media transfer. Reauthentication requires the same account and retains the session. Cancel cannot unsend received bytes; the UI/docs explain this. An expired session requires checking Studio before deliberately forgetting it.
- Reviewed MainActor UI/model ownership, task cancellation, quit guard, Keychain failures and unchanged capture/finalization/window filter. Capture, camera queue and hotkey source files have no diff. Recording controls stay outside the scrolling settings/list area.
- Fixed during review: cached URL file metadata could miss changed recordings (regression test caught it); now fresh attributes are checked before retry and each chunk. Fixed retry after failed Keychain persistence, preserved session during reauthentication, and made setup guide clickable.
- Project spec explicitly links Security/CryptoKit/Network; XcodeGen regenerated the checked-in project. No dependencies, CI or services added.

## Security review — PASS

### Threat model

- Remote sites could forge OAuth callbacks: loopback-only listener, random 256-bit state, PKCE S256, exact callback path, single code/state fields and bounded 180-second lifetime prevent accepting an unsolicited grant. A local process can deny service to the temporary listener but cannot know state/verifier.
- A tampered API/session response could steal credentials or MP4 bytes: only HTTPS on www.googleapis.com:443 and the upload API path is allowed for session URLs; URLSession redirects are refused. Endpoint credentials are in POST bodies or Authorization headers, never query strings (apart from the public client ID in the browser authorization request).
- A user could upload to the wrong account or expose a video: verified Google userinfo email is shown before explicit confirmation; reconnect enforces the same account; audience is required; privacy and embedding are explicit and checked again in the returned video. Unlisted is explained as link-accessible.
- A local insider with access to the unlocked user session can access that user's files/Keychain subject to macOS controls; this desktop app does not promise protection from a compromised OS/account. No remote multi-user/admin surface exists.

### Findings

No open critical, high or medium findings in the reviewed scope. Playback, Google configuration, actual consent, Keychain prompts after an ad-hoc rebuild and real quota/channel behavior remain manual integration checks, not proven by mocks.

### Checklist

1. Authorization/tenant: local single-user app; no tenant/server routes. Only explicit sign-in/upload/disconnect actions make Google requests. Callback accepts only its in-flight state.
2. Privilege escalation: no roles/admin surface. Narrow youtube.upload plus openid/email identity; no silent broader YouTube read scope.
3. Injection/SSRF: fixed endpoints; upload URL scheme/host/port/path/userinfo/fragment allowlist; redirects denied. IDs are validated before building watch/embed links. No shell/HTML evaluation of user content.
4. Secrets/history/build/logs: client configuration, refresh grant/account and sensitive session live in Keychain with WhenUnlockedThisDeviceOnly accessibility. Short-lived access token is memory-only. Preferences contain paths and validated result IDs only. No logging or raw server errors. Gitleaks history, source, test, docs and generated local build scan: no leaks. Test strings are artificial, never issued credentials. Downloaded client JSON filename patterns ignored.
5. Dependencies/CVEs: no new third-party packages or lockfiles; system Apple frameworks only, so package audit is not applicable.
6. RLS/grants: not applicable; no database.
7. Ledger/payments: not applicable; no payments, billing setup or purchasing quota.
8. Rate limits: no public endpoint; bounded local listener connections/header size/lifetime, user-triggered uploads and no automatic retry loop. Quota errors stop and ask the user to wait.
9. Audit: no server/admin audit surface. No telemetry/token/request-body logs; deliberately keep the desktop user's account and recordings local.
10. Sessions/CSRF/uploads: random state, PKCE, fixed loopback redirect; refresh/revoke; local deletion reported separately from remote revocation failure. Size/modification checks and bounded 8 MiB reads. Fail closed on invalid final status, unexpected offsets or host. No automatic fresh upload after an ambiguous result.

## Verification

`./scripts/check.sh`: build, privacy metadata, strict local signature and all 20 hostless tests pass. Mocked tests cover PKCE vector, callback rejection, token exchange/refresh/email/revoke, expired sign-in, explicit privacy/audience, URL allowlist, partial retry, lost final response, bounded chunks, modified files, final status validation, errors and cancellation. Native app launch: inspected scrolling controls, confirmation and setup, saved three screenshots outside git using an offline fixture with sign-in/upload disabled. No Google resource, consent grant or video upload was made.

Exact PR head and second full-check results will be posted on the PR before merge. Real sign-in, refreshed-token reuse across app rebuild/relaunch, upload, unlisted playback and embedding need Matt's one-time setup and test recording.
