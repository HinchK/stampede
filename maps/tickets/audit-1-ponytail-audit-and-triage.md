---
id: AUDIT-1
title: "Run a fresh ponytail audit and triage the findings (report committed in-repo)"
type: wayfinder:research
status: backlog
assignee: arch
owns: docs/audits/2026-11-08-ponytail-audit.md
parent: maps/repo-truth-pass.md
---

# AUDIT-1 -- fresh whole-repo ponytail audit, committed in-repo, triaged

## Intended Outcome

A fresh whole-repo quality audit runs on the post-incident tree and lands as a committed,
dated report at `docs/audits/2026-11-08-ponytail-audit.md`, diffed against the 2026-10-09
prior, with every finding triaged (`FIX-NOW` / `CHARTER` / `ACCEPT`). The audit changes
nothing else — it is a research dispatch: findings, receipts, and recommendations only.

## Background

- The prior audit (2026-10-09, reconstructed 2026-10-14) was produced outside the repository
  and its findings 6–8 are permanently lost (`docs/audits/2026-10-09-ponytail-audit.md` §4).
  Two standing rules inherit from that lesson: **the report is committed in-repo**, and
  **new findings take new numbers** — never renumber into the 6–8 gap; overlap with the prior
  report is cross-referenced by class, not by number.
- Since that audit: the 2026-11-06/07 incident (twelve feature commits discarded and archived
  at `archive/2026-11-07/*`, per the postmortem §11), and a post-incident fix arc that landed
  in plain sessions without a map — PRs #178–#183 (arbiter slug-split/gate-env/drain-halt
  #179, prior-art borrows #178, async-gate flake #180, attn-err #181, base-red log window
  #182, base-timeout + worktree sweep #183). None of that fresh code has been audited.
- Method: the ponytail repo-audit method (the `ponytail-audit` skill where the seat has it) —
  bugs, security holes, what breaks under real load, risky code without tests, slow paths,
  and what to delete, merge, or split. Ranked, each finding explained in plain English,
  one-shot report, changes nothing.

## Done-Criteria

1. Audit scope is the whole production surface: `bin/stampede`, `herdr-loop-swarm.sh`,
   `loop-bot-herd.sh`, all `lib/*.sh` / `lib/*.py` / `lib/cli/*.sh`, `Makefile`, `scripts/`,
   plus test-suite health (risky code without tests). Findings ranked by severity, each in
   plain English with the risk named.
2. The report is committed **in-repo** at `docs/audits/2026-11-08-ponytail-audit.md`, dated,
   with scope and status stated up front (the 2026-10-09 report was lost because it lived
   outside the repo — do not repeat that).
3. Every finding carries a receipt (`file:line`, command output, or commit sha). Every
   overlap with the 2026-10-09 report is cross-referenced by class; the report states that
   prior findings 6–8 are void and that its own numbering is independent of them.
4. A triage table closes the report: each finding marked `FIX-NOW` (small, safe — docs,
   tests, or trivial), `CHARTER` (needs a real ticket), or `ACCEPT` (accepted-limit, one-line
   rationale). Nothing is implemented inside this dispatch — follow-on work is looper's to
   charter (Single-Ticket Scope Guardrail).
5. The audit reads `docs/audits/2026-11-07-swarm-postmortem.md` §11 first and does not
   re-litigate settled decisions (the discards stay discarded). `ARB-TREE-CACHE-1` may be
   re-raised — its own refile condition ("after the arbiter fixes") is now met — but only as
   a triaged finding, not a built one.
6. `make check` green; the commit is docs-class (rides the REV-06 fast path; no code, no
   test changes).

## Verification Step

```bash
make check && test -f docs/audits/2026-11-08-ponytail-audit.md
```
