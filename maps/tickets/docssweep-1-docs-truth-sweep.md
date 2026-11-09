---
id: DOCSWEEP-1
title: "Docs truth sweep — public and state docs match the repo as it actually is"
type: wayfinder:doc
status: resolved
assignee: agy-docs
owns: README.md,CHANGELOG.md,STATE.md,CONTEXT.md,HANDOFF.md,LEGACY.md,docs/user-guide.md
parent: maps/repo-truth-pass.md
---

# DOCSWEEP-1 -- clean up and update the documentation

## Intended Outcome

Every public- and state-facing document tells the truth about the repository as of this
milestone: commands shown are commands that run and behave as described, STATE.md carries
a current checkpoint, CHANGELOG's `[Unreleased]` is a faithful two-way record of what
landed since `[0.6.0]`, incident-era files are current or explicitly marked archival, and
README links the new lib guide. A reader coming cold to the repo after the 2026-11-07
incident finds no doc contradicting the code.

## Background

- STATE.md's freshest checkpoint is 2026-11-05 — pre-incident. Since then: the incident
  itself (twelve commits discarded, §11), the plain-session arbiter-fix arc (PRs #178–#183,
  merged at `71b23e6` and ancestors), and this milestone's own tickets.
- CHANGELOG `[Unreleased]` currently carries AUTOPILOT-1 and the four prior-art borrows;
  nothing yet records the arbiter fixes (#166/#164/#172 via PR #179, #180–#183 follow-ons)
  or the post-incident work. Two-way check required: `git log` since `[0.6.0] — 2026-11-05`
  vs the entries, both directions.
- HANDOFF.md still carries branch-local incident-era notes; LEGACY.md preserves the old
  README by design. Sweep decides per file: bring current, or mark archival with a
   one-line banner — never silent deletion (they are incident/legacy evidence).
- Precedent and method: HORIZON-4/ROUTE-5 docs-sweep tickets; receipts or it didn't
  happen — every command documented is verified by running it (`bin/stampede <cmd>
  --help` or reading the current wrapper) before the sweep claims it true.

## Done-Criteria

1. STATE.md: new dated checkpoint section at the top recording this milestone's receipts
   (audit committed, lib guide published, sweep green — with shas) plus the current
   suites count and `make check` status.
2. README.md: truth pass — every command shown runs as shown on the current tree
   (autopilot, attention, arbiter, headless, status); the role/model table matches
   `swarm.config.toml` defaults; add one link line to `docs/lib-guide.md` for
   contributors (LIBDOC-1's deliverable).
3. docs/user-guide.md: section-by-section verification against current behavior —
   especially §11 (headless batch mode) against post-0.6.0 changes; drift fixed, not
   noted.
4. CHANGELOG.md: `[Unreleased]` reconciled two-way against `git log` since
   `[0.6.0] — 2026-11-05` — nothing shipped is missing, nothing listed failed to land.
   **No version bump**: VERSION stays `0.6.0` until the human releases; `make
   version-check` stays green.
5. HANDOFF.md and LEGACY.md: each either brought current or given a one-line archival
   banner naming what it preserves. No deletions.
6. CONTEXT.md: verify the vocabulary is current against the shipped surface (§4
   one-project-slug, §15 grilling rule already landed); update only where drift is
   found — this is a check, not a rewrite.
7. Every behavioral claim in the touched docs is backed by a receipt (command output or
   file:line) cited in the ticket resolution notes or commit message.
8. `make check` green; `make version-check` green; docs-only commit (REV-06 fast path —
   no code or test changes ride along).

## Verification Step

```bash
make check && make version-check
```

## Resolution
Resolved in commit `31e444a`. CHANGELOG, banners, and CLI doc alignment. Review PASS in .herdr-swarm/reviews/DOCSWEEP-1-31e444a.md.
