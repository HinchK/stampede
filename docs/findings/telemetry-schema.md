# Telemetry Event Schema

The trust ledger of the swarm: every event a stranger would need in order
to audit what the herd claimed, measured, and merged. Emitted as JSONL to
`.herdr-swarm/traces/<session>.jsonl` by `lib/telemetry.py`; rendered as
one-line ANSI badges by `stampede`'s Ops pane (`stream`).

Standing rule (from the DOG-4 lesson): **measured numbers only.** A field
that nobody measured is absent, never `0`, never modelled. Absence IS
information: `usage` missing means the provider CLI reported nothing.

## Envelope

| Field | Type | Notes |
|---|---|---|
| `timestamp` | float | epoch seconds |
| `iso` | string | `YYYY-MM-DDTHH:MM:SSZ` |
| `session_id` | string | stable per project (minted once, shared by launcher + supervisor) |
| `event_type` | string | `domain.action` vocabulary below |
| `agent` | string or null | seat the event is about |
| `ticket_num` | string or null | ticket id **verbatim** — `DEMO-1`, `PUB-10`, `23`. Never coerced to int; never dropped (PUB-10 / ARB-STR) |
| `payload` | object | event-specific fields below |

## Event vocabulary

### Lifecycle (launcher)

- `swarm.lifecycle` — payload: `action`, `mode`, `slug`, `repo`, `seats`, `summary`
- `seat.fallback` (PUB-6) — a seat seated on a non-primary provider.
  Payload: `seat`, `wanted` (primary kind), `used` (seated kind), `summary`.

### Dispatch / verdict / gate (supervisor)

- `swarm.dispatch` — payload: `ticket`, `seat`, `summary`
- `suite.verdict` — payload: `ticket`, `sha`, `suite` (`green`|`red`|`skipped`),
  `summary`, and **measured** trust-tax fields when available:
  - `gate.duration_ms` — wall-clock of the supervisor's own suite run
    (integer ms). Absent when the gate never ran (skipped/invalidated).
  - `verdict.attempt` — 1-based count of verdicts recorded for this
    ticket so far this session (re-verdicts included). Derived from the
    verdicts JSONL at emit time — a count, never a guess.

### Quota (PUB-9)

- `quota.probe` — payload: `kind`, `status` (`ok`|`unknown`|`error`),
  `detail`, `summary`. Emitted once per probed provider per `stampede quota`
  run. `unknown` means the provider exposes nothing probeable — it is not
  an error and is never reported as zero.

### Briefs

- `brief.deliver` — payload: `seat`, `brief.bytes` (integer, size of the
  rendered standing brief actually delivered), `summary`.

## Optional measurement fields (any payload)

- `usage` — object; sub-fields `tokens_in`, `tokens_out`, `cost` — only
  when a provider CLI or API reported them verbatim. Absent = unreported.
- `duration_ms` — integer; only for an operation this code timed itself.

## Absence semantics (normative)

1. Missing `usage` ≠ zero cost. Renderers must not default it.
2. Missing `gate.duration_ms` means no gate ran — do not average over it.
3. `ticket_num: null` means no ticket context — it never means "ticket
   unknown so drop the id".
4. Counting re-verdicts: count `suite.verdict` events for a ticket;
   `verdict.attempt` is that count at emit time.
