---
id: DOG-4
title: "Relabel the 80% token-reduction claim as design rationale, not measurement"
type: wayfinder:doc
status: in_progress
assignee: agy-docs
owns: docs/findings/swarm-orchestration-retrospective.md
parent: maps/public-readiness.md
github_issue: 6
github_url: "https://github.com/HinchK/stampede/issues/6"
synced_at: "2026-09-21T21:54:12Z"
---

# DOG-4 — Token claim honesty pass (WAVE 2)

## 1. Intended Outcome

The retrospective's token claims read as what they are — an architectural
argument — so the repo ships no measured-sounding number it cannot produce.

## 2. Problem

`docs/findings/swarm-orchestration-retrospective.md:62` is headed
"The 80%+ Token Reduction", and the table at `:185` contains
`| **Token Efficiency** | Poor (100k–200k tokens/turn) | **High (80%+ savings)** | ...`.

Verified:

```
$ cat .herdr-swarm/traces/*.jsonl | wc -l        → 0
$ grep -ic 'token|cost|usage' lib/telemetry.py   → 0
```

Zero trace events. Zero token/cost/usage fields in the telemetry schema. **No
token measurement has ever been taken in this repo.** The number is derived, not
observed.

It also conflates two quantities:

- **Context per turn** — genuinely reduced by fan-out (5k vs 120k), and it buys
  attention quality, which is what §3.1 actually cares about.
- **Total tokens per retired ticket** — *increased* by design: N workers, a
  supervisor re-running the full suite per verdict, re-verdict loops, the
  arbiter re-testing the combined tree, `pm` audits, an ADR per decision.

## 3. Scope

1. Retitle §3.1 to name the real mechanism, e.g. "Context Compaction: Why
   Per-Turn Context Shrinks". Keep the reasoning — it is sound.
2. Every "80%+" becomes explicitly modelled/expected, never measured. Table cell
   becomes `Modelled: high (per-turn context)`.
3. Add a short **"The trust tax"** subsection stating plainly that total spend
   goes *up*, and that this is the deliberate trade: correctness bought with
   compute.
4. Add one line noting per-seat token accounting is not obtainable today —
   Herdr drives vendor CLIs over a PTY that reports no usage.

Do **not** delete the analysis. The reasoning is good; only the epistemic status
of the number is wrong.

## 4. Done-Criteria

1. No occurrence of "80%" anywhere in the repo is presented as a measurement.
2. §3.1's heading no longer asserts a reduction figure.
3. A "trust tax" subsection exists and says total spend increases.
4. The PTY/no-usage-reporting limitation is stated once.
5. Only this file is modified.

## 5. Verification Step

```bash
grep -rn '80%' docs/ README.md STATE.md maps/
# every surviving hit must sit beside the words modelled / expected / estimated

git diff --name-only HEAD~1   # want exactly the retrospective
```
