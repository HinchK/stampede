# HANDOFF — audit must-fix 1 to 5

**Goal:** fix findings 1 to 5 of the 2026-10-09 ponytail audit (second, merged report).
**Branch:** `fix/audit-must-fix-1-5` (off `main` @ 8636b62). Not pushed. Nothing merges to `main` without the human.

## Tasks

- [x] 1. Arbiter must not gate a stale worktree (`lib/arbiter.sh` `_arb_worktree` + both callers; test in `tests/test_arbiter.sh`)
- [x] 2. Green-retire rule must let a re-verdict through after a review BLOCK or an arbiter hand-back (`loop-bot-herd.sh` `harvest_verdicts`; test in `tests/test_async_gate.sh`)
- [x] 3. Seat names: `looper_notice` and `ARCH_NAME` (`loop-bot-herd.sh:708`, `lib/briefs.sh:79`, `lib/standby.sh:97`)
- [x] 4. `CLI_DIR` unbound when no directory is passed (`herdr-loop-swarm.sh:84`)
- [ ] 5. `substitute_template` pastes values into Python source (`lib/briefs.sh:20-42`; test in `tests/test_briefs.sh`)
- [ ] 6. `make check`, report real counts

**Current task:** 5

**Next action if interrupted:** run the suite of the last ticked task, then continue at the first unticked box. One commit per task, exact paths only (`docs/findings/open-source-landscape.md` is someone else's untracked file — never `git add -A`).

## Notes

- Fix 2 makes a re-verdict after `conflict` / `integration_red` possible, but the worker is still never told about those (audit finding 9, not in this branch).
- Rendered briefs under `.herdr-swarm/briefs/` stay stale until the next `up`.
