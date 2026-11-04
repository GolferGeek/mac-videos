# Saved recordings presentation

- Goal: a grouped recent-recordings list, five newest first, friendly titles, local duration/size/thumbnail, clear upload status and aligned actions. Done means native light/dark inspection and local checks, then authorized PR merge and installation.
- Files: YouTubeViews.swift (list and async local metadata), YouTubeModel.swift (date ordering), YouTube.swift (optional returned title metadata), existing YouTube tests, this plan. Capture, credential storage, signing and saved link identifiers/URLs remain unchanged.
- Approach: read local media asynchronously per visible row; use creation date for ordering/title with original recent order as missing-file fallback. Decode an optional title from upload responses; old saved links retain their date title without a network lookup. Prefer compact actions over wrapped rows; use the existing outer scroll view for Show all. No new persistence format or media cache.
- Risks: missing/disconnected files show explicit unavailable metadata; local thumbnails stay in memory. Optional title decoding must accept old link JSON. No auth, upload protocol, Keychain or network destination changes.
- Tests: old/new link decoding and exact URL/embed preservation, ordering and remember/reload behavior; full check.sh twice on final head; real app light/dark and menu/copy inspection. No uploads or capture needed for this UI change.
- Size: small native presentation update; no dependencies or project layout changes.
- Known turn-backs: no review-lessons catalog. All planning, implementation and review performed directly per Codex handoff instruction.
