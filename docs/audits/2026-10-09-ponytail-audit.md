# Ponytail Repo Audit — 2026-10-09

**Date:** 2026-10-09 (recorded 2026-10-14) · **Author:** `ponytail-audit` (second, merged report) ·
**Scope:** whole repository · **Status:** 1–5 fixed and merged · 9 fixed, awaiting promote · 6–8 **unrecovered**

> **This document is a reconstruction, not the original report.** The audit was produced outside the repository
> and its full text no longer exists anywhere reachable. Findings 1–5 are recovered verbatim in substance from
> the body of [PR #121](https://github.com/HinchK/stampede/pull/121); finding 9 survives through
> `HANDOFF.md:22` on `fix/audit-must-fix-1-5`. Findings 6, 7 and 8 are lost — §4 records the search rather
> than guessing at them. Nothing below is re-derived or inferred: every entry cites the artifact it came from.
>
> It exists because the repo's convention is a dated audit doc per review, and without one the only in-repo
> trace of this audit was a parenthetical in a branch-local handoff file. Future audits now have a prior to
> diff against, even a partial one.

---

## 1. Must-fix findings 1–5 — fixed, merged in PR #121 (`8600166`)

Source: PR #121 body. Each landed as its own commit.

### 1. The arbiter gated a tree it had failed to check out — `49a61a9` (`lib/arbiter.sh`)

`_arb_worktree` swallowed every git failure, and because `_arb_integrate` runs under `if !`, `set -e` was off
too. With a stale `index.lock` in the arbiter worktree the suite ran on the **previous** tree, passed, and the
integration ref advanced to a commit whose own suite exits 1 — a false green manufactured by the component
whose job is to prevent them. It now returns 1 unless the checkout succeeded and HEAD is the wanted commit,
leaving the record `queued` (the same truthful outcome as the missing-`timeout` case).

It also refuses when the worktree folder has lost its `.git` link: git then resolves to the root repo, and the
old code detached the human's root checkout onto the candidate commit.

### 2. A re-verdict after a review BLOCK or arbiter hand-back was skipped forever — `3d6cc2f` (`loop-bot-herd.sh`)

`harvest_verdicts` retired a ticket permanently on its first green record. With the review loop on (the
shipped default), the worker's fix after a BLOCK arrives as a **new sha** and was ignored. The retire rule now
stands aside while the review state is `critique_dispatched`, or the ticket's latest queue record is
`conflict` or `integration_red`. The `(ticket, sha)` dedupe is untouched.

### 3. Seats were addressed by names that do not exist — `3fd8e28`, lint follow-up `688a706`

`looper_notice` prompted the bare name `looper` behind `|| true`; seats are named `looper-<slug>`.
`{{ARCH_NAME}}` was bound from `SEAT_NAME_arch`, which the config never emits, so briefs named `arch-<slug>`
while the real seats are `arch-1-<slug>` / `arch-2-<slug>`. Touched `loop-bot-herd.sh`, `lib/briefs.sh`,
`lib/standby.sh`.

### 4. The launcher died when no directory was passed — `0b04335` (`herdr-loop-swarm.sh`)

`CLI_DIR` was read under `set -u` with no default, so the **documented default form** exited with
`CLI_DIR: unbound variable`.

### 5. The brief renderer pasted values into Python source — `9481b25` (`lib/briefs.sh`)

`substitute_template` interpolated paths and JSON into a `python -c` string, so a test command containing a
double quote (`pytest -k "not slow"`) or a path with an apostrophe broke the launch. It now passes argv with a
quoted heredoc, matching `config_dump_env`.

### Extra, found while fixing the above: arbiter telemetry was never written — `cc7adcb`

`_arb_telemetry` passed its arguments in the wrong order, the payload failed to parse, and `|| true` hid it.
**No `arbiter.*` event had reached a trace since the arbiter landed.** Not an audit finding; recorded here
because it shipped in the same PR.

---

## 2. Finding 9 — workers were never told why the arbiter rejected them

**Source:** `HANDOFF.md:22` on `fix/audit-must-fix-1-5`, verbatim: *"Fix 2 makes a re-verdict after
`conflict` / `integration_red` possible, but the worker is still never told about those (audit finding 9, not
in this branch)."*

Finding 2 unblocked the re-verdict path; nothing supplied the reason. The arbiter drain runs as its own
background process, so neither its stderr nor its exit code reaches a seat — the only durable trace is the
record in `integration.jsonl`. A worker whose ticket was handed back either sat idle or re-submitted the same
sha.

**Fixed** in `063e41c` (`arbiter_handback_feedback` in `loop-bot-herd.sh`, 6 assertions as case 19 in
`tests/test_async_gate.sh`). Currently on branch `fix/audit-9-handback-feedback`; **not yet promoted to
`main`**.

---

## 3. Unnumbered surviving thread — stale rendered briefs

**Source:** `HANDOFF.md:23`, verbatim: *"Rendered briefs under `.herdr-swarm/briefs/` stay stale until the
next `up`."* Also listed as a risk in PR #121.

Recorded as its own thread because the handoff names it alongside finding 9 without a number; whether the
original report numbered it is unknown. **Open** — no ticket in `maps/tickets/` addresses it and no commit
mentions it.

---

## 4. Findings 6, 7 and 8 — unrecovered

These were referenced by number (the audit's must-fix set stopped at 5, and finding 9 is attested) but their
text exists nowhere reachable. Searched on 2026-10-14, all exhausted:

| Source | Result |
|---|---|
| `gh pr view 121 --json body` | findings 1–5 + the telemetry extra only |
| `gh api .../pulls/121/reviews` | 0 |
| `gh api .../pulls/121/comments` | 0 |
| `gh api .../issues/121/comments` | none |
| `gh search issues --repo HinchK/stampede 'audit finding'` | no matching issue |
| `git log --all --grep=audit -i` / `--grep=ponytail` | the fix commits only, no finding text |
| Tracked tree, any ref, any branch | no `2026-10-09*` or report file ever added |
| Agent session transcripts, 2026-10-08 → 2026-10-14 | only quotations of `HANDOFF.md`'s finding-9 line |

**Do not reconstruct them by re-auditing and renumbering.** A fresh pass would produce different findings
wearing the numbers 6–8, which is worse than a gap: it would make this document lie, and a later audit would
diff against fiction. If the next audit finds something in this class, give it a new number and note that 6–8
of this report are void.

---

## 5. Provenance

Reconstructed 2026-10-14 from PR #121's body, `HANDOFF.md` on `fix/audit-must-fix-1-5`, and
`git log --all --grep`. Every claim is traceable to one of those; §4 is the record of what could not be.
