---
id: T-015b
title: "Comprehensive README and User Guide Polish"
type: wayfinder:prototype
status: resolved
assignee: agy-docs
prototype_asset: README.md
owns: README.md
parent: maps/universal-herdr-swarm.md
resolution:
  commit: pending
  verified_by: looper
  date: "2026-09-19"
github_issue: 41
github_url: "https://github.com/HinchK/stampede/issues/41"
synced_at: "2026-09-22T03:50:13Z"
---

# Comprehensive README and User Guide Polish (T-015b)

## Question

How should `README.md` be updated to reflect the full, shipped, modular Universal Herdr Swarm architecture, documenting the lifecycle subcommands (`up`, `down`, `status`, `verify`), the seat verification readiness gate, the live telemetry engine, and references to the ADR repository and system vocabulary?

## Preamble

1. **Intended Outcome**: Polish and update `README.md` to document the shipped capabilities: CLI subcommands (`up`, `down`, `status`, `verify`), the 9-point preflight matrix, post-seating readiness verification, live ANSI telemetry streaming in the Ops pane, links to `CONTEXT.md` and `docs/adr/`, and accurate repository structure.
2. **Explicit Done-Criteria**:
   - Updates CLI section to document all subcommands:
     - `up [dir] [FLAGS]`: Launch or re-attach the swarm
     - `status [dir]`: Inspect workspace, seats, profile, and recent trace events
     - `down [dir] [-y|--yes] [--keep-ws]`: Non-destructive selective seat teardown
     - `verify [dir] [timeout_ms]`: Seat readiness & brief acknowledgment gate
   - Updates architecture diagram / text to show the Ops Anchor pane streaming real-time JSONL telemetry badges via `lib/telemetry.py`.
   - Documents the seat verification protocol (`swarm_verify_seats`) and fail-closed guarantees.
   - Adds links to `CONTEXT.md` (System Vocabulary) and `docs/adr/` (Architecture Decision Records 0001–0005).
   - Updates repository tree listing `docs/adr/`, `CONTEXT.md`, and `lib/telemetry.py`.
   - Markdown formatting is clean, with valid links and Mermaid diagrams.
   - Committed with message referencing `(#T-015b)`.
3. **Verification Step**: Run `grep -E 'verify|status|down|telemetry\.py|CONTEXT\.md' README.md && echo "PASS: README documentation complete"`.

## Verification Log

- Shipped complete lifecycle subcommands reference (`up`, `status`, `down`, `verify`) in `README.md`.
- Updated Mermaid topology to replace `process.log` with `telemetry-stream (lib/telemetry.py)`.
- Documented `swarm_verify_seats` readiness verification gate and fail-closed guarantees.
- Linked system vocabulary (`CONTEXT.md`) and Architecture Decision Records (`docs/adr/0001`–`0005`).
- Updated repository structure tree to reflect `docs/adr/`, `CONTEXT.md`, `lib/telemetry.py`, and maps.
- Verified with `grep -E 'verify|status|down|telemetry\.py|CONTEXT\.md' README.md`.
