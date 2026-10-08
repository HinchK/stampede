---
id: HERDR-1
title: "Herdr surface audit: every call site vs installed CLI, keep/adopt/drop receipts"
type: wayfinder:task
status: backlog
assignee: arch
owns: docs/findings/herdr-surface-audit.md
parent: maps/herdr-native-and-seat-utilization.md
---

# HERDR-1 -- audit every herdr invocation against the installed CLI

## Intended Outcome

A findings document, `docs/findings/herdr-surface-audit.md`, that inventories **every**
`herdr ...` invocation in this repo (shell sources, briefs templates, docs that show
commands) and grades each against the installed binary (`herdr --version`) and the
0.9.3 CLI reference (https://herdr.dev/llms.txt → CLI reference), with one of three
verdicts: **keep** (right primitive), **adopt** (a better primitive exists — name it
and the seam), **drop** (dead/legacy — name the removal ticket or PR note).

## Background

Epic charter 2026-10-07 (maps/herdr-native-and-seat-utilization.md); the retrospective
found at least one legacy seam (the `sleep 1 && send-keys enter` double-submit after
`agent prompt` in `lib/briefs.sh:119-123`) and two never-used primitives
(`agent explain`, `pane wait-output`). This audit is the receipt layer that keeps
HERDR-2..5 from guessing — and catches anything the charter did not.

## Done-Criteria

1. Inventory table: call site (`file:line`) → current invocation → verdict → citation
   (installed-binary help output or doc section), covering at minimum:
   `herdr-loop-swarm.sh`, `loop-bot-herd.sh`, every `lib/*.sh`, every `briefs/*.in.md`,
   `scripts/*.sh`, and user-facing docs that print herdr commands.
2. The known seams are graded explicitly: brief-delivery double-enter; harvest scan
   (`loop-bot-herd.sh` `harvest_verdicts`); quota probe read (`lib/quota.sh:40`);
   seat-verify waits (`herdr-loop-swarm.sh` verify path); lifecycle waits
   (`lib/lifecycle.sh:582-587`; `lib/briefs.sh:115`).
3. Alternate-screen read behavior (0.9.3: `--lines N` mouse-scroll history for idle
   full-screen agents; default 80 rows) is assessed for every `agent read`/`pane read`
   call site — anchored lines must not be assumable to live in the last 80 rows.
4. Any verdict that implies a code change gets a one-line pointer to its ticket
   (HERDR-2..5) or a note that it needs a new ticket.

## Verification Step

`make check` green (docs-only change rides the REV-06 fast path). Human/pm spot-check:
pick 3 rows of the table at random and confirm the cited help output matches the
installed binary.

## Notes

Findings-only output; no code changes in this ticket. Audit runs against the *live*
binary via `--help` probes, not memory of docs.
