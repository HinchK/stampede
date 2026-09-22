---
id: PUB-10
title: "Trust-tax telemetry schema: measured numbers, never modelled"
type: wayfinder:task
status: resolved
assignee: arch
owns: lib/telemetry.py,docs/findings/telemetry-schema.md
parent: maps/public-multi-provider.md
blocked_by: PUB-1
---

# PUB-10 — Trust-tax telemetry schema (Wave 11)

## 1. Intended Outcome

The telemetry envelope grows measured trust-tax fields: per-verdict gate
duration, re-verdict count per `(ticket)`, brief bytes delivered, and
provider-reported token/cost figures **when the CLI reports them**. The
schema document (`docs/findings/telemetry-schema.md`) specifies every
field, its type, and its absence semantics (`unreported`, never `0`,
never modelled).

## 2. Problem

The product's thesis is "don't take the agent's word for it", the docs
admit a trust tax exists (DOG-4), and the public-readiness map parks
"trust-tax instrumentation" as unspecified. Without these events the herd
cannot publish honest numbers about what supervision costs and buys — and
M3 (every claim traceable to an event) is unreachable.

## 3. Plan

- Envelope additions (all optional fields with absence semantics):
  `gate.duration_ms`, `verdict.attempt` (per ticket, derived from
  verdicts JSONL at emit time), `brief.bytes`, `usage.{tokens_in,
  tokens_out, cost}` — populated only from provider-reported data passed
  in by callers; `lib/telemetry.py` never invents values.
- Emit points: supervisor verdict path (duration, attempt), brief
  delivery (bytes), seating (fallback — PUB-6's event joins the schema).
- Schema doc: one table per event family, field types, absence rules,
  and the standing rule that modelled numbers may not be emitted.
- Verification stays honest: this repo has no `tests/test_telemetry.sh`
  today, so the ticket adds a scratch-repo round-trip check inside
  `tests/` only if it can stay hermetic; otherwise the receipt is the
  `log`→`stream` round-trip documented in the ticket body.

## 4. Explicit Done-Criteria

- Round-trip: every new field emitted by `log` reappears identically in
  `stream` output.
- Absence semantics tested/observed: missing usage emits nothing for the
  sub-object, not zeros.
- `py_compile` clean under the DOG-1 interpreter resolver; schema doc
  matches implementation field-for-field.

## 5. Verification Step

```bash
"$(bash lib/pyenv.sh)" -m py_compile lib/telemetry.py
python3 lib/telemetry.py log s1 verdict.green arch T-1 '{"gate.duration_ms":4200,"verdict.attempt":2}' --trace-dir /tmp/tt && python3 lib/telemetry.py stream s1 /tmp/tt
make check
```
