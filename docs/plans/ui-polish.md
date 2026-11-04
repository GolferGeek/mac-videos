# Main window polish plan

- Goal: aligned, native settings and a centered recording action; complete when light/dark native screenshots, local checks, merged PR and installed app are verified.
- Files: Sources/MacVideos/MacVideosApp.swift only for product changes; this plan records scope. No recorder, device, bubble, save logic or project changes.
- Approach: grouped cards with consistent two-column grids, right-aligned 100-point labels and equal-width controls. Keep native semantic colors, sentence case and wrapping paths. A grouped Form was considered, but explicit grids provide predictable alignment across sections.
- Risks: clipping in long device names, folders and error states; inspect native layout and retain help text/full paths. No new permissions, auth, data access, network or production services.
- Tests: scripts/check.sh before PR and on exact head before merge; launch and inspect light/dark layout and source/folder controls without starting capture. Actual recording is outside this layout-only change.
- Size: one UI file, small local change. No review-lessons catalog exists. Implementation and review performed directly in Codex per user instruction.
