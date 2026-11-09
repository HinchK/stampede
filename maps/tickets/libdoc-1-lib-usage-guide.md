---
id: LIBDOC-1
title: "Publish docs/lib-guide.md — what every lib/* tool is for and how it is meant to be used"
type: wayfinder:doc
status: backlog
assignee: arch
owns: docs/lib-guide.md,CONTRIBUTING.md,CLAUDE.md
parent: maps/repo-truth-pass.md
---

# LIBDOC-1 -- the lib/ usage guide

## Intended Outcome

A single committed reference — `docs/lib-guide.md` — that tells any seat, contributor, or
curious human what each of the 31 files under `lib/` is **for**, who consumes it, what its
public surface is, and how the modules compose into the two run modes. Linked from
`CONTRIBUTING.md` and `CLAUDE.md`. After this ticket, "how is lib/quota.sh supposed to be
used?" has one canonical in-repo answer.

## Background

- Today the only in-repo guidance for lib/ is `CLAUDE.md`'s ~10-line command cheat-sheet
  (lines ~50–59) plus scattered ADRs (0001–0019) that explain *decisions*, not *surface*.
  Nothing answers, per module: what is this for, who sources it, what may I call, and what
  is off-limits.
- Scale of the gap: 20 modules in `lib/` plus 11 wrappers in `lib/cli/`, 9,140 lines,
  ~171 public functions (counted 2026-11-08: `grep -cE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)'`).
- Why now: the 2026-11-07 postmortem shows agents building features without a shared model
  of the surface (`docs/audits/2026-11-07-swarm-postmortem.md` §5 — self-added ledgers,
  speculative schemas colliding with real ones). A per-module contract document is
  prevention-of-recurrence infrastructure, the same role CONTEXT.md's vocabulary plays for
  terminology.
- Sequenced after AUDIT-1 so the guide documents the tree the audit has already assessed —
  if the audit's triage marks a module delete/merge/split as `FIX-NOW`, the guide should
  not enshrine the pre-fix shape (looper may resequence if AUDIT-1's triage comes back
  clean for lib/).

## Done-Criteria

1. `docs/lib-guide.md` covers **every** file under `lib/` — `lib/*.sh` (20), `lib/*.py`
   (4), `lib/cli/*.sh` (11) — no exceptions. A coverage table up top lists all 31; each
   has its own section.
2. Per module: (a) one-paragraph purpose in plain English — what it is for, when you'd
   touch it; (b) consumers, by name (launcher `herdr-loop-swarm.sh`, supervisor
   `loop-bot-herd.sh`, specific `lib/cli/*` wrappers, sibling modules, or "human-run
   directly"); (c) the contract: sourced vs executed, subcommands if it is an entry;
   (d) public function inventory with one-line behavior notes. Underscore-prefixed
   helpers are summarized as a count, not enumerated (they are not surface).
3. A short "how it composes" section: the config → environment → launcher flow (expand
   `CLAUDE.md`'s existing narrative, cite `lib/config.sh`), which modules the interactive
   pane mode and the headless batch mode share (ADR 0015), and how each `lib/cli/*`
   wrapper maps onto the lib module beneath it.
4. Truth bar — document what IS, as of the ticket's sha, verified mechanically:
   - every function the guide names greps in its cited module;
   - no aspirational, planned, or "should" behavior appears anywhere in the guide.
   The verifying one-liners run as part of the ticket's Verification Step below, and their
   output is pasted into the resolution notes.
5. `CONTRIBUTING.md` links the guide from its "libraries in `lib/`" paragraph (line ~5);
   `CLAUDE.md`'s command cheat-sheet points to the guide for full contracts. Edits to
   both are additive pointer lines only — no rewrites of existing guidance.
6. No `README.md` edit (that link is DOCSWEEP-1's, keeping `owns:` disjoint).
7. `make check` green; docs-only commit (rides the REV-06 fast path).

## Verification Step

```bash
make check
# coverage: every lib file appears in the guide's table
diff <(ls lib/*.sh lib/*.py lib/cli/*.sh | sed 's|lib/||' | sort) \
     <(grep -oE '^\| `[^`]+`' docs/lib-guide.md | sed 's/^| `//; s/`//' | sort)
```
