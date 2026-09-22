# Telemetry Event Schema and Live Ops Streaming — Research Findings (T-009)

**Date:** 2026-09-19  
**Source Analysis:** `lib/telemetry.py`, `lib/agent_guard.sh`, `herdr-loop-swarm.sh`, `loop-bot-herd.sh`, `swarm.config.toml`  
**Resolves Ticket:** [Telemetry Event Schema and Live Ops Streaming](../../maps/tickets/telemetry-event-schema-and-live-ops-streaming.md)

---

## 1. Existing Telemetry Schema & Disconnections

### Current `telemetry.py` Contract
Appends single-line JSON entries to `~/.herdr-loop-swarm/traces/{session_id}.jsonl`:
- `timestamp`: Epoch seconds (float)
- `iso`: UTC ISO-8601 string (`YYYY-MM-DDTHH:MM:SSZ`)
- `event_type`: String tag
- `agent`: Agent seat identifier (or null)
- `ticket_num`: Numeric ticket integer (or null)
- `payload`: Arbitrary JSON dictionary

### Root Causes of Disconnection
1. **Launcher Inaction (`herdr-loop-swarm.sh`)**: Creates `$SESSION_ID` and displays the traces path, but never calls `telemetry.py` during workspace setup, seat allocation, or mode dispatch.
2. **Supervisor Bypass (`loop-bot-herd.sh`)**: Bypasses `telemetry.py` entirely, maintaining an ad-hoc, flat JSON file at `$HOME/.kultivait/loop-bot/session-verdicts.jsonl` with conflicting field names (`ts`, `ticket`, `seat`, `suite`).
3. **Guard Silence (`lib/agent_guard.sh`)**: `wait_agent_with_circuit_breaker()` only prints ANSI to stdout on timeouts/blocked states; it accepts no session context and calls no logger.
4. **Ops Log Pane Miswiring**: Launcher runs `tail -n 40 -f /tmp/herdr-process.log`, a file that nothing in the codebase writes to.
5. **Global Path Pollution**: Traces write to user-global `~/.herdr-loop-swarm/traces/` rather than project-scoped `.herdr-swarm/traces/`.

---

## 2. Standardized JSONL Event Contract

All events follow a common envelope:
```json
{
  "timestamp": 1726748263.123,
  "iso": "2026-09-19T12:17:43Z",
  "session_id": "swarm-20260919-051800",
  "event_type": "domain.action",
  "agent": "arch-kultivait",
  "ticket_num": 104,
  "payload": {}
}
```

### Event Domain Specifications
1. **`agent.dispatch`**:
   - `sender`: `"looper"` | `"supervisor"` | `"launcher"`
   - `ticket_id`: String identifier (e.g. `"T-009"`, `"#104"`)
   - `brief_path`: Relative path to brief/spec file
   - `channel_file`: Path to file-based nonce response channel
   - `prompt_summary`: 1-line summary of intended outcome
   - `mode`: `"wayfinder"` | `"brainstorm"` | `"drain"` | `"auto_queue"`

2. **`suite.verdict`**:
   - `verdict`: `"green"` | `"red"` | `"skipped"`
   - `test_cmd`: Executed test runner command
   - `exit_code`: Process exit code (0, 1, 124)
   - `duration_s`: Test execution runtime in seconds
   - `raw_verdict_line`: Unwrapped verdict text from worker pane
   - `summary`: Truncated test runner summary (`28 passed in 4.15s`)
   - `action`: `"accepted"` | `"rejected"` | `"bypassed"`

3. **`guard.circuit_breaker`**:
   - `reason`: `"timeout"` | `"blocked"` | `"stall"` | `"missing"`
   - `timeout_s`: Configured timeout threshold in seconds
   - `elapsed_s`: Actual elapsed seconds before trip
   - `last_status`: Raw Herdr agent status
   - `diagnostics`: Sanitized 1-line snippet from terminal output
   - `action`: `"alert_human"` | `"nudge"` | `"respawn"`

---

## 3. Ops Log Pane Real-Time Streaming Specification

To eliminate terminal clutter and line wrapping in standard 80-column split panes:
- Extend `lib/telemetry.py` with a `stream` command:
  ```bash
  python3 -u lib/telemetry.py stream <session_id> [trace_dir]
  ```
- Formats each JSONL event into a single, column-clamped ANSI badge line:
  `[HH:MM:SS] [BADGE] SEAT-NAME #TICKET  Summary Details...`

| Event Type | Badge | Color | Example Line |
|---|---|---|---|
| `agent.dispatch` | `[DISPATCH]` | Cyan | `[12:17:43] [DISPATCH]  arch-kultivait #104  T-007a: Fix supervisor deduplication` |
| `suite.verdict` (green) | `[VERDICT:✓]` | Bold Green | `[12:18:35] [VERDICT:✓] arch-kultivait #104  GREEN (28 passed in 4.15s)` |
| `suite.verdict` (red) | `[VERDICT:✗]` | Bold Red | `[12:18:50] [VERDICT:✗] arch-kultivait #104  RED (pytest exit 1: 2 failed)` |
| `guard.circuit_breaker` | `[BREAKER:⚠]` | Yellow/Red | `[12:23:35] [BREAKER:⚠] arch-kultivait #104  TIMEOUT after 300s -> alert_human` |
| `swarm.lifecycle` | `[LIFECYCLE]` | Blue | `[12:15:00] [LIFECYCLE] launcher        -    Topology seated: herd & ops tabs` |

- Rewire `herdr-loop-swarm.sh` Ops Anchor pane:
  ```bash
  herdr pane rename "$OpsAnchor" "telemetry-stream"
  herdr pane run "$OpsAnchor" "python3 -u '$LIB_DIR/telemetry.py' stream '$SESSION_ID' '$TRACE_DIR'"
  ```
