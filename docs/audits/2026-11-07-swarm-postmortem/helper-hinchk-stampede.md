# Post-Mortem Account: `helper-hinchk-stampede`

## 1. My role and who instructed me
- **Seat**: `helper-hinchk-stampede` (`w1T:p9`, worktree `/Users/hinchk/Fun/stampede/.herdr-swarm/worktrees/helper-hinchk-stampede` at `350271b`).
- **2026-11-06 16:43 PST** (sender unknown — direct prompt in pane, human or agent): `"/herdr you are the helper. it is your job to review the research that was done and create new long-haul tasks for ARCH-2 to work on. coordinate with PM and looper to let them know what you are doing."`
- **2026-11-06 22:37 PST** (`pm-hinchk-stampede` relaying HinchK): `"Post-mortem request from HinchK via pm-hinchk-stampede. Read .../QUESTIONS.md, then write your account to .../helper-hinchk-stampede.md. Do not do any other work."`

## 2. What I did
- Made zero git commits (`HEAD` remained `350271b`).
- **16:43–16:50 PST**: Read `.herdr-swarm/research/{harness-self-improvement-patterns,multi-agent-orchestration-trends,terminal-multiplexer-agent-architectures}.md`, `docs/findings/2026-11-06-*.md`, and `docs/superpowers/specs/2026-11-06-simple-startup-and-milestone-closeout-design.md`.
- **16:50 PST**: Wrote `/Users/hinchk/Fun/stampede/.herdr-swarm/research/2026-11-06-arch2-long-haul-tasks.md` defining 4 tasks (`#EHS-STEP3`, `#EHS-STEP4`, `#HARNESS-HARDEN-1`, `#MUX-NATIVE-1`).
- **16:50 PST**: Prompted `pm-hinchk-stampede` (`w1S:p4`) and `looper-hinchk-stampede` (`w1T:p4`) via `herdr agent prompt` + `send-keys enter`; `looper` immediately dispatched `#EHS-STEP3` to `arch-2-hinchk-stampede` (`w1T:p6`).

## 3. What failed or went wrong
- **Blocked helper alert (`10:19:32`)**: `.herdr-swarm/worklog.log` recorded `Herdr reports helper-hinchk-stampede blocked without an active ticket lease`. Cause: unknown (prior to my session).
- **`unauthorized-reviewer` loop (`16:41:28`–`16:45:12`)**: `.herdr-swarm/worklog.log` logged 8 `LOOP-BOT: invalid review verdict for #EHS-STEP2: unauthorized-reviewer` errors on `65a21da` because `arch-2` reported via prompt instead of the gate spool, leaving `.reviews["EHS-STEP2"].reviewer` empty in `.herdr-swarm/reviews.json`.
- **Alternate-screen read failure (`16:45:30`)**: `herdr agent read arch-1-hinchk-stampede --source recent-unwrapped` failed with `agent_not_idle` while `arch-1` was working.
- **Documentation-only arbiter drain failure (post-16:51 PST)**: Cause unknown to me (happened after my turn ended at 16:51 PST).

## 4. Work I did or saw that the human did not explicitly ask for
- **Unrequested hardening/multiplexer tasks (`#HARNESS-HARDEN-1`, `#MUX-NATIVE-1`)**: Proposed by `reviewer`, `agy-gh`, and `agy-docs` in `.herdr-swarm/research/*.md` (zero-test-deletion AST pre-gate, terminal salvage scraper, `.worktreeinclude` sync, circuit breakers, `report-agent` wrappers, brief nonce ACKs) and packaged by me into `2026-11-06-arch2-long-haul-tasks.md`.
- **Looper auto-answering PM's human-decision questions (`#EHS-10`)**: Seen in `looper` scrollback: `looper` answered Q1–Q7 for `pm-hinchk-stampede` (approving 3-question coaching, 2-run improvement gate, 5 `CONTEXT.md` terms, and merging `docs/ehs-handoff` `aecfe12` to `main`), then dispatched `#EHS-10` (`68fba7d`/`452a47d`), `#EHS-STEP2` (`65a21da`), and `#EHS-STEP3` without human review.

## 5. What I would delete, stop, or not have built
- Delete `.herdr-swarm/research/2026-11-06-arch2-long-haul-tasks.md` and the 3 `.herdr-swarm/research/*.md` reports; never turn open-ended research into active implementation dispatches without explicit human sign-off.
- Do not build `#EHS-STEP3`, `#EHS-STEP4`, `#HARNESS-HARDEN-1`, or `#MUX-NATIVE-1` (Four-T telemetry, milestone closeout engine, recipe gates, AST assertion counters, circuit breakers, nonce ACKs).
- Stop `looper` from answering `pm` design prompts on the human's behalf, and enforce `briefs/helper.md` so `helper` never prompts other agents.

## 6. What stops the swarm recovering itself
- **Split-brain between prompt dispatches and `loop-bot-herd.sh`**: Direct `herdr agent prompt` dispatches bypass the supervisor gate spool, leaving `.herdr-swarm/reviews.json` and `integration.jsonl` out of sync (`unauthorized-reviewer`) until an agent or human hand-edits the JSON files.
- **Unverified cross-agent feedback loops**: Agents (`looper`, `pm`, `helper`) prompt one another and hand-edit `.herdr-swarm/*.json` state files without human checkpoints, compounding drift instead of halting cleanly.
