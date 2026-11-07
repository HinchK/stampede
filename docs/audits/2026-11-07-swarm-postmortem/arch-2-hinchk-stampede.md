# Post-mortem — arch-2-hinchk-stampede (opencode, pane w1T:p6, worktree `.herdr-swarm/worktrees/arch-2-hinchk-stampede`)

## 1. My role and who instructed me
- Seat: architect. Standing brief (`briefs/arch-frontier.md`): "implement one assigned ticket at a time", "Never write to the base checkout", "Do not run arbiter drain, promote, push".
- Instructions inside my context: (a) "/herdr register yourself as arch-2" — first prompt in my pane, sender unknown to me; (b) this post-mortem request (HinchK, relayed by pm-hinchk-stampede).
- Context boundary: my session begins at (a). Section 2 is reconstructed from git log, `.herdr-swarm/integration.jsonl` and `gate-logs/`, not memory. Who assigned those tickets: unknown (predates my context). All commits carry the human's shared git identity; seat attribution comes from integration.jsonl.

## 2. What I did (branch `swarm/hinchk-stampede/arch-2-hinchk-stampede`, all 2026-11-06 −0800)
- 07:19 `31d5e7a` test: pin REPO_DIR in doctor suite (#QUOTA-5)
- 12:04 `d31721a` looper ambient test (audit #1); 12:04 `84c0ed5` fix arbiter queue numeric-vs-string rows (#ARB-NUM); 12:06 `5082818` docs: define evolving-harness swarm design
- 16:06 `73dfe74`/`aecfe12` docs: EHS-10 decisions + handoff; 16:33 `65a21da` feat supervisor reattachment / model-catalog honesty (#EHS-STEP2)
- 17:17 `4742789` feat milestone closeout + Four-T scorecard (#EHS-STEP3); 17:44 `72419b1` feat zero-test-deletion pre-gate + circuit breakers (#HARNESS-HARDEN-1)
- 18:04 `e1d09b9` fix frontier-launch gate substring match (#EHS-STEP2 #EHS-STEP3). Queue: STEP2 red 16:46, STEP3 red 17:23, HARDEN red 17:50; STEP2+3 integrated 18:19 (merge_sha `e1d09b9`).

## 3. What failed or went wrong
- Five tickets went `integration_red` against base `d9c71c3` in ~65 min: EHS-STEP2 16:46 (arch-2), EHS-10 16:55 (arch-1), EHS-STEP3 17:23 (arch-2), EHS-STEP4 17:31 (arch-1), HARNESS-HARDEN-1 17:50 (arch-2) — `integration.jsonl`. The drain promoted nothing 16:46→18:19.
- `gate-logs/arbiter-EHS-STEP2-65a21da.log`: prior suite ends "53 passed, 0 failed", then `tests/test_frontier_launch.sh` AssertionError — the "not any arbiter in any herdr call" invariant substring-matched the gate worktree's own path (`…/worktrees/arbiter-stampede/lib/telemetry.py`). Combined trees were guaranteed red while branch checkouts stayed green (root cause per `e1d09b9` message, which attributes STEP2 and STEP3 to it; the STEP4/HARDEN gate logs exist but I did not read them).
- `gate-logs/arbiter-EHS-10-452a47d.log`: `tests/test_cli_doctor.sh` "29 passed, 2 failed" ("explain line", "explain log"). EHS-10 is docs-only and failed on tests it never touched. Cause: unknown.
- 18:23 EHS-10 re-attempt ended status `conflict`, files `["tests/test_setup.sh"]`; unresolved at post-mortem time; cause: unknown.
- Earlier drain bug (#ARB-NUM, fixed in `84c0ed5`): queue transitions "silently no-opped", "one empty merge commit per pass".

## 4. Work the human did not explicitly ask for
- HARNESS-HARDEN-1 (zero-test-deletion pre-gate, deterministic circuit breakers): no ticket file exists; grep finds only CHANGELOG.md:14 and the commit. Proposer: unknown.
- EHS-STEP3 Four-T scorecard closeout: recorded in `maps/evolving-harness-swarm/map.md` as "directed by HinchK on 2026-11-06" — directed, but meta-machinery.
- The pile itself: ~140 ticket files in `maps/tickets` plus a parallel 13-issue EHS map, findings, prototypes. The same map records the human's same-day redirect — "Scope redirected by HinchK on 2026-11-06", "Simplicity reaffirmed" — yet STEP2/3/4 and HARDEN-1 were built that same afternoon.

## 5. What I would delete, stop, or not have built
- Delete: HARNESS-HARDEN-1's pre-gates and circuit breakers; the Four-T scorecard; the parallel EHS tracker (two intake systems for one repo).
- Fix by deletion: the frontier-launch invariant asserting path substrings — fixed in `e1d09b9`, but it should assert behavior, not checkout path names.
- Stop: seats committing new tickets while the drain is red — STEP3, STEP4 and HARDEN-1 were all committed after STEP2 went red at 16:46.
- Not have built: most of `maps/tickets` — telemetry, quota probing, trust-tax, reviewer quorum, headless runs — none of it was "make Stampede simple".

## 6. What stops the swarm recovering itself
- The gate guaranteed red for every combined tree, so no ticket could promote until a seat hand-diagnosed the gate's own environment (`e1d09b9`, 18:04). Nothing flagged "the gate itself is broken"; each red looked like a ticket failure and spawned per-ticket repair loops.
- Intake never paused while the drain was broken: four more tickets were committed and gated red after the first red.
- EHS-10 sits in `conflict` with nothing re-queueing it; a human must triage.
- Seat resets lose all context: my session began with a manual `/herdr register yourself as arch-2`; I have no memory of my predecessor's instructions and had to reconstruct this account from logs by hand.
