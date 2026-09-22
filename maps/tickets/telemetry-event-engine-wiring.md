---
id: T-009-impl
title: "Telemetry Event Engine and Live Ops Streaming Wiring"
type: wayfinder:prototype
status: done
assignee: arch
prototype_asset: lib/telemetry.py,herdr-loop-swarm.sh,loop-bot-herd.sh
owns: lib/telemetry.py,herdr-loop-swarm.sh,loop-bot-herd.sh
parent: maps/universal-herdr-swarm.md
github_issue: 51
github_url: "https://github.com/HinchK/stampede/issues/51"
synced_at: "2026-09-22T03:50:13Z"
---

# Telemetry Event Engine and Live Ops Streaming Wiring (T-009-impl)

## Question

How should `lib/telemetry.py` be upgraded to enforce the standardized `domain.action` JSONL envelope in project-scoped `.herdr-swarm/traces/`, provide a column-clamped ANSI `stream` command for the Ops pane, and wire telemetry logging across `herdr-loop-swarm.sh` and `loop-bot-herd.sh`?

## Preamble

1. **Intended Outcome**: Upgrade `lib/telemetry.py` with project-scoped trace storage (`.herdr-swarm/traces/`), the standardized JSONL envelope, and an ANSI badge-formatting `stream` command; wire the Ops Anchor pane in `herdr-loop-swarm.sh` to stream traces in real time, and add structured event logging to launcher and supervisor.
2. **Explicit Done-Criteria**:
   - `lib/telemetry.py` supports:
     - `log <session_id> <event_type> [agent] [ticket_num] [json_payload] [--trace-dir <dir>]`: Appends standard envelope `{"timestamp": float, "iso": str, "session_id": str, "event_type": str, "agent": str|null, "ticket_num": int|null, "payload": dict}` to `<trace_dir>/<session_id>.jsonl`. Default `trace_dir` is `${PWD}/.herdr-swarm/traces`.
     - `stream <session_id> [trace_dir] [--once]`: Reads/tails the session trace file and formats each JSONL event into a single-line ANSI badge clamped to terminal width:
       `[HH:MM:SS] [BADGE] SEAT-NAME #TICKET Summary Details...`
       Badges: `[DISPATCH]` (Cyan), `[VERDICT:✓]` (Green), `[VERDICT:✗]` (Red), `[BREAKER:⚠]` (Yellow), `[LIFECYCLE]` (Blue), `[VERIFY:✓]` (Green).
       `--once` processes existing lines and exits (for testing and non-interactive replay).
   - `herdr-loop-swarm.sh`:
     - Rewires Ops Anchor pane to run `python3 -u "$LIB_DIR/telemetry.py" stream "$SESSION_ID" "$PWD/.herdr-swarm/traces"`.
     - Renames Ops Anchor pane to `telemetry-stream`.
     - Emits `swarm.lifecycle` event on seating completion and `suite.verdict` / `seat.verified` events.
   - `loop-bot-herd.sh`:
     - Emits `suite.verdict` events via `telemetry.py` into `.herdr-swarm/traces/` on every verdict evaluated.
   - Shellcheck on `herdr-loop-swarm.sh` and `loop-bot-herd.sh` passes cleanly with 0 warnings.
   - Python code passes syntax and execution test.
3. **Verification Step**:
   - Test logging an event:
     `python3 lib/telemetry.py log test-session swarm.lifecycle looper 100 '{"action":"test"}' --trace-dir .herdr-swarm/traces`
   - Test streaming the event:
     `python3 lib/telemetry.py stream test-session .herdr-swarm/traces --once | grep -E '\[LIFECYCLE\]'`
   - Clean up test trace file: `rm -f .herdr-swarm/traces/test-session.jsonl`
   - Run `shellcheck herdr-loop-swarm.sh loop-bot-herd.sh && echo "PASS: shellcheck"`
