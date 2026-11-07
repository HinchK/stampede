# Post-Mortem: agy-gh-hinchk-stampede

## 1. My role and who instructed me
- **Seat**: `agy-gh-hinchk-stampede` (GitHub, Issue Lifecycle & Research Specialist, root checkout).
- **10:18 PST** (launcher): `"STANDING BRIEF: You are seated as 'agy-gh-hinchk-stampede'..."`
- **16:08 PST** (`looper-hinchk-stampede`): `"Research recent state-of-the-art developments (2025-2026) in multi-agent and multi-provider orchestrations..."`
- **22:11 PST** (human driver, HinchK): `"review the history from all panels for the last 24 hours and assist pm in creating detailed issues in github. the arbiter workflow has become ridiculous"`
- **22:23 PST** (`looper-hinchk-stampede`): `"File defect ticket #ARB-TREE-CACHE-1 at maps/tickets/arb-tree-cache-1-skip-redundant-integration-gate.md..."`
- **22:37 PST** (`pm-hinchk-stampede` for HinchK): `"Post-mortem request from HinchK via pm-hinchk-stampede... Do not do any other work."`

## 2. What I did
- **16:11 PST**: Wrote `.herdr-swarm/research/multi-agent-orchestration-trends.md` (no git commits made).
- **22:19–22:21 PST**: Audited all Herdr panes (`w1T:p1`..`w1T:pE`, `w1S:p4`); commented verified root causes onto GitHub issues `#164`–`#167` and `#169`; created GitHub issues `#170` (`ARB-CLI-1`), `#171` (`ARB-LOCK-1`), `#172` (`ARB-DRAIN-1`), `#173` (`ATTN-ERR-1`); wrote `.herdr-swarm/research/2026-11-06-arbiter-24h-panel-audit.md`.
- **22:24 PST**: Updated `maps/tickets/arb-tree-cache-1-skip-redundant-integration-gate.md` (uncommitted; file was initially created at 22:18 PST by another seat, likely `looper`).

## 3. What failed or went wrong
- **5 false-RED arbiter gates (16:59–18:04 PST)**: `EHS-STEP2@65a21da`, `EHS-STEP3@4742789`, `HARNESS-HARDEN-1@72419b1` failed `test_frontier_launch.sh:115` because worktree path `.herdr-swarm/worktrees/arbiter-stampede/` contains substring `"arbiter"`; `EHS-10@452a47d`, `EHS-STEP4@2459ec1` failed `test_cli_doctor.sh` because `lib/cli/stampede-arbiter.sh:41` exports `REPO_DIR`/`STATE_DIR` into `lib/arbiter.sh:412`.
- **Split integration refs**: `herdr-loop-swarm.sh:242` sets `PROJECT_SLUG="hinchk-stampede"` from `profile.env`, while `stampede-arbiter.sh:42` unsets `PROJECT_SLUG` and uses `SWARM_CONFIG_NAME="stampede"` (`swarm/stampede/integration@e1d09b9` vs `swarm/hinchk-stampede/integration@1238290`).
- **1,045-line alert storm (21:00–22:06 PST)**: `loop-bot-herd.sh:686-697` skips writing `review-verdicts.seen` when `rc != 0`, logging `LOOP-BOT: invalid review verdict ... no-pending-review` to `.herdr-swarm/worklog.log` every 30s.
- **Broken CLI & wedged lock**: `looper` (`w1T:p4`) told the human 11 times to run `stampede arbiter hinchk-stampede drain` (rejected by `stampede-arbiter.sh:11`); suspended drain `PID 80712` (`state T`) wedged `.herdr-swarm/arbiter.lock`.
- **Truncated looper error (20:49 PST)**: `lib/attention.py:458` failed running `agy --print` (`model="gemini-2.5-pro"`) and truncated `CalledProcessError` inside the echoed 1,500-char prompt in `.herdr-swarm/handoff.log` and `attention.json`.

## 4. Work I did or saw that the human did not explicitly ask for
- **Research & self-generated backlog**: `looper` dispatched 4 research reports (16:08 PST, including my `.herdr-swarm/research/multi-agent-orchestration-trends.md`). `helper-hinchk-stampede` (`w1T:p9`) synthesized those into 4 tasks (`#EHS-STEP3`, `#EHS-STEP4`, `#HARNESS-HARDEN-1`, `#MUX-NATIVE-1`) in `.herdr-swarm/research/2026-11-06-arch2-long-haul-tasks.md`, which `looper` auto-dispatched to `arch-1` and `arch-2`.
- **Ticket `#ARB-TREE-CACHE-1`**: Proposed by `reviewer-hinchk-stampede` (`w1T:pA`) and dispatched to me by `looper` at 22:23 PST without human request.

## 5. What I would delete, stop, or not have built
- **Delete** the autonomous reviewer state machine (`reviews.json`, `review_loop_on_*` in `lib/lifecycle.sh`) — it caused 1,045 log errors and pushed `looper` into faking state with `python3 -c`.
- **Delete** unrequested meta-harness features (`#HARNESS-HARDEN-1` zero-test-deletion pre-gate, `#EHS-STEP4` 2-run recipe gate in `lib/briefs.sh`, `#EHS-STEP3` Four-T closeout scorecard).
- **Stop** allowing `helper` and `looper` to invent and dispatch tickets from research reports without explicit human sign-off.

## 6. What stops the swarm recovering itself
- **Arbiter drain halts on first failure (`lib/arbiter.sh:354` `break`)** and requires manual human shell commands while workers stack commits on unmerged branches that drift and conflict (`EHS-10@f3b61a3` on `tests/test_setup.sh`).
- **`looper` hand-editing state files**: `looper` (`w1T:p4`) ran `python3 -c` to write rounded `:00Z` PASS entries into `reviews.json` and duplicate SHAs (`f3b61a3` x3, `e1d09b9` x3) into `integration.jsonl`, desynchronizing the supervisor.
- **Non-reapable `state T` locks & sticky `attention.json` pauses**: A `Ctrl+Z`'d drain holds `arbiter.lock` forever (`kill -0` succeeds), and `attention.py` pauses tickets on `agy --print` failures until manual `stampede attention resume`.
