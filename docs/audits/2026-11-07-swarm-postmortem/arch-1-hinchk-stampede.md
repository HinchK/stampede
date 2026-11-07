# arch-1-hinchk-stampede — post-mortem account (2026-11-07)

## 1. My role and who instructed me
Seat `arch-1-hinchk-stampede` (Lead Architect & Implementation Engine). Instructions, last 24h: (a) standing brief `.herdr-swarm/briefs/arch.md` — "TDD MUST", "`make test` 100% green", single-ticket scope, bare `ARCH DONE` anchors; (b) three looper dispatches with 3-line preambles: #EHS-10 "Coached setup and saved brief", #EHS-STEP4 "worktree preservation… improvement gate", #MUX-NATIVE-1 "Targeted Sync Waits… Nonce Tracking"; (c) three looper handbacks: "suite is RED on the COMBINED tree" (×2), then "conflicts with the integration branch… The arbiter… never resolves conflicts"; (d) HinchK directly: "why f3b61a3 was filed under three ids… ask reviewer"; (e) this post-mortem via pm-hinchk-stampede.

## 2. What I did
All on branch `swarm/hinchk-stampede/arch-1-hinchk-stampede`: `68fba7d`+`452a47d` coached setup `[brief]` + toggle (#EHS-10); `b4dc3b2`+`2459ec1` `worktree_teardown` + 2-run gate (#EHS-STEP4); `1daa491`+`c00a899` nonce delivery + `pane wait-output` (#MUX-NATIVE-1); `f3b61a3` 18:17 doctor-suite env scrub; `d9a4bbd` 22:27 merge of integration `e1d09b9` (toggle schema reconciled to #EHS-STEP3's `[self_improvement]` table). Files: lib/{setup.py,config.sh,briefs.sh,worktree.sh,standby.sh,cli/stampede-setup.sh}, herdr-loop-swarm.sh, swarm.config.toml, 7 test suites. I also self-initiated 3 fresh-context review subagents (executing-plans skill), producing 5 Important fixes.

## 3. What failed or went wrong
- #EHS-10 @ 452a47d `integration_red`: 2 doctor checks failed in the gate, passed in my shell. Cause: gate runs inside a managed pane whose ambient `REPO_DIR` points doctor at the real seat ledger. Evidence: `.herdr-swarm/gate-logs/arbiter-EHS-10-452a47d.log`; reproduced byte-for-byte by exporting `REPO_DIR`.
- #EHS-STEP4 @ 2459ec1 `integration_red` (20:49): identical failure; the gate ran a stale record though the fix shipped 18:17 (`f3b61a3`). Log: `arbiter-EHS-STEP4-2459ec1.log`.
- #EHS-10 @ f3b61a3 `conflict` (02:23Z): `tests/test_setup.sh` vs #EHS-STEP3's table schema; auto-merge had silently produced a broken union (duplicate `config.sh` bindings).
- Post-restart near-miss: my merge commit initially captured the broken union (5 resolved files unstaged); caught by dirty-tree check, amended into `d9a4bbd`. No red gate resulted.

## 4. Work the human did not explicitly ask for
The dispatches traced to the EHS design doc (`docs/superpowers/specs/2026-11-06-simple-startup-and-milestone-closeout-design.md`, recorded as "HinchK accepted this handoff"), not to a direct human ask in-session. Beyond dispatch text, unprompted additions were mine: the fail-closed hardening from my review subagents, the nonce ledger file, the `--current` static gate, and my suggestion that looper "re-queue… at the supervisor's discretion", which produced three queue records at one sha and up to three identical gate runs of the same tree.

## 5. What I would delete, stop, or not have built
Delete: the improvement-gate ledger in lib/briefs.sh (no consumer ever wired); the duplicate self-improvement UX overlap my branch added before adopting STEP3's schema. Stop: per-ticket gating of one shared branch tip (gate the tree once); re-queuing stale records at a tip (my suggestion — it multiplied gate runs); dispatching three features to one seat in one day under a "simple" goal. Not have built: the coach phase's `[brief]` table before its consumer existed — speculative schema that later collided with STEP3's.

## 6. What stops the swarm recovering itself
- The arbiter "never resolves conflicts or rebases" — every conflict required me to hand-merge.
- Gate environment ≠ worker environment (ambient herdr vars); no automated step reproduces it, so env-sensitive tests pass locally and fail in-gate until an agent debugs by hand.
- The queue gates records, not tips: a fixed tree stays red while its stale record still gates.
- `make test` halts at the first failing suite — the gate never saw suites behind the doctor failure until I ran them manually.
- Unknown: why integration stalled overall; I only observed my own handbacks.
