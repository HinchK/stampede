---
id: T-007c-fix
title: "Strict Verdict Line Anchoring, Resume Mode Gate, and Verdict Log Hygiene (H1, M1, M2)"
type: wayfinder:prototype
status: resolved
assignee: arch
prototype_asset: loop-bot-herd.sh,herdr-loop-swarm.sh
parent: maps/universal-herdr-swarm.md
---

# Strict Verdict Line Anchoring, Resume Mode Gate, and Verdict Log Hygiene (T-007c-fix)

## Question

How should `loop-bot-herd.sh` and `herdr-loop-swarm.sh` resolve the findings in PM's M3 audit (`docs/audits/2026-09-19-m3-completion-audit.md`): anchoring the verdict regex strictly to prevent scrollback discussion/fixtures from being harvested as verdicts (H1), gating resume mode (`r`) against unrunnable test commands (M1), ensuring skipped verdicts do not automatically retire tickets (M2), and removing the dead `lib/agent_guard.sh` orphan?

## Preamble

1. **Intended Outcome**: Harden supervisor verdict harvesting in `loop-bot-herd.sh` with strict whole-line anchoring (`^[[:space:]]*ARCH DONE #[0-9]+[[:space:]]+[0-9a-fA-F]{7,40}[[:space:]]*$`), gate resume mode (`r`) in `herdr-loop-swarm.sh` fail-closed against unrunnable test commands, prevent `skipped` verdicts from retiring tickets, and purge test-fixture records (#99, #42).
2. **Explicit Done-Criteria**:
   - `loop-bot-herd.sh`:
     - Line harvest regex requires strict whole-line format: `^[[:space:]]*ARCH DONE #[0-9]+[[:space:]]+[0-9a-fA-F]{7,40}[[:space:]]*$`. Unanchored substrings in bash scripts or scrollback discussion are ignored.
     - When `TEST_CMD` is non-runnable or "skipped", supervisor logs `skipped` but does NOT report "filed verdict" to looper as an accepted completion; notifies operator that human evaluation is required.
     - Purges bogus records for tickets 99 and 42 from `~/.kultivait/loop-bot/session-verdicts.jsonl` and any local verdict ledger if present.
   - `herdr-loop-swarm.sh`:
     - Mode `r` (resume map) enforces `test_cmd_is_runnable "${TEST_CMD:-}"` fail-closed (exit 1), exactly matching mode `a`.
   - Remove orphan unused library `lib/agent_guard.sh` (superseded by `swarm_verify_seats` and preflight matrix).
   - Shellcheck on `loop-bot-herd.sh` and `herdr-loop-swarm.sh` passes cleanly with 0 warnings.
3. **Verification Step**:
   - Run:
     `out="Some code talking about ARCH DONE #99 aaa1111 in scrollback\nARCH DONE #123 4567890abcdef1234567890abcdef1234567890"`
     and verify only the whole-line verdict #123 is harvested, not #99.
   - Run `shellcheck loop-bot-herd.sh herdr-loop-swarm.sh && echo "PASS: clean shellcheck"`.
