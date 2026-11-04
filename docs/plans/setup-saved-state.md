# YouTube setup saved state

- Goal: Saving switches immediately to a clear saved summary; reopening shows it too. Done means native inspection of empty, saved, reopened and confirmed-change states.
- Files: YouTubeViews.swift, YouTubeModel.swift, existing core YouTube.swift and YouTubeTests.swift. No project layout changes or credential migrations.
- Approach: Track persisted configuration separately from editable drafts. Commit UI state only after persistence succeeds; hide fields and mask the identifier in the saved summary. Confirm deletion of client setup; require disconnect first when signed in or holding a pending upload. Keep Save disabled for blank drafts. Rejected merely renaming Save while leaving editable fields, because it leaves persistence ambiguous.
- Risks: Secrets/Keychain require security review. Existing production client, grant and pending items must not be mutated during verification. Offline preview bypasses Keychain entirely and uses in-memory writes/removals. No network actions in verification.
- Tests: Hostless tests with closures acting as a mock store prove save/delete success and failure, reopen, blank drafts, and masking. Full local check twice plus native layout inspection with offline fixtures; no recording/upload claims.
- Size: Small focused UI/model change. No new dependencies. No review-lessons file.
- Execution: Direct Codex implementation, architecture and security/self-review per user instruction; no Claude-only subagents.
