# P3-2 Spec — Task Intake File Partition Checking (`pm`)

**Date:** 2026-09-19 · **Against:** `main` @ `bd2392f`
**Implements:** `docs/audits/2026-09-19-phase3-concurrent-fanout-roadmap.md` §1.2 (roadmap numbering calls this P3-1;
this spec follows the looper's **P3-2** label — same deliverable, `lib/partition.sh`).
**Prior art:** `partition_check` in `loop-bot-herd-claude/herdr-loop-claude-pm.sh` (tab-separated tasks file, path↔owner
collision scan). **Evidence:** probes against the shipped libs, quoted inline.

## 0. Two findings from the review that shape this spec

1. **Frontmatter is parsed line-by-line as `key: value`** (`lib/gh_sync.sh:273-276`: `line.split(":", 1)`, value
   stripped of quotes). A YAML block list under `owns:` would parse as an empty string and every subsequent `- path`
   line would be discarded. **So `owns` must be a single comma-separated line**, matching the existing
   `prototype_asset: lib/worktree.sh,tests/test_worktree.sh` convention.
2. **`tests/test_worktree.sh` is flaky on exactly the path Phase 3 leans on.** Observed **1 failure in 6 runs (~17%)**:
   `✗ 5 concurrent provisions all succeed` / `✗ 5 parallel worktrees + branches all present`, then 5/5 clean reruns.
   Plain `git worktree add` measured 0/12 failures in the Phase 2 advisory, so the race is in `worktree_provision`'s
   own compound sequence (`show-ref` → `add` → `lock`), not in git's add. **This is not a P3-2 defect, but it blocks the
   replica-seating ticket** — file it now, before N-way seating makes it routine. It also means intermittent red on `main`.

---

## 1. `owns:` declaration

```yaml
---
id: P3-2
title: "Task Intake File Partition Checking"
status: in_progress
owns: lib/partition.sh,tests/test_partition.sh,docs/adr/
---
```

**Grammar.** One line, comma-separated, repo-relative. Whitespace around entries is trimmed. Three entry forms:

| Form | Example | Means |
|---|---|---|
| file | `lib/partition.sh` | exactly that path |
| directory prefix (trailing `/`) | `docs/adr/` | that directory and everything beneath it |
| glob | `tests/test_*.sh` | `fnmatch` against repo-relative paths; `*` does not cross `/`, `**` does |

**Normalization (before any comparison).** Strip a leading `./`; collapse `//`; reject absolute paths, `..` segments,
and anything resolving outside the repo (fail-closed, with the offending entry named). Compare **casefolded**, because
macOS checkouts are case-insensitive by default and `lib/Foo.sh` and `lib/foo.sh` are the same file there.

**Empty vs absent** are different: `owns:` present but empty is a malformed ticket (reject at intake); `owns` absent is
the fallback path in §4.

## 2. Overlap semantics

Two tickets conflict when any entry of one intersects any entry of the other. Intersection is **deliberately
over-approximate** — a false conflict costs a serialized dispatch, a missed conflict costs a corrupted merge.

| Pair | Rule |
|---|---|
| file vs file | equal paths |
| file vs dir prefix | file is under the prefix |
| dir vs dir | either is a prefix of the other (`lib/` ⊃ `lib/sub/`) |
| glob vs file/dir | `fnmatch`, plus expansion against the current work tree |
| **glob vs glob** | conflict if their **literal prefixes** (text before the first wildcard) overlap by the dir rule, **or** their expansions against the work tree intersect. Undecidable cases resolve to *conflict* |

Globs are expanded against the tree at intake, but expansion alone is not authoritative: a ticket may *create* files
that don't exist yet. That is why literal-prefix comparison runs as well.

**Self-check at intake:** the same ticket listing overlapping entries (`lib/` and `lib/foo.sh`) is a warning, not an
error — it is redundant, not dangerous. Duplicate ticket ids remain a hard error (carried over from the prototype).

## 3. Intake conflict detection and fail-closed dispatch

### 3.1 The active set

A candidate is checked against every ticket that could have a worker touching files right now:

- ticket files whose `status` is in the **active set**, and
- every live **lease** in `.herdr-swarm/leases.json` (§3.2).

Status mapping — note the repo currently uses five values (`backlog`, `in_progress`, `done`, `resolved`, `closed`):

| Status | Treated as |
|---|---|
| `in_progress` | **active** |
| `backlog`, `ready` | inactive (not yet dispatched) |
| `resolved`, `done`, `closed` | inactive **only if** the ticket's work has integrated (`integration.jsonl` has `integrated`/`promoted` for it, or it has no `owns`) |
| anything else / unparseable | **active** (fail-closed) |

The `resolved`-but-not-integrated case matters: a worker's branch can be green and waiting in the arbiter queue while
its files are still unmerged. Releasing the lease at "resolved" would let a second worker start from a base that lacks
those commits — the roadmap's conflict-manufacturing scenario. **Leases release on integration, not on verdict.**

### 3.2 Leases

`.herdr-swarm/leases.json`, written by the dispatcher through one locked, atomic writer (same `mkdir` lock +
temp-file-`mv` pattern as `arbiter_lock`, so it is bash 3.2 / macOS safe):

```json
{"version": 1, "leases": [
  {"ticket": "P3-2", "seat": "arch-1-repo", "owns": ["lib/partition.sh", "tests/test_partition.sh"],
   "exclusive": false, "acquired_at": "2026-09-19T…", "branch": "swarm/repo/arch-1"}
]}
```

- **Acquire** happens *before* the prompt is dispatched, in the same locked section as the conflict check. Checking and
  acquiring separately is a TOCTOU race that two dispatchers would lose.
- **Release** on: arbiter `integrated`, ticket abandoned, or seat teardown. `status` reconciles: a lease whose seat is
  no longer in `seats.json` is reported as **stale** and released with a warning (never silently).
- Crash-safe: leases are the durable record; a restarted supervisor reads them rather than re-deriving from panes.

### 3.3 Dispatch decision

```
dispatch_candidate(ticket):
  lock leases
  owns = parse_owns(ticket)                  # §4 when absent
  for each active ticket/lease L:
      if overlaps(owns, L.owns) or L.exclusive or owns.exclusive:
          record dispatch.blocked{ticket, blocked_by: L.ticket, paths: <intersection>}
          unlock; return BLOCKED
  acquire lease; unlock; dispatch to worker
```

- **Blocked ⇒ the ticket stays in `ready`/`backlog`.** It is never partially dispatched, never queued into a worker's
  pane "to start later", and never silently reordered into a different seat. The looper moves to the next
  non-conflicting ticket on the frontier; if none exists, the herd runs below `max_workers`, which is correct.
- The block is **reported with the intersecting paths and the blocking ticket**, so the human can split the ticket or
  wait. A blocked ticket is retried on the next frontier pass with no backoff — the unblock event is an integration,
  which is already observable.
- Telemetry: `dispatch.blocked` / `lease.acquired` / `lease.released` events, and `status` gains a Leases block.

### 3.4 Post-hoc drift check (cheap, catches the lie)

A declaration is a promise, not a fact. After a **green** verdict, compare what the worker actually touched against what
it declared:

```bash
git -C "$GATE_DIR" diff --name-only "$base_sha".."$sha"
```

Files outside the declared `owns` ⇒ record `owns_violation` on the verdict (with the file list) and surface it to the
human. **Do not auto-retire and do not auto-block the integration**: by then the work exists and the arbiter's gate is
the real safety net. This is the feedback loop that keeps declarations honest, and it is how `owns` lists get corrected.

## 4. Tickets without `owns`

**Every one of the repo's ~32 existing tickets lacks `owns`.** A hard refusal would stop the herd dead on the first
un-annotated ticket, so the fallback is **serialized exclusive execution**, not rejection:

- A ticket with no `owns` acquires an **exclusive whole-repo lease**: it dispatches only when *no other* lease is held,
  and while it is held no other ticket dispatches — i.e. exactly today's single-worker behaviour.
- It is still fail-closed in the safety sense: the unknown is treated as "owns everything", never as "owns nothing".
  The failure mode is lost throughput, which is visible and recoverable; the alternative failure mode is a corrupted merge.
- `status` and the dispatch log report **why** the herd is running at one worker (`serialized: P2-9 declares no owns`),
  so the fix is obvious.
- Migration: `lib/partition.sh suggest <ticket>` proposes an `owns` line from a resolved ticket's actual diff
  (`git diff --name-only base..branch`), for a human to paste in. New tickets from `w`/`b` modes get `owns` written by
  the looper at creation; a ticket template change lands with this ticket.

Recommended escalation once the backlog is annotated: a config flag `[fanout] require_owns = true` flips the fallback
from serialized to refused, so an un-annotated ticket becomes a loud authoring error instead of a silent throughput cliff.

## 5. Interface

```
lib/partition.sh check <ticket-id|file> [<ticket-id|file> …]   # pairwise; exit 1 on conflict, prints intersections
lib/partition.sh check --tasks <file>                          # prototype-compatible tab-separated form
lib/partition.sh can-dispatch <ticket-id>                      # vs live leases + active tickets; exit 0/1/2(no owns)
lib/partition.sh lease acquire|release|list [<ticket-id>]      # locked, atomic
lib/partition.sh suggest <ticket-id>                           # propose owns from the branch diff
```

Pure-function core (`parse_owns`, `normalize`, `overlaps`) is sourceable and unit-testable with no git or herdr present —
those are the functions where the bugs will be.

## 6. Acceptance (`tests/test_partition.sh`)

| # | Case | Expected |
|---|---|---|
| 1 | `lib/a.sh` vs `lib/b.sh` | no conflict |
| 2 | `lib/a.sh` vs `lib/a.sh` | conflict |
| 3 | `lib/` vs `lib/sub/a.sh` | conflict (dir prefix) |
| 4 | `tests/test_*.sh` vs `tests/test_partition.sh` | conflict (glob) |
| 5 | `lib/*.sh` vs `lib/*.py` | conflict (literal prefixes overlap — over-approximation is intended) |
| 6 | `docs/adr/` vs `docs/audits/` | no conflict |
| 7 | `lib/Foo.sh` vs `lib/foo.sh` | conflict (casefolded) |
| 8 | `../outside`, `/etc/passwd` | rejected at parse, entry named |
| 9 | YAML block list under `owns:` | rejected with "use a comma-separated line" (guards §0.1) |
| 10 | candidate vs a live lease | BLOCKED, intersection reported, ticket stays `ready` |
| 11 | ticket `resolved` but not integrated | lease still held; candidate blocked |
| 12 | no-`owns` ticket with another lease live | not dispatched; with none live, dispatched exclusive |
| 13 | two dispatchers racing one lease file | exactly one acquires (locked section) |
| 14 | lease whose seat vanished from `seats.json` | reported stale and released with a warning |
| 15 | green verdict touching an undeclared file | `owns_violation` recorded, integration not blocked |

## 7. Decisions needed

1. **Confirm the fallback** is serialized-exclusive (recommended) rather than refuse-to-dispatch, given no ticket is annotated yet.
2. **`require_owns` timing:** flip it on once the active backlog carries `owns`, or leave it off indefinitely?
3. **Who writes `owns` for new tickets** — the looper at ticket creation (recommended) or `arch` as part of charter?
4. **File the concurrent-provision flake (§0.2)** as its own ticket before replica seating lands.
