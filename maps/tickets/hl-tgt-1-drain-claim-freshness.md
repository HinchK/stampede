---
id: HL-TGT-1
title: "Fix the stale operator-invoked drain claim in docs/dogfood/public-readiness.md"
status: done
owns: docs/dogfood/public-readiness.md
---

# HL-TGT-1 — drain-claim freshness fix

Headless proof target for HORIZON-2 (see docs/findings/headless-live-proof.md).

## Outcome

The headless dispatch of this ticket dead-lettered (worker killed by the stale
provider id in `.opencode/opencode.json` — the HORIZON-2 live finding), so the
fix landed through the normal interactive pipeline instead, per HORIZON-2's
step-9 cleanup: item 3 of the findings list now states that drain auto-runs
after enqueue (PROVE-4, HL-RED-1) and only promote is operator-invoked.
