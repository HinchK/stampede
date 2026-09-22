---
id: PUB-3
title: "Journey-ordered user guide (docs/user-guide.md)"
type: wayfinder:task
status: ready
assignee: arch
owns: docs/user-guide.md
parent: maps/public-multi-provider.md
blocked_by: PUB-1
---

# PUB-3 — User guide: zero to first verified verdict (Wave 9)

## 1. Intended Outcome

`docs/user-guide.md` walks a stranger from a stock machine to one
supervisor-gated green verdict, in reading order, with no prior exposure to
this repo's vocabulary. Every fenced command either runs as written or is
explicitly marked with what it needs (a provider CLI, a GitHub remote).

## 2. Problem

The README explains the architecture and defends the thesis; CONTEXT.md
defines vocabulary for the herd itself. Neither is ordered by the *user's*
journey. Onboarding docs currently assume the authors' mental model.

## 3. Plan

Sections in journey order:

1. Prerequisites — bash 3.2+, `jq`, git, Python ≥3.11, Herdr; per-provider
   install pointers for claude / opencode / agy (links only, one provider
   suffices).
2. `make check` — prove the tool itself is green before trusting it.
3. `stampede doctor` — what healthy looks like.
4. Configure seats — annotated `swarm.config.toml` walkthrough (hand-edit
   path; `stampede init` pointer marked "landing in PUB-7").
5. Seat the swarm — `up -m s`, `verify`, reading the Ops telemetry pane.
6. First ticket — hand-dispatch one demo ticket (PUB-4's repo) to one
   worker; what the supervisor does next.
7. Read the verdict — `.herdr-swarm/session-verdicts.jsonl`, RED re-verdict
   protocol.
8. Integrate — `arbiter drain`, human promote, why the human is the only
   one who moves `main`.
9. Troubleshooting matrix — every fail-closed exit mapped to cause → fix.

## 4. Explicit Done-Criteria

- A reader with one provider CLI can reach a first green verdict using
  only this guide plus the demo repo.
- Zero machine-local paths (the DOG-9 rule), zero unverifiable claims
  (the DOG-4/DOG-5 rule).
- Guide cross-links ADRs for the *why* without duplicating them.

## 5. Verification Step

```bash
grep -n 'file://\|/Users/' docs/user-guide.md ; echo "rc=$? (want 1)"
make check
```
